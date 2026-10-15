import XCTest
import SwiftData
import UIKit
@testable import PinHaoYun

final class CoreTests: XCTestCase {
    func testAuthenticationInputValidationAndLegacyPolicyCompatibility() throws {
        XCTAssertTrue(AuthInput.validEmail("tester+photos@example.com"))
        for value in ["", "tester", "tester@example", "tester @example.com", "a@@example.com"] { XCTAssertFalse(AuthInput.validEmail(value)) }
        XCTAssertTrue(AuthInput.validNewPassword("Example-pass!2026"))
        for value in ["short", "alllowercase1!", "ALLUPPERCASE1!", "NoNumbers!", "NoSymbols2026", "BlankSymbol2026 "] { XCTAssertFalse(AuthInput.validNewPassword(value)) }
        XCTAssertTrue(AuthInput.validResetPassword("Example-pass!2026", confirmation: "Example-pass!2026"))
        XCTAssertFalse(AuthInput.validResetPassword("Example-pass!2026", confirmation: ""))
        XCTAssertFalse(AuthInput.validResetPassword("Example-pass!2026", confirmation: "Example-pass!2027"))
        XCTAssertFalse(AuthInput.validResetPassword("Example-pass!2026", confirmation: "example-pass!2026"))
        XCTAssertFalse(AuthInput.validResetPassword("weak", confirmation: "weak"))
        let policy = try JSONDecoder().decode(PolicyDocument.self, from: Data(#"{"version":"legacy","isDraft":true,"terms":{"en":"terms"},"privacy":{"en":"privacy"}}"#.utf8))
        XCTAssertNil(policy.reading)
        XCTAssertEqual(policy.termsText, "terms")
    }
    @MainActor func testPhotoZoomKeepsAspectRatioAndAccessibleZoomLimits() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 400)).image { _ in UIColor.blue.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 800, height: 400)) }
        let view = PhotoZoomView(frame: CGRect(x: 0, y: 0, width: 375, height: 600))
        view.setImage(image); view.layoutIfNeeded()
        XCTAssertEqual(view.contentSize.width, 375, accuracy: 0.1)
        XCTAssertEqual(view.contentSize.height, 187.5, accuracy: 0.1)
        view.accessibilityIncrement(); XCTAssertEqual(view.zoomScale, 1.5, accuracy: 0.01)
        for _ in 0..<20 { view.accessibilityIncrement() }
        XCTAssertEqual(view.zoomScale, 4, accuracy: 0.01)
        for _ in 0..<20 { view.accessibilityDecrement() }
        XCTAssertEqual(view.zoomScale, 1, accuracy: 0.01)
    }
    @MainActor func testAccountErasurePreservesQueueUntilServerAcceptance() async throws {
        for responseStatus in [503, 200] {
            DeletionFixtureProtocol.configure(status: responseStatus)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DeletionFixtureProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let url = URL(string: "https://deletion-fixture-" + UUID().uuidString + ".invalid")!
            defer { Keychain.remove(account: "session:" + url.absoluteString); Keychain.remove(account: "deletion:" + url.absoluteString) }
            let api = APIClient(baseURL: url, session: session)
            try api.saveTokens(DeletionFixtureProtocol.tokens)
            let container = try ModelContainer(for: TransferRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let manager = TransferManager(api: api, container: container, identifier: "com.jake177.pinhaoyun.deletion-test." + UUID().uuidString)
            let folderName = UUID().uuidString
            let folder = TransferManager.filesRoot.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let original = folder.appendingPathComponent("fixture.png")
            try Data(repeating: 1, count: 12).write(to: original)
            let component = UploadComponent(filePath: folderName + "/fixture.png", fileName: "fixture.png", contentType: "image/png", size: 12, mediaType: "PHOTO", mediaRole: "image")
            let pending = try TransferRecord(ownerSub: "fixture-owner", displayName: "pending", components: [component]); pending.state = "failed"; pending.completedBytes = 4
            let history = try TransferRecord(ownerSub: "fixture-owner", displayName: "history", components: [component]); history.state = "completed"
            let otherFolderName = UUID().uuidString
            let otherFolder = TransferManager.filesRoot.appendingPathComponent(otherFolderName)
            try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: otherFolder) }
            let otherOriginal = otherFolder.appendingPathComponent("other.png")
            try Data(repeating: 2, count: 8).write(to: otherOriginal)
            var otherComponent = component; otherComponent.filePath = otherFolderName + "/other.png"
            let other = try TransferRecord(ownerSub: "other-owner", displayName: "other", components: [otherComponent]); other.state = "completed"
            for record in [pending, history, other] { manager.context.insert(record) }
            try manager.context.save()
            do {
                try await requestAccountDeletion(api: api, transfers: manager, password: "mock-only")
                XCTAssertEqual(responseStatus, 200)
                XCTAssertNil(api.tokens)
                XCTAssertEqual(manager.records().map(\.ownerSub), ["other-owner"])
                XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
                XCTAssertNotNil(api.deletionReceipt)
            } catch {
                XCTAssertEqual(responseStatus, 503, error.localizedDescription)
                XCTAssertEqual(manager.records().count, 3)
                XCTAssertEqual(pending.state, "failed")
                XCTAssertEqual(pending.completedBytes, 4)
                XCTAssertEqual(history.state, "completed")
                XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
                XCTAssertNotNil(api.tokens)
                XCTAssertEqual(api.deletionReceipt?.state, "REQUESTING")
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: otherOriginal.path))
        }
    }
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
    @MainActor func testReturningToSignInPreservesDeletionProof() throws {
        let url = URL(string: "https://receipt-" + UUID().uuidString + ".invalid")!
        let key = "deletion:" + url.absoluteString
        defer { Keychain.remove(account: key) }
        let receipt = DeletionReceipt(requestId: "request", receipt: "secret-proof", requestedAt: "2026-10-08T00:00:00Z", deleteBy: "2026-11-07T00:00:00Z", state: "PENDING", ownerSub: "owner")
        try Keychain.save(receipt, account: key)
        let api = APIClient(baseURL: url)
        api.dismissReceipt()
        XCTAssertNil(api.deletionReceipt)
        XCTAssertTrue(api.hasSavedDeletionReceipt)
        api.restoreReceipt()
        XCTAssertEqual(api.deletionReceipt?.receipt, receipt.receipt)
    }
    @MainActor func testConfirmedSignOutCancellationKeepsTransferHistory() async throws {
        let url = URL(string: "https://signout-" + UUID().uuidString + ".invalid")!
        defer { Keychain.remove(account: "session:" + url.absoluteString) }
        let api = APIClient(baseURL: url)
        try api.saveTokens(AuthTokens(idToken: "synthetic", accessToken: "synthetic", refreshToken: "synthetic", expiresIn: 60, username: "owner", sub: "owner", email: "owner@example.invalid", requiresConsent: false))
        let container = try ModelContainer(for: TransferRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let manager = TransferManager(api: api, container: container, identifier: "com.jake177.pinhaoyun.history." + UUID().uuidString)
        let folder = UUID().uuidString
        let component = UploadComponent(filePath: folder + "/fixture.png", fileName: "fixture.png", contentType: "image/png", size: 12, mediaType: "PHOTO", mediaRole: "image")
        let completed = try TransferRecord(ownerSub: "owner", displayName: "completed", components: [component]); completed.state = "completed"
        let unfinished = try TransferRecord(ownerSub: "owner", displayName: "unfinished", components: [component]); unfinished.state = "failed"
        manager.context.insert(completed); manager.context.insert(unfinished); try manager.context.save()
        await manager.cancelUnfinishedForSignOut()
        XCTAssertEqual(manager.records().count, 2)
        XCTAssertEqual(completed.state, "completed")
        XCTAssertEqual(unfinished.state, "cancelled")
    }

    @MainActor func testNativeBackgroundUploadAgainstIsolatedAWS() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["PH_INTEGRATION_EMAIL"] ?? env["TEST_RUNNER_PH_INTEGRATION_EMAIL"],
              let password = env["PH_INTEGRATION_PASSWORD"] ?? env["TEST_RUNNER_PH_INTEGRATION_PASSWORD"] else { throw XCTSkip("Run explicitly with disposable localhost integration credentials.") }
        guard email.hasPrefix("ios-qa-"), email.hasSuffix("@example.invalid") else { XCTFail("Only synthetic development accounts may be used"); return }
        let base = env["PH_INTEGRATION_BASE_URL"] ?? env["TEST_RUNNER_PH_INTEGRATION_BASE_URL"] ?? "http://127.0.0.1:3000"
        let api = APIClient(baseURL: URL(string: base)!)
        let priorSession = api.tokens
        defer { restoreIntegrationSession(priorSession, api: api, environment: env) }
        try await api.signIn(email: email, password: password)
        if api.tokens?.requiresConsent == true {
            let policy: PolicyDocument = try await api.request("/api/mobile/policies", authenticated: false)
            try await api.accept(policy)
        }
        XCTAssertFalse(api.tokens!.requiresConsent)
        let before: UserProfile = try await api.request("/api/user/profile")
        let container = try ModelContainer(for: TransferRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let manager = TransferManager(api: api, container: container, identifier: "com.jake177.pinhaoyun.integration." + UUID().uuidString)
        let folderName = UUID().uuidString, photoId = UUID().uuidString.lowercased()
        let folder = TransferManager.filesRoot.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor(hue: CGFloat.random(in: 0...1), saturation: 0.7, brightness: 0.8, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            (UUID().uuidString as NSString).draw(at: CGPoint(x: 1, y: 1), withAttributes: [.font: UIFont.systemFont(ofSize: 6), .foregroundColor: UIColor.white])
        }
        let bytes = try XCTUnwrap(image.pngData())
        try bytes.write(to: folder.appendingPathComponent("QA-native.png"))
        let component = UploadComponent(filePath: folderName + "/QA-native.png", fileName: "QA-native.png", contentType: "image/png", size: Int64(bytes.count), mediaType: "PHOTO", mediaRole: "image", photoId: photoId)
        try manager.enqueue(displayName: "QA native upload", components: [component], owner: api.tokens!.sub)
        // Reopening/scene activation may overlap initialization of an upload.
        await manager.resume()
        await manager.resume()
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
        let after: UserProfile = try await api.request("/api/user/profile")
        XCTAssertEqual(after.usedBytes - before.usedBytes, Int64(bytes.count))
        // The generated QA image remains in the isolated account for visual QA.
    }
    @MainActor func testNativeAutomaticQueueSkipsDeletedCloudContent() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["PH_INTEGRATION_EMAIL"] ?? env["TEST_RUNNER_PH_INTEGRATION_EMAIL"],
              let password = env["PH_INTEGRATION_PASSWORD"] ?? env["TEST_RUNNER_PH_INTEGRATION_PASSWORD"] else { throw XCTSkip("Enable explicitly with synthetic isolated integration credentials.") }
        guard email.hasPrefix("ios-qa-"), email.hasSuffix("@example.invalid") else { XCTFail("Only synthetic development accounts may be used"); return }
        let base = env["PH_INTEGRATION_BASE_URL"] ?? env["TEST_RUNNER_PH_INTEGRATION_BASE_URL"] ?? "http://127.0.0.1:3000"
        let api = APIClient(baseURL: URL(string: base)!)
        let priorSession = api.tokens
        defer { restoreIntegrationSession(priorSession, api: api, environment: env) }
        try await api.signIn(email: email, password: password)
        if api.tokens?.requiresConsent == true {
            let policy: PolicyDocument = try await api.request("/api/mobile/policies", authenticated: false); try await api.accept(policy)
        }
        let before: UserProfile = try await api.request("/api/user/profile")
        let container = try ModelContainer(for: TransferRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let manager = TransferManager(api: api, container: container, identifier: "automatic-integration." + UUID().uuidString)
        // This checks the real automatic transport, not PhotoKit scanning or hardware scheduling.
        manager.automaticGate = { _ in nil }
        manager.automaticCellularAllowed = true
        let marker = UUID().uuidString
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
            (marker as NSString).draw(at: CGPoint(x: 1, y: 1), withAttributes: [.font: UIFont.systemFont(ofSize: 6), .foregroundColor: UIColor.white])
        }
        let bytes = try XCTUnwrap(image.pngData())
        func enqueue() throws -> TransferRecord {
            let folderName = UUID().uuidString, folder = TransferManager.filesRoot.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent("QA-auto.png"))
            let component = UploadComponent(filePath: folderName + "/QA-auto.png", fileName: "QA-auto.png", contentType: "image/png", size: Int64(bytes.count), mediaType: "PHOTO", mediaRole: "image", photoId: UUID().uuidString.lowercased())
            let id = try manager.enqueue(displayName: "QA automatic transport", components: [component], owner: api.tokens!.sub, source: "automatic", assetIdentifier: "synthetic-" + UUID().uuidString)
            return manager.records().first { $0.id == id }!
        }
        func settle(_ record: TransferRecord) async throws {
            let deadline = Date(timeIntervalSinceNow: 90)
            while !record.isFinished && record.state != "failed" && Date.now < deadline { try await Task.sleep(for: .milliseconds(200)) }
        }
        let first = try enqueue(); await manager.resume(); await manager.resume(); try await settle(first)
        XCTAssertEqual(first.state, "completed", first.message ?? "Automatic transport incomplete")
        guard first.state == "completed" else { await manager.cancel(first); return }
        let photoID = try XCTUnwrap(first.components.first?.photoId)
        let after: UserProfile = try await api.request("/api/user/profile")
        XCTAssertEqual(after.usedBytes - before.usedBytes, Int64(bytes.count))
        let _: OKResponse = try await api.request("/api/videos/delete", method: "POST", body: ["mediaId": photoID, "mediaType": "PHOTO"])
        let second = try enqueue(); try await settle(second)
        XCTAssertEqual(second.state, "skipped", second.message ?? "Expected automatic suppression")
        XCTAssertEqual(second.skipReason, "CLOUD_DELETED")
        XCTAssertTrue(second.components.allSatisfy { $0.uploadId == nil })
        let deadline = Date(timeIntervalSinceNow: 60)
        var final: UserProfile = try await api.request("/api/user/profile")
        while final.usedBytes != before.usedBytes && .now < deadline {
            try await Task.sleep(for: .seconds(1)); final = try await api.request("/api/user/profile")
        }
        XCTAssertEqual(final.usedBytes, before.usedBytes)
    }
    @MainActor private func restoreIntegrationSession(_ prior: AuthTokens?, api: APIClient, environment: [String: String]) {
        #if targetEnvironment(simulator)
        if (environment["PH_KEEP_QA_SESSION"] ?? environment["TEST_RUNNER_PH_KEEP_QA_SESSION"]) == "1" { return }
        #endif
        api.clearTokens()
        if let prior { try? api.saveTokens(prior) }
    }
}

private final class DeletionFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var deletionStatus = 503
    static var tokens: AuthTokens { AuthTokens(idToken: "mock-id", accessToken: "mock-access", refreshToken: "mock-refresh", expiresIn: 60, username: "fixture-owner", sub: "fixture-owner", email: "fixture@example.invalid", requiresConsent: false) }
    static func configure(status: Int) { lock.withLock { deletionStatus = status } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let status = path.hasSuffix("sign-in") ? 200 : Self.lock.withLock { Self.deletionStatus }
        let data: Data
        if path.hasSuffix("sign-in") { data = try! JSONEncoder().encode(Self.tokens) }
        else if status == 200 {
            data = Data(#"{"requestId":"fixture","receipt":"mock-proof","requestedAt":"2026-10-09T00:00:00Z","deleteBy":"2026-11-08T00:00:00Z","state":"PENDING"}"#.utf8)
        } else { data = Data(#"{"error":"Fixture service unavailable"}"#.utf8) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
