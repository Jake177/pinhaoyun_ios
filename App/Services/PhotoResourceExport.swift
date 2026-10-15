import Foundation
@preconcurrency import Photos

// PhotoKit has no cellular flag. Network changes cancel its resource request;
// the upload request independently enforces URLSession's cellular restriction.
final class PhotoResourceExport: @unchecked Sendable {
    private let resource: PHAssetResource
    private let url: URL
    private let lock = NSLock()
    private var requestID: PHAssetResourceDataRequestID?
    private var continuation: CheckedContinuation<Void, Error>?
    private var handle: FileHandle?
    private var done = false
    private var failure: Error?
    private var count: Int64 = 0
    init(resource: PHAssetResource, url: URL) { self.resource = resource; self.url = url }
    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if done { let error = failure ?? CancellationError(); lock.unlock(); continuation.resume(throwing: error); return }
                self.continuation = continuation
                lock.unlock()
                do {
                    guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw CocoaError(.fileWriteUnknown) }
                    let file = try FileHandle(forWritingTo: url)
                    lock.lock(); if done { lock.unlock(); try? file.close(); return }; handle = file; lock.unlock()
                    let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = true
                    let id = PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { [self] data in
                        lock.lock()
                        guard !done else { lock.unlock(); return }
                        do {
                            guard count + Int64(data.count) <= 2 * 1024 * 1024 * 1024 else { throw APIError(status: 400, message: String(localized: "Each original must be smaller than 2 GB."), code: nil) }
                            let free = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                            guard free > Int64(data.count) + 200 * 1024 * 1024 else { throw APIError(status: 507, message: String(localized: "Not enough device storage. Free some space, then retry backup."), code: nil) }
                            try handle?.write(contentsOf: data); count += Int64(data.count); lock.unlock()
                        } catch { lock.unlock(); finish(error) }
                    }, completionHandler: { [self] error in finish(error) })
                    lock.lock(); requestID = id; let cancelled = done; lock.unlock()
                    if cancelled { PHAssetResourceManager.default().cancelDataRequest(id) }
                } catch { finish(error) }
            }
        } onCancel: { self.finish(CancellationError()) }
    }
    private func finish(_ error: Error?) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true; failure = error
        let waiter = continuation; continuation = nil
        let file = handle; handle = nil; let id = requestID
        lock.unlock()
        try? file?.close()
        if let error { if let id { PHAssetResourceManager.default().cancelDataRequest(id) }; waiter?.resume(throwing: error) }
        else { waiter?.resume() }
    }
}
