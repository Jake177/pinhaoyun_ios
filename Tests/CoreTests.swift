import XCTest
import SwiftData
import UIKit
@testable import PinHaoYun

final class CoreTests: XCTestCase {
    func testLegacyMixedLibraryDecodesAndUsesCaptureTimeline() throws {
        let data = Data(#"{"videos":[{"id":"photo-1","type":"PHOTO","originalName":"IMG_001.HEIC","originalPhotoUrl":"https://example.invalid/original","liveVideoUrl":"https://example.invalid/live","captureTime":"2025-01-02T03:04:05Z","createdAt":"2026-10-08T00:00:00Z"},{"id":"video-1","type":"VIDEO","fileLastModified":"2024-01-01T00:00:00.000Z"}],"nextCursor":null,"hasMore":false}"#.utf8)
        let page = try JSONDecoder().decode(LibraryPage.self, from: data)
        XCTAssertEqual(page.videos.count, 2)
        XCTAssertTrue(page.videos[0].isLivePhoto)
        XCTAssertEqual(page.videos[0].date, MediaItem.parseDate("2025-01-02T03:04:05Z"))
        XCTAssertEqual(page.videos[1].date, MediaItem.parseDate("2024-01-01T00:00:00Z"))
    }
    @MainActor func testDurableMultipartAndLivePairStateRoundTrips() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = ModelConfiguration(url: folder.appendingPathComponent("transfers.sqlite"))
        let photo = UploadComponent(filePath: "asset/original.heic", fileName: "original.heic", contentType: "image/heic", size: 1024, mediaType: "PHOTO", mediaRole: "image", photoId: "pair")
        var motion = UploadComponent(filePath: "asset/live.mov", fileName: "live.mov", contentType: "video/quicktime", size: 30_000_000, mediaType: "PHOTO", mediaRole: "liveVideo", photoId: "pair")
        motion.uploadId = "persisted-upload"; motion.key = "photo/owner@example.invalid/pair_live.mov"
        motion.parts = [UploadedPart(partNumber: 1, etag: "\"etag\"")]
        let record = try TransferRecord(ownerSub: "owner", displayName: "Live Photo", components: [photo, motion])
        record.componentIndex = 1; record.state = "uploading"
        try persist(record, configuration: configuration)
        let reopened = try ModelContainer(for: TransferRecord.self, configurations: configuration)
        let saved = try XCTUnwrap(ModelContext(reopened).fetch(FetchDescriptor<TransferRecord>()).first)
        XCTAssertEqual(saved.components[1].uploadId, "persisted-upload")
        XCTAssertEqual(saved.components[1].parts.first?.etag, "\"etag\"")
        XCTAssertEqual(saved.components[0].photoId, saved.components[1].photoId)
        XCTAssertEqual(saved.componentIndex, 1)
        XCTAssertEqual(saved.ownerSub, "owner")
    }
    @MainActor private func persist(_ record: TransferRecord, configuration: ModelConfiguration) throws {
        let container = try ModelContainer(for: TransferRecord.self, configurations: configuration)
        let context = ModelContext(container)
        context.insert(record); try context.save()
    }
    func testDeletionReceiptSurvivesSecureStorageRoundTrip() throws {
        let key = "test-receipt-" + UUID().uuidString
        defer { Keychain.remove(account: key) }
        let receipt = DeletionReceipt(requestId: "request", receipt: "secret-proof", requestedAt: "2026-10-08T00:00:00Z", deleteBy: "2026-11-07T00:00:00Z", state: "PENDING")
        try Keychain.save(receipt, account: key)
        let saved = try XCTUnwrap(Keychain.read(DeletionReceipt.self, account: key))
        XCTAssertEqual(saved.receipt, receipt.receipt)
        Keychain.remove(account: key)
        XCTAssertNil(try Keychain.read(DeletionReceipt.self, account: key))
    }

    @MainActor func testNativeBackgroundUploadAgainstIsolatedAWS() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["PH_INTEGRATION_EMAIL"] ?? env["TEST_RUNNER_PH_INTEGRATION_EMAIL"],
              let password = env["PH_INTEGRATION_PASSWORD"] ?? env["TEST_RUNNER_PH_INTEGRATION_PASSWORD"] else { throw XCTSkip("Run explicitly with disposable localhost integration credentials.") }
        guard email.hasPrefix("ios-qa-"), email.hasSuffix("@example.invalid") else { XCTFail("Only synthetic development accounts may be used"); return }
        let api = APIClient(baseURL: URL(string: "http://127.0.0.1:3000")!)
        try await api.signIn(email: email, password: password)
        XCTAssertFalse(api.tokens!.requiresConsent)
        let container = try ModelContainer(for: TransferRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let manager = TransferManager(api: api, container: container, identifier: "com.jake177.pinhaoyun.integration." + UUID().uuidString)
        let folderName = UUID().uuidString, photoId = UUID().uuidString.lowercased()
        let folder = TransferManager.filesRoot.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor(hue: CGFloat.random(in: 0...1), saturation: 0.7, brightness: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let bytes = try XCTUnwrap(image.pngData())
        try bytes.write(to: folder.appendingPathComponent("QA-native.png"))
        let component = UploadComponent(filePath: folderName + "/QA-native.png", fileName: "QA-native.png", contentType: "image/png", size: Int64(bytes.count), mediaType: "PHOTO", mediaRole: "image", photoId: photoId)
        try manager.enqueue(displayName: "QA native upload", components: [component], owner: api.tokens!.sub)
        let deadline = Date.now.addingTimeInterval(90)
        while Date.now < deadline {
            if let record = manager.records().first, ["completed", "failed"].contains(record.state) { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        let record = try XCTUnwrap(manager.records().first)
        XCTAssertEqual(record.state, "completed", record.message ?? "Native background upload did not complete")
        guard record.state == "completed" else { await manager.cancel(record); return }
        XCTAssertTrue(record.components.first?.notified == true)
        let links: MediaURLs = try await api.request("/api/media/urls", method: "POST", body: ["id": photoId, "type": "PHOTO"])
        let file = try await api.download(try XCTUnwrap(links.originalPhotoUrl ?? links.originalUrl), extension: "png")
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        // The generated QA image remains in the isolated account for visual QA.
    }
}
