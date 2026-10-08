import SwiftUI
@preconcurrency import Photos
@preconcurrency import PhotosUI
import UniformTypeIdentifiers

struct PhotoImporter: UIViewControllerRepresentable {
    let receive: @MainActor ([UploadComponent], String) throws -> Void
    let failed: @MainActor (String) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos]); configuration.selectionLimit = 0
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(receive: receive, failed: failed) }
    @MainActor final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let receive: @MainActor ([UploadComponent], String) throws -> Void
        let failed: @MainActor (String) -> Void
        init(receive: @escaping @MainActor ([UploadComponent], String) throws -> Void, failed: @escaping @MainActor (String) -> Void) { self.receive = receive; self.failed = failed }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            Task {
                for result in results {
                    do {
                        let components = try await export(result)
                        try receive(components, components.first?.fileName ?? String(localized: "Photo"))
                    } catch { failed(error.localizedDescription) }
                }
            }
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
