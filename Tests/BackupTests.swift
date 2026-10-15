import XCTest
import SwiftData
@testable import PinHaoYun

final class BackupTests: XCTestCase {
    @MainActor func testInterruptedPreparationAdoptsDurableTransferAndOnlyRemovesOrphans() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let tracked = directory.appendingPathComponent("tracked"), orphan = directory.appendingPathComponent("orphan"), manualFolder = directory.appendingPathComponent("manual")
        for folder in [tracked, orphan, manualFolder] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); try Data([1, 2, 3]).write(to: folder.appendingPathComponent("original.png")) }
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(for: TransferRecord.self, BackupAsset.self, BackupSettings.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let asset = BackupAsset(settingsKey: "test|owner", assetIdentifier: "asset", kind: "PHOTO"); asset.preparationFolder = "tracked"
        let incomplete = BackupAsset(settingsKey: "test|owner", assetIdentifier: "incomplete", kind: "PHOTO"); incomplete.preparationFolder = "orphan"
        let component = UploadComponent(filePath: "tracked/original.png", fileName: "original.png", contentType: "image/png", size: 3, mediaType: "PHOTO", mediaRole: "image")
        let record = try TransferRecord(ownerSub: "owner", displayName: "prepared", components: [component]); record.source = "automatic"; record.environment = "test"; record.localAssetIdentifier = "asset"; record.state = "paused"
        var manualComponent = component; manualComponent.filePath = "manual/original.png"
        let manual = try TransferRecord(ownerSub: "owner", displayName: "manual", components: [manualComponent]); manual.state = "failed"
        for value in [asset, incomplete] { context.insert(value) }; for value in [record, manual] { context.insert(value) }; try context.save()
        reconcileBackupAssets([asset, incomplete], records: [record, manual], owner: "owner", environment: "test")
        XCTAssertEqual(asset.transferID, record.id); XCTAssertEqual(asset.state, "queued")
        cleanBackupPreparation([tracked, orphan, manualFolder], records: [record, manual], context: context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tracked.appendingPathComponent("original.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manualFolder.appendingPathComponent("original.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertNil(incomplete.preparationFolder)
        XCTAssertEqual(incomplete.state, "pending")
        record.state = "completed"
        reconcileBackupAssets([asset], records: [record], owner: "owner", environment: "test")
        XCTAssertEqual(asset.state, "completed")
    }
    func testWindowCrossesMidnightAndFollowsDaylightSavingAndTravel() throws {
        let format = ISO8601DateFormatter()
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let overnight = BackupWindow(enabled: true, start: 22 * 60, end: 6 * 60)
        XCTAssertTrue(overnight.contains(format.date(from: "2026-10-08T23:00:00Z")!, calendar: utc))
        XCTAssertTrue(overnight.contains(format.date(from: "2026-10-09T05:59:00Z")!, calendar: utc))
        XCTAssertFalse(overnight.contains(format.date(from: "2026-10-09T06:00:00Z")!, calendar: utc))
        XCTAssertFalse(BackupWindow(enabled: true, start: 120, end: 120).valid)
        var sydney = utc; sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let morning = BackupWindow(enabled: true, start: 120, end: 360)
        XCTAssertFalse(morning.contains(format.date(from: "2026-10-03T15:59:00Z")!, calendar: sydney))
        XCTAssertTrue(morning.contains(format.date(from: "2026-10-03T16:00:00Z")!, calendar: sydney))
        XCTAssertEqual(morning.nextStart(after: format.date(from: "2026-10-03T14:00:00Z")!, calendar: sydney), format.date(from: "2026-10-03T16:00:00Z"))
        XCTAssertEqual(morning.nextStart(after: format.date(from: "2027-04-03T14:00:00Z")!, calendar: sydney), format.date(from: "2027-04-03T15:00:00Z"))
        let travelling = format.date(from: "2026-10-08T18:30:00Z")!
        XCTAssertTrue(morning.contains(travelling, calendar: sydney))
        XCTAssertFalse(morning.contains(travelling, calendar: utc))
    }
    @MainActor func testBackupLedgerAndPolicySurviveReopeningWithoutMarkingPendingAsComplete() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let schema = Schema([TransferRecord.self, BackupSettings.self, BackupAsset.self])
        let config = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("ledger.store"))
        func write() throws {
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)
            let settings = BackupSettings(key: "environment|owner")
            XCTAssertFalse(settings.enabled); XCTAssertFalse(settings.cellular); XCTAssertFalse(settings.videos); XCTAssertFalse(settings.windowEnabled)
            settings.baselineReady = true
            context.insert(settings)
            context.insert(BackupAsset(settingsKey: settings.key, assetIdentifier: "old-photo", kind: "PHOTO", baseline: true, presentAtActivation: true))
            context.insert(BackupAsset(settingsKey: settings.key, assetIdentifier: "imported-old-photo-after-activation", kind: "PHOTO"))
            context.insert(BackupAsset(settingsKey: "other|owner", assetIdentifier: "other-environment", kind: "PHOTO"))
            try context.save()
        }
        try write()
        let reopened = try ModelContainer(for: schema, configurations: config)
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<BackupAsset>())
        XCTAssertEqual(rows.first { $0.assetIdentifier == "old-photo" }?.state, "baseline")
        XCTAssertEqual(rows.first { $0.assetIdentifier == "imported-old-photo-after-activation" }?.state, "pending")
        XCTAssertFalse(rows.contains { $0.state == "completed" })
        let legacy = try TransferRecord(ownerSub: "owner", displayName: "legacy", components: [])
        XCTAssertEqual(legacy.source, "manual")
        let skipped = try JSONDecoder().decode(UploadStart.self, from: Data(#"{"duplicate":false,"skipped":true,"skipReason":"CLOUD_DELETED"}"#.utf8))
        XCTAssertTrue(skipped.skipped == true)
    }
    @MainActor func testPausingAutomaticTransfersKeepsOriginalsPartsAndManualWork() async throws {
        let url = URL(string: "https://pause-" + UUID().uuidString + ".invalid")!
        defer { Keychain.remove(account: "session:" + url.absoluteString) }
        let api = APIClient(baseURL: url)
        try api.saveTokens(AuthTokens(idToken: "id", accessToken: "access", refreshToken: "refresh", expiresIn: 60, username: "owner", sub: "owner", email: "owner@example.invalid", requiresConsent: false))
        let container = try ModelContainer(for: TransferRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let manager = TransferManager(api: api, container: container, identifier: "pause." + UUID().uuidString)
        manager.automaticGate = { _ in "Waiting for Wi-Fi" }
        let folderName = UUID().uuidString, folder = TransferManager.filesRoot.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("photo.png"); try Data(repeating: 1, count: 12).write(to: file)
        let component = UploadComponent(filePath: folderName + "/photo.png", fileName: "photo.png", contentType: "image/png", size: 12, mediaType: "PHOTO", mediaRole: "image", uploadId: "preserved-upload", parts: [UploadedPart(partNumber: 1, etag: "preserved-etag")])
        let automatic = try TransferRecord(ownerSub: "owner", displayName: "automatic", components: [component]); automatic.source = "automatic"
        let manual = try TransferRecord(ownerSub: "owner", displayName: "manual", components: [component]); manual.state = "failed"
        manager.context.insert(automatic); manager.context.insert(manual); try manager.context.save()
        await manager.enforceAutomaticPolicy()
        XCTAssertEqual(automatic.state, "paused"); XCTAssertEqual(manual.state, "failed")
        XCTAssertEqual(automatic.components.first?.uploadId, "preserved-upload")
        XCTAssertEqual(automatic.components.first?.parts.first?.etag, "preserved-etag")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    @MainActor func testRefreshTransportFailureRetainsCredentialsButRevocationClearsThem() async throws {
        for permanent in [false, true] {
            RefreshFailureProtocol.configure(permanent: permanent)
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RefreshFailureProtocol.self]
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            let url = URL(string: "https://refresh-" + UUID().uuidString + ".invalid")!
            defer { Keychain.remove(account: "session:" + url.absoluteString) }
            let api = APIClient(baseURL: url, session: session)
            try api.saveTokens(AuthTokens(idToken: "id", accessToken: "access", refreshToken: "refresh", expiresIn: 60, username: "owner", sub: "owner", email: "owner@example.invalid", requiresConsent: false))
            do { let _: OKResponse = try await api.request("/fixture"); XCTFail("Expected refresh failure") } catch { }
            XCTAssertEqual(api.tokens == nil, permanent)
        }
    }
}

private final class RefreshFailureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var permanent = false
    static func configure(permanent: Bool) { lock.withLock { Self.permanent = permanent } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url!.path.hasSuffix("refresh"), !Self.lock.withLock({ Self.permanent }) {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":"Expired","code":"NotAuthorizedException"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
