import Foundation
import SwiftData
import CryptoKit
import Observation

@MainActor @Observable final class TransferManager: NSObject, URLSessionTaskDelegate, URLSessionDelegate {
    static let partSize = 10 * 1024 * 1024
    nonisolated static var filesRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Transfers", isDirectory: true)
    }
    let api: APIClient
    let context: ModelContext
    var backgroundCompletion: (() -> Void)?
    var automaticGate: ((TransferRecord) -> String?)?
    var onRecordChange: (() -> Void)?
    var onAccountDeletion: ((String) -> Void)?
    private var retryTimer: Task<Void, Never>?
    private var activeJobs = Set<UUID>()
    private var drivers: [UUID: Task<Void, Never>] = [:]
    private var attempts: [UUID: Int] = [:]
    private var reconcile = Set<UUID>()
    private var background: URLSession!

    init(api: APIClient, container: ModelContainer, identifier: String = "com.jake177.pinhaoyun.transfers") {
        self.api = api; context = ModelContext(container); context.autosaveEnabled = false
        super.init()
        try? FileManager.default.createDirectory(at: Self.filesRoot, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var excluded = Self.filesRoot
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sessionSendsLaunchEvents = true; config.isDiscretionary = false
        config.httpMaximumConnectionsPerHost = 3; config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 24 * 3600
        background = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        for record in records() where record.environment.isEmpty { record.environment = api.baseURL?.absoluteString ?? "" }
        try? context.save()
    }
    func records() -> [TransferRecord] {
        (try? context.fetch(FetchDescriptor<TransferRecord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }
    @discardableResult func enqueue(displayName: String, components: [UploadComponent], owner: String, source: String = "manual", assetIdentifier: String? = nil, capturedAt: Date? = nil, startedAt: Date? = nil) throws -> UUID {
        guard api.tokens?.sub == owner else { throw URLError(.userAuthenticationRequired) }
        guard !components.isEmpty, components.allSatisfy({ $0.size > 0 && $0.size <= 2 * 1024 * 1024 * 1024 }) else {
            throw APIError(status: 400, message: String(localized: "Each original must be smaller than 2 GB."), code: nil)
        }
        let record = try TransferRecord(ownerSub: owner, displayName: displayName, components: components)
        record.source = source; record.localAssetIdentifier = assetIdentifier; record.capturedAt = capturedAt
        record.startedAt = startedAt
        record.environment = api.baseURL?.absoluteString ?? ""
        context.insert(record); try context.save(); kick(); return record.id
    }
    func resume() async {
        let tasks = await background.allTasks
        let unfinishedIDs = Set(records().filter { !$0.isFinished }.map(\.id))
        for task in tasks {
            let id = task.taskDescription?.split(separator: "|").first.flatMap { UUID(uuidString: String($0)) }
            if id == nil || !unfinishedIDs.contains(id!) { task.cancel() }
        }
        // Scene activation can overlap an API request before its URLSession task exists.
        // Keep those drivers active so a second resume cannot start the same record twice.
        activeJobs.formIntersection(unfinishedIDs)
        activeJobs.formUnion(tasks.compactMap { $0.taskDescription?.split(separator: "|").first.flatMap { UUID(uuidString: String($0)) } }.filter { unfinishedIDs.contains($0) })
        activeJobs.formUnion(drivers.keys)
        for record in records() where !record.isFinished && record.state != "failed" {
            if !activeJobs.contains(record.id) { reconcile.insert(record.id); record.state = "waiting" }
        }
        try? context.save(); kick()
    }
    func kick() {
        guard let owner = api.tokens?.sub, api.tokens?.requiresConsent == false else { return }
        for record in records() where record.ownerSub == owner && record.environment == (api.baseURL?.absoluteString ?? "") && !record.isFinished && record.state != "failed" {
            if record.source == "automatic" {
                if let reason = automaticGate?(record) ?? (automaticGate == nil ? String(localized: "Automatic backup is off") : nil) {
                    record.state = "paused"; record.pauseReason = reason; continue
                }
                record.pauseReason = nil
                if let date = record.retryAfter, date > .now { continue }
            }
            guard activeJobs.count < 3 else { break }
            if activeJobs.insert(record.id).inserted { drivers[record.id] = Task { await drive(record) } }
        }
        try? context.save(); scheduleRetry()
    }
    private func drive(_ record: TransferRecord) async {
        do {
            guard api.tokens?.sub == record.ownerSub, !record.isFinished else { activeJobs.remove(record.id); drivers[record.id] = nil; return }
            try Task.checkCancellation()
            if record.source == "automatic", let reason = automaticGate?(record) {
                record.state = "paused"; record.pauseReason = reason; try context.save(); activeJobs.remove(record.id); drivers[record.id] = nil; return
            }
            record.pauseReason = nil
            var components = record.components
            guard record.componentIndex < components.count else { finish(record); return }
            let index = record.componentIndex
            var component = components[index]
            let fileURL = Self.filesRoot.appendingPathComponent(component.filePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                record.skipReason = "LOCAL_ORIGINAL_MISSING"
                throw APIError(status: 410, message: String(localized: "The local original is unavailable. Add this item again."), code: nil)
            }
            if component.contentHash == nil && component.mediaRole != "liveVideo" {
                let file = try FileHandle(forReadingFrom: fileURL); defer { try? file.close() }
                let prefix = try file.read(upToCount: Self.partSize) ?? Data()
                component.contentHash = SHA256.hash(data: prefix).map { String(format: "%02x", $0) }.joined() + "-\(component.size)"
            }
            if component.uploadId == nil {
                if component.requestId == nil { component.requestId = UUID().uuidString.lowercased(); components[index] = component; record.components = components; try context.save() }
                var body: [String: Any] = ["fileName": component.fileName, "contentType": component.contentType, "size": component.size, "mediaType": component.mediaType, "mediaRole": component.mediaRole]
                body["requestId"] = component.requestId
                body["contentHash"] = component.contentHash; body["photoId"] = component.photoId
                if record.source == "automatic" { body["uploadSource"] = "automatic" }
                if record.startedAt == nil { record.startedAt = .now; try context.save() }
                let start: UploadStart = try await api.request("/api/videos/multipart/init", method: "POST", body: body)
                if start.skipped == true {
                    skip(record, reason: start.skipReason); return
                }
                if start.duplicate {
                    component.skipped = true; component.notified = true
                    if let photoId = start.photoId { for i in components.indices { components[i].photoId = photoId } }
                    components[index] = component; record.components = components; record.componentIndex += 1
                    try context.save(); activeJobs.remove(record.id); drivers[record.id] = nil; kick(); return
                }
                guard let uploadId = start.uploadId, let key = start.key, let bucket = start.bucket else { throw URLError(.cannotParseResponse) }
                component.uploadId = uploadId; component.key = key; component.bucket = bucket
                if let photoId = start.photoId { component.photoId = photoId; for i in components.indices { components[i].photoId = photoId } }
                components[index] = component; record.components = components; try context.save()
                if start.resumed == true { reconcile.insert(record.id); activeJobs.remove(record.id); drivers[record.id] = nil; kick(); return }
            } else if reconcile.remove(record.id) != nil {
                do {
                    let status: UploadStatus = try await api.request("/api/videos/multipart/status", method: "POST", body: ["key": component.key!, "uploadId": component.uploadId!])
                    component.parts = status.parts; component.remoteCompleted = status.completed
                    components[index] = component; record.components = components; try context.save()
                } catch let error as APIError where error.status == 410 {
                    component.uploadId = nil; component.parts = []; component.key = nil; component.bucket = nil; component.remoteCompleted = false
                    components[index] = component; record.components = components
                    record.state = "waiting"; try context.save(); activeJobs.remove(record.id); drivers[record.id] = nil; kick(); return
                }
            }
            guard api.tokens?.sub == record.ownerSub, !record.isFinished else { activeJobs.remove(record.id); drivers[record.id] = nil; return }
            let count = Int((component.size + Int64(Self.partSize) - 1) / Int64(Self.partSize))
            if !component.remoteCompleted, let part = (1...count).first(where: { number in !component.parts.contains(where: { $0.partNumber == number }) }) {
                let result: PartURL = try await api.request("/api/videos/multipart/part", method: "POST", body: ["key": component.key!, "uploadId": component.uploadId!, "partNumber": part])
                let handle = try FileHandle(forReadingFrom: fileURL); defer { try? handle.close() }
                try handle.seek(toOffset: UInt64((part - 1) * Self.partSize))
                let data = try handle.read(upToCount: Self.partSize) ?? Data()
                guard !data.isEmpty else { throw URLError(.cannotOpenFile) }
                let attemptID = UUID().uuidString
                let chunk = fileURL.deletingLastPathComponent().appendingPathComponent("part-\(record.id)-\(index)-\(part)-\(attemptID)")
                try data.write(to: chunk, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                var request = URLRequest(url: result.uploadUrl); request.httpMethod = "PUT"
                if record.source == "automatic" {
                    request.allowsCellularAccess = automaticCellularAllowed
                    request.allowsConstrainedNetworkAccess = false
                }
                let task = background.uploadTask(with: request, fromFile: chunk)
                task.taskDescription = "\(record.id)|\(index)|\(part)|\(attemptID)"
                record.activeTaskTag = task.taskDescription
                record.state = "uploading"; record.message = nil; try context.save(); task.resume()
                drivers[record.id] = nil
                return
            }
            record.state = "finalizing"; try context.save()
            if !component.remoteCompleted {
                let _: OKResponse = try await api.request("/api/videos/multipart/complete", method: "POST", body: ["key": component.key!, "uploadId": component.uploadId!, "parts": component.parts.map { ["partNumber": $0.partNumber, "etag": $0.etag] as [String: Any] }])
                component.remoteCompleted = true; components[index] = component; record.components = components; try context.save()
            }
            if !component.notified {
                var body: [String: Any] = ["bucket": component.bucket!, "key": component.key!, "originalName": component.fileName, "contentType": component.contentType, "size": component.size, "mediaType": component.mediaType, "mediaRole": component.mediaRole, "fileLastModified": ISO8601DateFormatter().string(from: record.capturedAt ?? record.createdAt)]
                body["contentHash"] = component.contentHash; body["photoId"] = component.photoId
                let result: UploadFinish = try await api.request("/api/videos/notify", method: "POST", body: body)
                if result.duplicate == true {
                    component.skipped = true
                    if component.mediaType == "PHOTO", let id = result.photoId { component.photoId = id; for i in components.indices { components[i].photoId = id } }
                }
                component.notified = true; components[index] = component; record.components = components; record.componentIndex += 1
                record.completedBytes = components.filter { $0.notified }.reduce(0) { $0 + $1.size }; try context.save()
            }
            activeJobs.remove(record.id); drivers[record.id] = nil; attempts[record.id] = nil
            if record.componentIndex >= components.count { finish(record) } else { record.state = "waiting"; try context.save(); kick() }
        } catch {
            activeJobs.remove(record.id)
            drivers[record.id] = nil
            if !record.isFinished && record.pauseReason == nil {
                if record.source == "automatic", let failure = error as? APIError, failure.code == "CLOUD_DELETED" { skip(record, reason: failure.code); return }
                record.message = (error as? APIError)?.localizedDescription ?? String(localized: "Connection interrupted. Check your connection, then retry.")
                let status = (error as? APIError)?.status
                if record.source == "automatic" && (status == nil || status == 429 || (error as? APIError)?.code == "UPLOAD_IN_PROGRESS" || (status ?? 0) >= 500) { deferRetry(record) }
                else { record.state = "failed" }
                try? context.save()
            }
            kick()
            onRecordChange?()
        }
    }
    private func finish(_ record: TransferRecord) {
        record.state = "completed"; record.completedBytes = record.totalBytes
        drivers[record.id] = nil
        activeJobs.remove(record.id); try? context.save()
        if let first = record.components.first { try? FileManager.default.removeItem(at: Self.filesRoot.appendingPathComponent(first.filePath).deletingLastPathComponent()) }
        api.libraryRevision += 1; kick()
        onRecordChange?()
    }
    func retry(_ record: TransferRecord) {
        guard record.ownerSub == api.tokens?.sub else { return }
        record.state = "waiting"; record.message = nil; record.retryAfter = nil; record.retryCount = 0; reconcile.insert(record.id); attempts[record.id] = nil; try? context.save(); kick()
    }
    func cancel(_ record: TransferRecord) async {
        record.state = "cancelled"; try? context.save()
        // Stop API finalization before removing its model or original files.
        if let driver = drivers.removeValue(forKey: record.id) { driver.cancel(); await driver.value }
        let tasks = await background.allTasks
        for task in tasks where task.taskDescription?.hasPrefix(record.id.uuidString + "|") == true { task.cancel() }
        for component in record.components {
            if let key = component.key, let uploadId = component.uploadId, !component.notified {
                let _: OKResponse? = try? await api.request("/api/videos/multipart/abort", method: "POST", body: ["key": key, "uploadId": uploadId])
            }
        }
        if let first = record.components.first { try? FileManager.default.removeItem(at: Self.filesRoot.appendingPathComponent(first.filePath).deletingLastPathComponent()) }
        activeJobs.remove(record.id); kick(); onRecordChange?()
    }
    func clearForAccountDeletion(owner: String) async {
        // The server has accepted erasure and cleared the session by this point.
        for record in records() where record.ownerSub == owner { if !record.isFinished { await cancel(record) }; context.delete(record) }
        try? context.save()
        onAccountDeletion?(owner)
    }
    func cancelUnfinishedForSignOut() async {
        guard let owner = api.tokens?.sub else { return }
        for record in records() where record.ownerSub == owner && !record.isFinished { await cancel(record) }
        // Keep completed/cancelled history associated with its original account.
        try? context.save()
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let tag = task.taskDescription
        let status = (task.response as? HTTPURLResponse)?.statusCode
        let etag = (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
        let failed = error != nil
        Task { @MainActor [weak self] in self?.completed(tag: tag, status: status, etag: etag, failed: failed) }
    }
    private func completed(tag: String?, status: Int?, etag: String?, failed: Bool) {
        guard let values = tag?.split(separator: "|"), values.count >= 3, let id = UUID(uuidString: String(values[0])), let index = Int(values[1]), let part = Int(values[2]), let record = records().first(where: { $0.id == id }) else { return }
        var components = record.components
        guard components.indices.contains(index) else { return }
        let suffix = values.count == 4 ? "-" + String(values[3]) : ""
        let chunk = Self.filesRoot.appendingPathComponent(components[index].filePath).deletingLastPathComponent().appendingPathComponent("part-\(id)-\(index)-\(part)" + suffix)
        try? FileManager.default.removeItem(at: chunk)
        guard !record.isFinished, record.pauseReason == nil, record.componentIndex == index,
              record.activeTaskTag == tag || (values.count == 3 && record.activeTaskTag == nil) else { return }
        record.activeTaskTag = nil; activeJobs.remove(id)
        if !failed, let status, (200..<300).contains(status), let etag {
            if !components[index].parts.contains(where: { $0.partNumber == part }) { components[index].parts.append(UploadedPart(partNumber: part, etag: etag)) }
            record.components = components
            record.completedBytes = components.prefix(index).reduce(0) { $0 + $1.size } + components[index].parts.reduce(0) { $0 + min(Int64(Self.partSize), components[index].size - Int64(($1.partNumber - 1) * Self.partSize)) }
            attempts[id] = nil; record.retryAfter = nil; record.retryCount = 0; record.state = "waiting"; try? context.save(); kick()
        } else {
            let count = (attempts[id] ?? 0) + 1; attempts[id] = count
            record.state = "failed"; record.message = String(localized: "Connection interrupted. Check your connection, then retry.")
            reconcile.insert(id); try? context.save()
            if record.source == "automatic" { deferRetry(record); try? context.save(); kick() }
            else if status == 403 && count <= 2 { record.state = "waiting"; kick() }
            else { kick() }
            onRecordChange?()
        }
    }
    var automaticCellularAllowed = false
    func enforceAutomaticPolicy(reconfigure: Bool = false) async {
        for record in records() where record.source == "automatic" && !record.isFinished {
            let reason = automaticGate?(record)
            guard reason != nil || reconfigure else { continue }
            let previousState = record.state
            record.pauseReason = reason ?? String(localized: "Updating backup settings"); record.state = "paused"; record.activeTaskTag = nil; try? context.save()
            if let driver = drivers.removeValue(forKey: record.id) { driver.cancel(); await driver.value }
            for task in await background.allTasks where task.taskDescription?.hasPrefix(record.id.uuidString + "|") == true { task.cancel() }
            activeJobs.remove(record.id); reconcile.insert(record.id)
            if reason == nil { record.pauseReason = nil; record.state = previousState == "failed" ? "failed" : "waiting"; try? context.save() }
        }
        kick()
    }
    private func deferRetry(_ record: TransferRecord) {
        record.retryCount += 1
        record.retryAfter = Date(timeIntervalSinceNow: min(3600, 30 * pow(2, Double(min(record.retryCount, 7)))))
        record.state = "retryWaiting"; reconcile.insert(record.id)
    }
    private func scheduleRetry() {
        retryTimer?.cancel(); retryTimer = nil
        guard let next = records().filter({ $0.source == "automatic" && $0.ownerSub == api.tokens?.sub && !$0.isFinished && $0.pauseReason == nil }).compactMap(\.retryAfter).filter({ $0 > .now }).min() else { return }
        retryTimer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))); try Task.checkCancellation(); self?.kick() } catch { }
        }
    }
    private func skip(_ record: TransferRecord, reason: String?) {
        record.state = "skipped"; record.skipReason = reason
        record.message = String(localized: "Deleted cloud copy will not be backed up again. Choose it manually to upload again.")
        activeJobs.remove(record.id); drivers[record.id] = nil; try? context.save()
        if let first = record.components.first { try? FileManager.default.removeItem(at: Self.filesRoot.appendingPathComponent(first.filePath).deletingLastPathComponent()) }
        kick(); onRecordChange?()
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let tag = task.taskDescription
        Task { @MainActor [weak self] in
            guard let self, let values = tag?.split(separator: "|"), values.count >= 3, let id = UUID(uuidString: String(values[0])), let index = Int(values[1]), let record = records().first(where: { $0.id == id }), ["uploading", "waitingForNetwork"].contains(record.state), record.componentIndex == index, record.activeTaskTag == tag || (values.count == 3 && record.activeTaskTag == nil) else { return }
            record.state = "uploading"
            let components = record.components
            guard components.indices.contains(index) else { return }
            let confirmed = components[index].parts.reduce(Int64(0)) { $0 + min(Int64(Self.partSize), components[index].size - Int64(($1.partNumber - 1) * Self.partSize)) }
            record.completedBytes = min(record.totalBytes, components.prefix(index).reduce(0) { $0 + $1.size } + confirmed + totalBytesSent)
        }
    }
    nonisolated func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        let tag = task.taskDescription
        Task { @MainActor [weak self] in
            guard let self, let idText = tag?.split(separator: "|").first, let id = UUID(uuidString: String(idText)), let record = records().first(where: { $0.id == id }), !record.isFinished else { return }
            record.state = "waitingForNetwork"; try? context.save()
        }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }; try? context.save()
            let completion = backgroundCompletion; backgroundCompletion = nil; completion?()
        }
    }
}
