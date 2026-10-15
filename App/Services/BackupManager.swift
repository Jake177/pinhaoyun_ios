import SwiftUI
import SwiftData
@preconcurrency import Photos
import Network
import BackgroundTasks
import UniformTypeIdentifiers
import Observation

private struct BackupCandidate: Sendable {
    let id: String
    let kind: String
}

@MainActor @Observable final class BackupManager: NSObject, PHPhotoLibraryChangeObserver {
    static let taskIdentifier = "com.jake177.pinhaoyun.backup"
    let api: APIClient
    let transfers: TransferManager
    var settings: BackupSettings?
    var permission = PHPhotoLibrary.authorizationStatus(for: .readWrite) { didSet { if permission != oldValue { forceFullScan = true } } }
    var scanning = false
    var preparationError: String?
    var revision = 0
    private var network = "unavailable"
    private let monitor = NWPathMonitor()
    private var work: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private var needsScan = false
    private var forceFullScan = false
    private var backgroundProcessing = false
    private var preparingIdentifier: String?
    private var boundKey: String?
    private var notifications: [NSObjectProtocol] = []
    private let startupFolders: [URL]
    private var cleanedStartup = false
    private var observingPhotos = false
    @ObservationIgnored private var cachedAssets: [BackupAsset] = []
    @ObservationIgnored private var cachedKey: String?
    @ObservationIgnored private var cachedRevision = -1
    private var context: ModelContext { transfers.context }
    var hasPermission: Bool { permission == .authorized || permission == .limited }
    var window: BackupWindow { BackupWindow(enabled: settings?.windowEnabled ?? false, start: settings?.startMinute ?? 120, end: settings?.endMinute ?? 360) }
    var diagnosticsURL: URL? { settings.map { BackupDiagnostics.url(key: $0.key) } }
    var assets: [BackupAsset] {
        guard let key = settings?.key else { return [] }
        if cachedKey != key || cachedRevision != revision {
            cachedAssets = (try? context.fetch(FetchDescriptor<BackupAsset>(predicate: #Predicate { $0.settingsKey == key }, sortBy: [SortDescriptor(\.createdAt)]))) ?? []
            cachedKey = key; cachedRevision = revision
        }
        return cachedAssets
    }
    var eligibleAssets: [BackupAsset] { assets.filter { $0.state != "baseline" && ($0.kind != "VIDEO" || settings?.videos == true || $0.startedAt != nil || $0.transferID != nil) } }
    var status: String {
        if settings?.enabled != true { return String(localized: "Automatic backup is off") }
        if let reason = preparationError { return reason }
        let active = transfers.records().filter { $0.source == "automatic" && $0.ownerSub == api.tokens?.sub && $0.environment == api.baseURL?.absoluteString && !$0.isFinished }
        if gate(nil) != nil && active.contains(where: { $0.startedAt != nil && gate($0) == nil && ["uploading", "finalizing", "waiting"].contains($0.state) }) { return String(localized: "Finishing started backups") }
        if let reason = gate(nil) { return reason }
        if !active.isEmpty && active.allSatisfy({ $0.state == "paused" || $0.state == "failed" }), let reason = active.first(where: { $0.pauseReason != nil })?.pauseReason { return reason }
        if scanning { return String(localized: "Checking your Photos library") }
        if eligibleAssets.contains(where: { $0.state == "failed" }) { return String(localized: "Some originals need attention") }
        if active.contains(where: { $0.state == "retryWaiting" }) { return String(localized: "Retrying later") }
        return eligibleAssets.contains(where: { ["pending", "queued"].contains($0.state) }) ? String(localized: "Backing up your originals") : String(localized: "Backup is up to date")
    }
    init(api: APIClient, transfers: TransferManager) {
        self.api = api; self.transfers = transfers
        startupFolders = (try? FileManager.default.contentsOfDirectory(at: TransferManager.filesRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        super.init()
        transfers.automaticGate = { [weak self] record in
            guard let self else { return String(localized: "Automatic backup is off") }
            return self.gate(record)
        }
        transfers.onRecordChange = { [weak self] in self?.reconcile(); self?.check() }
        transfers.onAccountDeletion = { [weak self] owner in self?.clear(owner: owner) }
        monitor.pathUpdateHandler = { [weak self] path in
            let kind = path.status != .satisfied ? "unavailable" : (path.isConstrained ? "constrained" : (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) ? "wifi" : "cellular"))
            Task { @MainActor [weak self] in
                guard let self else { return }; self.network = kind
                if self.gate(nil) != nil { self.work?.cancel() }
                await self.transfers.enforceAutomaticPolicy(); self.check()
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.jake177.pinhaoyun.network"))
        for name in [NSNotification.Name.NSProcessInfoPowerStateDidChange, UIApplication.significantTimeChangeNotification, NSNotification.Name.NSSystemTimeZoneDidChange] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in guard let self else { return }; await self.transfers.enforceAutomaticPolicy(); self.check(); self.schedule() }
            })
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: .main) { [weak self] task in
            Task { @MainActor [weak self] in
                guard let self else { task.setTaskCompleted(success: false); return }
                let job = Task { @MainActor in
                    self.backgroundProcessing = true
                    defer { self.backgroundProcessing = false }
                    await self.activate(); self.check(); await self.work?.value; await self.transfers.resume(); self.schedule(); task.setTaskCompleted(success: !Task.isCancelled)
                }
                task.expirationHandler = { job.cancel(); Task { @MainActor [weak backup = self] in backup?.work?.cancel() } }
            }
        }
    }
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if self.permission == .limited { self.forceFullScan = true }
            if !self.hasPermission { self.work?.cancel() }
            if self.permission == .limited, let id = self.preparingIdentifier, PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject == nil { self.work?.cancel() }
            await self.transfers.enforceAutomaticPolicy(); self.check()
        }
    }
    func activate() async {
        let key = api.tokens.map { (api.baseURL?.absoluteString ?? "") + "|" + $0.sub }
        if boundKey != key {
            if boundKey != nil { await stopForSignOut() }
            boundKey = key; settings = nil
            if let key {
                settings = (try? context.fetch(FetchDescriptor<BackupSettings>(predicate: #Predicate { $0.key == key })))?.first
                if settings == nil { let value = BackupSettings(key: key); context.insert(value); try? context.save(); settings = value }
            }
        }
        let previousPermission = permission
        permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        updatePhotoObservation()
        if permission != previousPermission || permission == .limited { forceFullScan = true }
        transfers.automaticCellularAllowed = settings?.cellular ?? false
        await transfers.enforceAutomaticPolicy()
        if !cleanedStartup { cleanedStartup = true; await transfers.resume(); cleanStartupPreparation() }
        reconcile(); check(); schedule()
        if clock == nil {
            clock = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard let self else { return }
                    await self.transfers.enforceAutomaticPolicy(); self.check()
                }
            }
        }
    }
    func enable() async throws {
        guard let settings, let owner = api.tokens?.sub, api.tokens?.requiresConsent == false, window.valid else { return }
        let expectedKey = settings.key
        permission = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        updatePhotoObservation()
        guard hasPermission else { return }
        guard self.settings?.key == expectedKey, api.tokens?.sub == owner else { throw CancellationError() }
        if !settings.baselineReady {
            scanning = true; defer { if self.settings?.key == expectedKey { scanning = false } }
            let token = PHPhotoLibrary.shared().currentChangeToken
            let initial = try await Self.candidates(token: nil)
            try Task.checkCancellation()
            guard self.settings?.key == expectedKey, api.tokens?.sub == owner else { throw CancellationError() }
            let existing = Set(assets.map(\.assetIdentifier))
            for asset in assets where asset.transferID == nil { asset.presentAtActivation = true; asset.state = settings.scope == "new" ? "baseline" : "pending" }
            for (index, candidate) in initial.enumerated() where !existing.contains(candidate.id) {
                guard self.settings?.key == expectedKey, api.tokens?.sub == owner else { throw CancellationError() }
                context.insert(BackupAsset(settingsKey: settings.key, assetIdentifier: candidate.id, kind: candidate.kind, baseline: settings.scope == "new", presentAtActivation: true))
                if index % 250 == 0 { try context.save(); await Task.yield(); try Task.checkCancellation() }
            }
            guard self.settings?.key == expectedKey, api.tokens?.sub == owner else { throw CancellationError() }
            settings.scanToken = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            settings.baselineReady = true
        }
        guard self.settings?.key == expectedKey, api.tokens?.sub == owner else { throw CancellationError() }
        settings.enabled = true; preparationError = nil; try context.save(); settingsChanged()
    }
    func settingsChanged() {
        guard let settings else { return }
        let networkChanged = transfers.automaticCellularAllowed != settings.cellular
        transfers.automaticCellularAllowed = settings.cellular
        if settings.scope == "all" { for asset in assets where asset.state == "baseline" { asset.state = "pending" } }
        var excluded: [TransferRecord] = []
        if settings.scope == "new" {
            for asset in assets where asset.presentAtActivation && asset.startedAt == nil && ["pending", "queued"].contains(asset.state) {
                if let id = asset.transferID, let record = transfers.records().first(where: { $0.id == id }), record.startedAt == nil { excluded.append(record) }
                asset.state = "baseline"; asset.transferID = nil
            }
        }
        try? context.save(); revision += 1
        Task { for record in excluded { await transfers.cancel(record) }; await transfers.enforceAutomaticPolicy(reconfigure: networkChanged); check(); schedule() }
        if gate(nil) != nil { work?.cancel() }
    }
    func pause() async {
        settings?.enabled = false; try? context.save()
        work?.cancel(); await work?.value
        await transfers.enforceAutomaticPolicy()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier); revision += 1
    }
    func stopForSignOut() async {
        await pause()
        for asset in assets where asset.state == "queued" {
            guard let id = asset.transferID, let record = transfers.records().first(where: { $0.id == id }), !record.isFinished else { continue }
            asset.transferID = nil; asset.state = "pending"
        }
        try? context.save()
    }
    func clear(owner: String) {
        work?.cancel()
        let allSettings = (try? context.fetch(FetchDescriptor<BackupSettings>())) ?? []
        let keys = Set(allSettings.filter { $0.key.hasSuffix("|" + owner) }.map(\.key))
        for asset in (try? context.fetch(FetchDescriptor<BackupAsset>())) ?? [] where keys.contains(asset.settingsKey) {
            if let folder = asset.preparationFolder { try? FileManager.default.removeItem(at: TransferManager.filesRoot.appendingPathComponent(folder)) }
            context.delete(asset)
        }
        for value in allSettings where keys.contains(value.key) {
            try? FileManager.default.removeItem(at: BackupDiagnostics.url(key: value.key)); context.delete(value)
        }
        if let key = settings?.key, keys.contains(key) { settings = nil; boundKey = nil }
        try? context.save(); schedule()
    }
    func retryIssues() {
        preparationError = nil
        Task {
            for asset in assets where asset.state == "failed" {
                if let id = asset.transferID, let record = transfers.records().first(where: { $0.id == id }), !record.isFinished {
                    if record.skipReason == "LOCAL_ORIGINAL_MISSING" {
                        asset.transferID = nil; asset.state = "pending"; await transfers.cancel(record)
                    } else { asset.state = "queued"; transfers.retry(record) }
                } else { asset.state = "pending"; asset.transferID = nil }
                asset.message = nil
            }
            try? context.save(); check()
        }
    }
    func check() {
        permission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        updatePhotoObservation()
        if let key = settings?.key { BackupDiagnostics.record(key: key, status: preparationError == nil ? status : "preparation-needs-attention", assets: eligibleAssets, network: network, window: window, backgroundProcessing: backgroundProcessing) }
        let continuing = assets.contains { $0.state == "pending" && $0.startedAt != nil }
        guard settings?.enabled == true, api.tokens?.requiresConsent == false, gate(nil, continuing: continuing) == nil,
              UIApplication.shared.applicationState == .active || backgroundProcessing else { return }
        if work != nil { needsScan = true; return }
        work = Task { [weak self] in
            guard let self else { return }
            defer { self.work = nil; self.scanning = false; self.revision += 1; if self.needsScan { self.needsScan = false; self.check() } }
            do { try await self.scanAndPrepare() }
            catch is CancellationError { }
            catch { self.preparationError = error.localizedDescription }
        }
    }
    private func updatePhotoObservation() {
        if hasPermission && !observingPhotos {
            PHPhotoLibrary.shared().register(self); observingPhotos = true
        } else if !hasPermission && observingPhotos {
            PHPhotoLibrary.shared().unregisterChangeObserver(self); observingPhotos = false
        }
    }
    private func gate(_ record: TransferRecord?, continuing: Bool = false) -> String? {
        if let record, record.ownerSub != api.tokens?.sub || record.environment != api.baseURL?.absoluteString { return String(localized: "Automatic backup is off") }
        guard settings?.enabled == true, let owner = api.tokens?.sub, boundKey?.hasSuffix("|" + owner) == true else { return String(localized: "Automatic backup is off") }
        guard api.tokens?.requiresConsent == false else { return String(localized: "Review terms before backup") }
        guard hasPermission else { return String(localized: "Allow Photos access to resume backup") }
        if permission == .limited, let id = record?.localAssetIdentifier, PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject == nil { return String(localized: "Allow access to this photo to resume its backup, or cancel this transfer.") }
        if network == "unavailable" { return String(localized: "Waiting for network") }
        if network == "constrained" { return String(localized: "Waiting for Low Data Mode to end") }
        if network != "wifi" && settings?.cellular != true { return String(localized: "Waiting for Wi-Fi") }
        if record?.startedAt == nil && !continuing {
            if settings?.scope == "new", let id = record?.localAssetIdentifier, let key = settings?.key {
                let assetKey = key + "|" + id
                if (try? context.fetch(FetchDescriptor<BackupAsset>(predicate: #Predicate { $0.key == assetKey })))?.first?.presentAtActivation == true { return String(localized: "Outside the selected backup scope") }
            }
            if ProcessInfo.processInfo.isLowPowerModeEnabled { return String(localized: "Waiting for Low Power Mode to end") }
            if record?.components.first?.mediaType == "VIDEO" && settings?.videos != true { return String(localized: "Video backup is off") }
            if !window.contains(.now) { return String(localized: "Waiting for your backup time window") }
        }
        return nil
    }
    private func reconcile() {
        reconcileBackupAssets(assets, records: transfers.records(), owner: api.tokens?.sub, environment: api.baseURL?.absoluteString ?? "")
        try? context.save(); revision += 1
    }
    private func scanAndPrepare() async throws {
        guard let settings, let owner = api.tokens?.sub else { return }
        let expectedKey = settings.key
        scanning = true
        let token = forceFullScan ? nil : settings.scanToken
        let nextToken = PHPhotoLibrary.shared().currentChangeToken
        let canScan = gate(nil) == nil
        let found = canScan ? try await Self.candidates(token: token) : []
        if canScan { forceFullScan = false }
        try Task.checkCancellation()
        guard self.settings?.key == expectedKey, api.tokens?.sub == owner else { throw CancellationError() }
        let existing = Set(assets.map(\.assetIdentifier))
        for (index, candidate) in found.enumerated() where !existing.contains(candidate.id) {
            context.insert(BackupAsset(settingsKey: settings.key, assetIdentifier: candidate.id, kind: candidate.kind))
            if index % 250 == 0 { try context.save(); await Task.yield(); try Task.checkCancellation() }
        }
        // Scan checkpoints advance only after every candidate has a durable ledger row.
        // Completed backup is tracked separately and only follows server finalization.
        if canScan {
            settings.scanToken = try NSKeyedArchiver.archivedData(withRootObject: nextToken, requiringSecureCoding: true)
            settings.lastCheckedAt = .now
        }
        try context.save(); revision += 1; scanning = false
        for asset in assets where asset.state == "pending" && (asset.kind != "VIDEO" || settings.videos || asset.startedAt != nil) {
            try Task.checkCancellation()
            guard gate(nil, continuing: asset.startedAt != nil) == nil else { continue }
            let staged = transfers.records().filter { $0.source == "automatic" && $0.ownerSub == owner && !$0.isFinished }
            guard staged.count < 3 else { return }
            do {
                if asset.startedAt == nil { asset.startedAt = .now; try context.save() }
                if let folder = asset.preparationFolder { try? FileManager.default.removeItem(at: TransferManager.filesRoot.appendingPathComponent(folder)) }
                let folderName = UUID().uuidString
                asset.preparationFolder = folderName; try context.save()
                let components = try await export(asset.assetIdentifier, folderName: folderName)
                do {
                    try Task.checkCancellation()
                    guard gate(nil, continuing: true) == nil, api.tokens?.sub == owner else { throw CancellationError() }
                    let capturedAt = PHAsset.fetchAssets(withLocalIdentifiers: [asset.assetIdentifier], options: nil).firstObject?.creationDate
                    asset.transferID = try transfers.enqueue(displayName: components.first?.fileName ?? String(localized: "Photo"), components: components, owner: owner, source: "automatic", assetIdentifier: asset.assetIdentifier, capturedAt: capturedAt, startedAt: asset.startedAt)
                    asset.state = "queued"; asset.preparationFolder = nil; try context.save()
                } catch { Self.remove(components); throw error }
            } catch is CancellationError { throw CancellationError() }
            catch {
                guard !Task.isCancelled, self.settings?.key == expectedKey, api.tokens?.sub == owner else { throw CancellationError() }
                asset.state = "failed"; asset.message = error.localizedDescription
                asset.preparationFolder = nil
                if let error = error as? APIError, error.status == 400 { asset.state = "skipped" }
                if let error = error as? APIError, error.status == 507 { preparationError = error.localizedDescription; try context.save(); return }
                try context.save()
            }
        }
    }
    private nonisolated static func candidates(token: Data?) async throws -> [BackupCandidate] {
        let job = Task.detached(priority: .utility) {
            let options = PHFetchOptions(); options.includeHiddenAssets = false
            options.includeAllBurstAssets = true
            var identifiers = Set<String>()
            var incremental = false
            if let token, let decoded = try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: token) {
                do {
                    let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: decoded)
                    for change in changes {
                        let details = try change.changeDetails(for: .asset)
                        identifiers.formUnion(details.insertedLocalIdentifiers); identifiers.formUnion(details.updatedLocalIdentifiers)
                    }
                    incremental = true
                } catch {
                    // Never advance past unreadable history without a full reconciliation.
                    identifiers.removeAll()
                }
            }
            let result = incremental ? PHAsset.fetchAssets(withLocalIdentifiers: Array(identifiers), options: options) : PHAsset.fetchAssets(with: options)
            var found: [BackupCandidate] = []
            for index in 0..<result.count {
                try Task.checkCancellation()
                let asset = result.object(at: index)
                if !asset.isHidden && (asset.mediaType == .image || asset.mediaType == .video) { found.append(BackupCandidate(id: asset.localIdentifier, kind: asset.mediaType == .video ? "VIDEO" : "PHOTO")) }
            }
            return found
        }
        return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
    }
    private func export(_ identifier: String, folderName: String) async throws -> [UploadComponent] {
        preparingIdentifier = identifier
        defer { preparingIdentifier = nil }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject, !asset.isHidden else { throw APIError(status: 410, message: String(localized: "This original is no longer accessible in Photos."), code: nil) }
        let all = PHAssetResource.assetResources(for: asset)
        let movie = asset.mediaType == .video
        var resources = all.filter { $0.type == (movie ? .video : .photo) }.prefix(1).map { $0 }
        if asset.mediaSubtypes.contains(.photoLive) {
            guard let motion = all.first(where: { $0.type == .pairedVideo }) else { throw APIError(status: 410, message: String(localized: "The Live Photo motion resource is unavailable."), code: nil) }
            resources.append(motion)
        }
        guard !resources.isEmpty, resources.allSatisfy({ (movie ? ["mov", "mp4", "hevc", "m4v"] : ($0.type == .pairedVideo ? ["mov"] : ["jpg", "jpeg", "png", "heic", "heif"])).contains(($0.originalFilename as NSString).pathExtension.lowercased()) }) else { throw APIError(status: 400, message: String(localized: "This original format is not supported yet."), code: nil) }
        let folder = TransferManager.filesRoot.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        do {
            let photoID = movie ? nil : UUID().uuidString.lowercased()
            var components: [UploadComponent] = []
            for (index, resource) in resources.enumerated() {
                try Task.checkCancellation()
                let name = (resource.originalFilename as NSString).lastPathComponent
                let file = folder.appendingPathComponent("\(index)-" + name)
                try await PhotoResourceExport(resource: resource, url: file).run()
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                components.append(UploadComponent(filePath: folderName + "/" + file.lastPathComponent, fileName: name, contentType: UTType(resource.uniformTypeIdentifier)?.preferredMIMEType ?? "application/octet-stream", size: Int64(size), mediaType: movie ? "VIDEO" : "PHOTO", mediaRole: resource.type == .pairedVideo ? "liveVideo" : "image", photoId: photoID))
            }
            return components
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    private nonisolated static func remove(_ components: [UploadComponent]) {
        if let first = components.first { try? FileManager.default.removeItem(at: TransferManager.filesRoot.appendingPathComponent(first.filePath).deletingLastPathComponent()) }
    }
    func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        guard settings?.enabled == true, window.valid else { return }
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        let continuing = assets.contains { $0.state == "pending" && $0.startedAt != nil } || transfers.records().contains { $0.source == "automatic" && $0.ownerSub == api.tokens?.sub && $0.startedAt != nil && !$0.isFinished }
        request.earliestBeginDate = window.contains(.now) || continuing ? Date(timeIntervalSinceNow: 15 * 60) : window.nextStart(after: .now)
        try? BGTaskScheduler.shared.submit(request)
    }
    func enterBackground() {
        if !backgroundProcessing { work?.cancel() }
        schedule()
    }
    private func cleanStartupPreparation() {
        cleanBackupPreparation(startupFolders, records: transfers.records(), context: context)
    }
}

@MainActor func reconcileBackupAssets(_ assets: [BackupAsset], records allRecords: [TransferRecord], owner: String?, environment: String) {
        let records = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.id, $0) })
        var byAsset: [String: TransferRecord] = [:]
        for record in records.values where record.source == "automatic" && record.ownerSub == owner && record.environment == environment && (!record.isFinished || record.state == "completed") {
            guard let id = record.localAssetIdentifier else { continue }
            if byAsset[id] == nil || byAsset[id]!.createdAt < record.createdAt { byAsset[id] = record }
        }
        for asset in assets where asset.transferID == nil && ["pending", "failed"].contains(asset.state) {
            if let record = byAsset[asset.assetIdentifier] {
                asset.transferID = record.id; asset.state = "queued"; asset.preparationFolder = nil
            }
        }
        for asset in assets where asset.transferID != nil && ["queued", "failed"].contains(asset.state) {
            guard let id = asset.transferID, let record = records[id] else { asset.state = "pending"; asset.transferID = nil; continue }
            if record.state == "completed" { asset.state = "completed" }
            else if record.state == "failed" { asset.state = "failed"; asset.message = record.message }
            else if !record.isFinished { asset.state = "queued"; asset.message = nil }
            if ["cancelled", "skipped"].contains(record.state) { asset.state = "skipped"; asset.message = record.message }
        }
}

@MainActor func cleanBackupPreparation(_ startupFolders: [URL], records: [TransferRecord], context: ModelContext) {
        let referenced = Set(records.filter { !$0.isFinished }.flatMap { $0.components.compactMap { $0.filePath.split(separator: "/").first.map(String.init) } })
        let initial = Set(startupFolders.map(\.lastPathComponent))
        for asset in (try? context.fetch(FetchDescriptor<BackupAsset>())) ?? [] {
            if let folder = asset.preparationFolder, initial.contains(folder) {
                if !referenced.contains(folder) { try? FileManager.default.removeItem(at: startupFolders.first(where: { $0.lastPathComponent == folder })!) }
                asset.preparationFolder = nil
            }
        }
        for folder in startupFolders where !referenced.contains(folder.lastPathComponent) {
            if (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { try? FileManager.default.removeItem(at: folder) }
        }
    try? context.save()
}
