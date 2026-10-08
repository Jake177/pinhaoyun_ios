import Foundation
import SwiftData
import CryptoKit
import Observation

@MainActor @Observable final class TransferManager: NSObject, URLSessionTaskDelegate, URLSessionDelegate {
    static let partSize = 10 * 1024 * 1024
    static var filesRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Transfers", isDirectory: true)
    }
    let api: APIClient
    let context: ModelContext
    var backgroundCompletion: (() -> Void)?
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
    }
    func records() -> [TransferRecord] {
        (try? context.fetch(FetchDescriptor<TransferRecord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }
    func enqueue(displayName: String, components: [UploadComponent], owner: String) throws {
        guard api.tokens?.sub == owner else { throw URLError(.userAuthenticationRequired) }
        guard !components.isEmpty, components.allSatisfy({ $0.size > 0 && $0.size <= 2 * 1024 * 1024 * 1024 }) else {
            throw APIError(status: 400, message: String(localized: "Each original must be smaller than 2 GB."), code: nil)
        }
        let record = try TransferRecord(ownerSub: owner, displayName: displayName, components: components)
        context.insert(record); try context.save(); kick()
    }
    func resume() async {
        let tasks = await background.allTasks
        let unfinishedIDs = Set(records().filter { !$0.isFinished }.map(\.id))
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
        for record in records() where record.ownerSub == owner && !record.isFinished && record.state != "failed" {
            guard activeJobs.count < 3 else { break }
            if activeJobs.insert(record.id).inserted { drivers[record.id] = Task { await drive(record) } }
        }
    }
    private func drive(_ record: TransferRecord) async {
        do {
            guard api.tokens?.sub == record.ownerSub, !record.isFinished else { activeJobs.remove(record.id); drivers[record.id] = nil; return }
            var components = record.components
            guard record.componentIndex < components.count else { finish(record); return }
            let index = record.componentIndex
            var component = components[index]
            let fileURL = Self.filesRoot.appendingPathComponent(component.filePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { throw APIError(status: 410, message: String(localized: "The local original is unavailable. Add this item again."), code: nil) }
            if component.contentHash == nil && component.mediaRole != "liveVideo" {
                let file = try FileHandle(forReadingFrom: fileURL); defer { try? file.close() }
                let prefix = try file.read(upToCount: Self.partSize) ?? Data()
                component.contentHash = SHA256.hash(data: prefix).map { String(format: "%02x", $0) }.joined() + "-\(component.size)"
            }
            if component.uploadId == nil {
                var body: [String: Any] = ["fileName": component.fileName, "contentType": component.contentType, "size": component.size, "mediaType": component.mediaType, "mediaRole": component.mediaRole]
                body["contentHash"] = component.contentHash; body["photoId"] = component.photoId
                let start: UploadStart = try await api.request("/api/videos/multipart/init", method: "POST", body: body)
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
                let chunk = fileURL.deletingLastPathComponent().appendingPathComponent("part-\(record.id)-\(index)-\(part)")
                try data.write(to: chunk, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                var request = URLRequest(url: result.uploadUrl); request.httpMethod = "PUT"
                let task = background.uploadTask(with: request, fromFile: chunk)
                task.taskDescription = "\(record.id)|\(index)|\(part)"
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
                var body: [String: Any] = ["bucket": component.bucket!, "key": component.key!, "originalName": component.fileName, "contentType": component.contentType, "size": component.size, "mediaType": component.mediaType, "mediaRole": component.mediaRole, "fileLastModified": ISO8601DateFormatter().string(from: record.createdAt)]
                body["contentHash"] = component.contentHash; body["photoId"] = component.photoId
                let _: OKResponse = try await api.request("/api/videos/notify", method: "POST", body: body)
                component.notified = true; components[index] = component; record.components = components; record.componentIndex += 1
                record.completedBytes = components.filter { $0.notified }.reduce(0) { $0 + $1.size }; try context.save()
            }
            activeJobs.remove(record.id); drivers[record.id] = nil; attempts[record.id] = nil
            if record.componentIndex >= components.count { finish(record) } else { record.state = "waiting"; try context.save(); kick() }
        } catch {
            activeJobs.remove(record.id)
            drivers[record.id] = nil
            if !record.isFinished { record.state = "failed"; record.message = (error as? APIError)?.localizedDescription ?? String(localized: "Connection interrupted. Check your connection, then retry."); try? context.save() }
            kick()
        }
    }
    private func finish(_ record: TransferRecord) {
        record.state = "completed"; record.completedBytes = record.totalBytes
        drivers[record.id] = nil
        activeJobs.remove(record.id); try? context.save()
        if let first = record.components.first { try? FileManager.default.removeItem(at: Self.filesRoot.appendingPathComponent(first.filePath).deletingLastPathComponent()) }
        api.libraryRevision += 1; kick()
    }
    func retry(_ record: TransferRecord) {
        guard record.ownerSub == api.tokens?.sub else { return }
        record.state = "waiting"; record.message = nil; reconcile.insert(record.id); attempts[record.id] = nil; try? context.save(); kick()
    }
    func cancel(_ record: TransferRecord) async {
        record.state = "cancelled"; try? context.save()
        // Stop API finalization before removing its model or original files.
        if let driver = drivers.removeValue(forKey: record.id) { driver.cancel(); await driver.value }
        let tasks = await background.allTasks
        for task in tasks where task.taskDescription?.hasPrefix(record.id.uuidString + "|") == true { task.cancel() }
        for component in record.components {
            if let key = component.key, let uploadId = component.uploadId, !component.remoteCompleted {
                let _: OKResponse? = try? await api.request("/api/videos/multipart/abort", method: "POST", body: ["key": key, "uploadId": uploadId])
            }
        }
        if let first = record.components.first { try? FileManager.default.removeItem(at: Self.filesRoot.appendingPathComponent(first.filePath).deletingLastPathComponent()) }
        activeJobs.remove(record.id); kick()
    }
    func clearForSignOut() async {
        guard let owner = api.tokens?.sub else { return }
        for record in records() where record.ownerSub == owner { if !record.isFinished { await cancel(record) }; context.delete(record) }
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
        guard let values = tag?.split(separator: "|"), values.count == 3, let id = UUID(uuidString: String(values[0])), let index = Int(values[1]), let part = Int(values[2]), let record = records().first(where: { $0.id == id }), !record.isFinished, record.componentIndex == index else { return }
        activeJobs.remove(id)
        var components = record.components
        guard components.indices.contains(index) else { return }
        let chunk = Self.filesRoot.appendingPathComponent(components[index].filePath).deletingLastPathComponent().appendingPathComponent("part-\(id)-\(index)-\(part)")
        try? FileManager.default.removeItem(at: chunk)
        if !failed, let status, (200..<300).contains(status), let etag {
            if !components[index].parts.contains(where: { $0.partNumber == part }) { components[index].parts.append(UploadedPart(partNumber: part, etag: etag)) }
            record.components = components
            record.completedBytes = components.prefix(index).reduce(0) { $0 + $1.size } + components[index].parts.reduce(0) { $0 + min(Int64(Self.partSize), components[index].size - Int64(($1.partNumber - 1) * Self.partSize)) }
            attempts[id] = nil; record.state = "waiting"; try? context.save(); kick()
        } else {
            let count = (attempts[id] ?? 0) + 1; attempts[id] = count
            record.state = "failed"; record.message = String(localized: "Connection interrupted. Check your connection, then retry.")
            reconcile.insert(id); try? context.save()
            if status == 403 && count <= 2 { record.state = "waiting"; kick() }
            else { kick() }
        }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let tag = task.taskDescription
        Task { @MainActor [weak self] in
            guard let self, let values = tag?.split(separator: "|"), values.count == 3, let id = UUID(uuidString: String(values[0])), let index = Int(values[1]), let record = records().first(where: { $0.id == id }), ["uploading", "waitingForNetwork"].contains(record.state), record.componentIndex == index else { return }
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
