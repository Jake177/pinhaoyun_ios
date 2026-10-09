import SwiftUI
@preconcurrency import Photos
@preconcurrency import PhotosUI
import UniformTypeIdentifiers
import Observation

@MainActor @Observable final class PhotoImportSession {
    var owner: String?
    var total = 0
    var processed = 0
    var added = 0
    var failures = 0
    var firstError: String?
    var isPreparing = false
    var stopping = false
    func begin(owner: String, total: Int) {
        self.owner = owner; self.total = total; processed = 0; added = 0; failures = 0
        firstError = nil; stopping = false; isPreparing = true
    }
    func stop() { if isPreparing { stopping = true } }
    func dismiss() { if !isPreparing { total = 0; firstError = nil } }
}

struct PhotoImportStatusView: View {
    @Environment(PhotoImportSession.self) private var session
    @Environment(APIClient.self) private var api
    var showTransfers: (() -> Void)? = nil
    var body: some View {
        if session.isPreparing && session.owner != api.tokens?.sub {
            ProgressView("Stopping preparation")
        } else if session.total > 0 && session.owner == api.tokens?.sub {
            VStack(alignment: .leading, spacing: 8) {
                if session.isPreparing {
                    Text(session.stopping ? String(localized: "Stopping preparation") : String(localized: "Preparing uploads")).font(.headline)
                    ProgressView(value: Double(session.processed), total: Double(max(1, session.total)))
                        .accessibilityLabel("Originals prepared")
                    Text(String(format: String(localized: "%lld of %lld originals prepared"), Int64(session.processed), Int64(session.total))).font(.subheadline)
                    Text("Keep the app open while originals are prepared. Items already in Transfers can continue uploading.").font(.footnote).foregroundStyle(.secondary)
                    Button("Stop preparing") { session.stop() }.disabled(session.stopping)
                } else {
                    Label(String(format: String(localized: "%lld items added to Transfers"), Int64(session.added)), systemImage: session.failures > 0 ? "exclamationmark.circle" : "checkmark.circle")
                    if session.stopping { Text("Preparation stopped. Your Photos library is unchanged.").font(.footnote) }
                    if session.owner == api.tokens?.sub, let error = session.firstError {
                        Text(String(format: String(localized: "%lld items could not be prepared. Choose them again to retry."), Int64(session.failures))).font(.footnote)
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                HStack {
                    if let showTransfers { Button("View transfers", action: showTransfers) }
                    Spacer()
                    if !session.isPreparing { Button("Dismiss") { session.dismiss() } }
                }
            }.accessibilityElement(children: .contain)
        }
    }
}

struct PhotoImporter: UIViewControllerRepresentable {
    let session: PhotoImportSession
    let owner: String
    let receive: @MainActor ([UploadComponent], String) throws -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos]); configuration.selectionLimit = 0
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(session: session, owner: owner, receive: receive) }
    @MainActor final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let session: PhotoImportSession
        let owner: String
        let receive: @MainActor ([UploadComponent], String) throws -> Void
        init(session: PhotoImportSession, owner: String, receive: @escaping @MainActor ([UploadComponent], String) throws -> Void) {
            self.session = session; self.owner = owner; self.receive = receive
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty, !session.isPreparing else { return }
            session.begin(owner: owner, total: results.count)
            Task {
                defer { session.isPreparing = false }
                for result in results {
                    if session.stopping { break }
                    var components: [UploadComponent] = []
                    do {
                        components = try await export(result)
                        if session.stopping { removePrepared(components); break }
                        try receive(components, components.first?.fileName ?? String(localized: "Photo"))
                        session.added += 1
                    } catch {
                        removePrepared(components)
                        session.failures += 1
                        if session.firstError == nil { session.firstError = error.localizedDescription }
                    }
                    session.processed += 1
                }
            }
        }
        private func removePrepared(_ components: [UploadComponent]) {
            if let first = components.first { try? FileManager.default.removeItem(at: TransferManager.filesRoot.appendingPathComponent(first.filePath).deletingLastPathComponent()) }
        }
        private func export(_ result: PHPickerResult) async throws -> [UploadComponent] {
            let folderName = UUID().uuidString
            let folder = TransferManager.filesRoot.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var succeeded = false
            defer { if !succeeded { try? FileManager.default.removeItem(at: folder) } }
            let photoId = UUID().uuidString.lowercased()
            var output: [UploadComponent] = []
            if result.itemProvider.canLoadObject(ofClass: PHLivePhoto.self) {
                let live: PHLivePhoto = try await withCheckedThrowingContinuation { continuation in
                    _ = result.itemProvider.loadObject(ofClass: PHLivePhoto.self) { @Sendable object, error in
                        if let live = object as? PHLivePhoto { continuation.resume(returning: live) }
                        else { continuation.resume(throwing: error ?? URLError(.cannotDecodeContentData)) }
                    }
                }
                let resources = PHAssetResource.assetResources(for: live)
                guard let photo = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }), let motion = resources.first(where: { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo }) else { throw URLError(.cannotDecodeContentData) }
                for (resource, role) in [(photo, "image"), (motion, "liveVideo")] {
                    let name = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
                    let target = folder.appendingPathComponent(name)
                    let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = true
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: options) { @Sendable error in
                            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                        }
                    }
                    output.append(try component(url: target, path: folderName + "/" + name, mediaType: "PHOTO", role: role, photoId: photoId))
                }
            } else {
                let provider = result.itemProvider
                let movie = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                let identifier = provider.registeredTypeIdentifiers.first { id in
                    guard let type = UTType(id) else { return false }
                    return movie ? type.conforms(to: .movie) : type.conforms(to: .image)
                } ?? (movie ? UTType.movie.identifier : UTType.image.identifier)
                let fileName: String = try await withCheckedThrowingContinuation { continuation in
                    _ = provider.loadFileRepresentation(forTypeIdentifier: identifier) { @Sendable url, error in
                        guard let url else { continuation.resume(throwing: error ?? URLError(.fileDoesNotExist)); return }
                        do {
                            let name = url.lastPathComponent
                            try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
                            continuation.resume(returning: name)
                        } catch { continuation.resume(throwing: error) }
                    }
                }
                output = [try component(url: folder.appendingPathComponent(fileName), path: folderName + "/" + fileName, mediaType: movie ? "VIDEO" : "PHOTO", role: "image", photoId: movie ? nil : photoId)]
            }
            succeeded = true
            return output
        }
        private func component(url: URL, path: String, mediaType: String, role: String, photoId: String?) throws -> UploadComponent {
            let ext = url.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "heic", "heif", "mov", "mp4", "m4v", "hevc"].contains(ext) else { throw APIError(status: 400, message: String(localized: "This original format is not supported yet."), code: nil) }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, Int64(size) <= 2 * 1024 * 1024 * 1024 else { throw APIError(status: 400, message: String(localized: "Each original must be smaller than 2 GB."), code: nil) }
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            return UploadComponent(filePath: path, fileName: url.lastPathComponent, contentType: mime, size: Int64(size), mediaType: mediaType, mediaRole: role, photoId: photoId)
        }
    }
}
