import SwiftUI
import AVKit
@preconcurrency import Photos
@preconcurrency import PhotosUI
import ImageIO

struct MediaDetailView: View {
    let item: MediaItem
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var image: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var files: [URL] = []
    @State private var loading = false
    @State private var error: String?
    @State private var notice: String?
    @State private var deleting = false
    @State private var saving = false
    @State private var share: ExportedFiles?
    @State private var details = false
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if let livePhoto { LivePhotoPlayer(livePhoto: livePhoto).accessibilityLabel("Live Photo. Touch and hold to play.") }
            else if let player { VideoPlayer(player: player) }
            else if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(item.title) }
            else if loading { ProgressView("Loading original") }
            else { ContentUnavailableView("Unable to load media", systemImage: "photo", description: Text(error ?? String(localized: "Try refreshing this item."))) }
        }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            if let notice { Text(notice).font(.footnote).padding().frame(maxWidth: .infinity).background(.regularMaterial) }
            if let error { VStack { Text(error).font(.footnote); Button("Refresh access") { Task { await load() } } }.padding().frame(maxWidth: .infinity).background(.regularMaterial) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { Task { await saveToPhotos() } } label: { if saving { ProgressView() } else { Image(systemName: "square.and.arrow.down") } }.disabled(saving || loading).accessibilityLabel("Save original to Photos")
                Spacer()
                Button { Task { await exportFiles() } } label: { Image(systemName: "square.and.arrow.up") }.disabled(saving || loading).accessibilityLabel("Save to Files or share")
                Spacer()
                Button { details = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("Media details")
                Spacer()
                Button(role: .destructive) { deleting = true } label: { Image(systemName: "trash") }.accessibilityLabel("Delete cloud copy")
            }
        }
        .confirmationDialog("Delete this cloud copy?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete cloud copy", role: .destructive) { Task { await delete() } }
        } message: { Text("This removes the cloud original and thumbnail. Photos on your device are kept.") }
        .sheet(item: $share) { ShareFiles(urls: $0.urls) }
        .sheet(isPresented: $details) { MediaInfoView(item: item) }
        .task { await load() }
        .onDisappear { player?.pause(); for file in files { try? FileManager.default.removeItem(at: file) } }
    }
    private func urls() async throws -> MediaURLs { try await api.request("/api/media/urls", method: "POST", body: ["id": item.id, "type": item.type]) }
    private var originalExtension: String { let ext = URL(fileURLWithPath: item.originalName ?? "").pathExtension; return ext.isEmpty ? (item.isPhoto ? "heic" : "mp4") : ext }
    private func originals() async throws -> [URL] {
        let links = try await urls()
        guard let original = links.originalPhotoUrl ?? links.originalUrl else { throw URLError(.resourceUnavailable) }
        let first = try await api.download(original, extension: originalExtension)
        var result = [first]
        do { if let motion = links.liveVideoUrl, item.isPhoto { result.append(try await api.download(motion, extension: "mov")) } }
        catch { try? FileManager.default.removeItem(at: first); throw error }
        files += result
        return result
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            if !item.isPhoto {
                let links = try await urls()
                guard let url = links.originalUrl else { throw URLError(.resourceUnavailable) }
                player = AVPlayer(url: url); return
            }
            let local = try await originals()
            if local.count == 2 {
                livePhoto = try await withCheckedThrowingContinuation { continuation in
                    PHLivePhoto.request(withResourceFileURLs: local, placeholderImage: nil, targetSize: CGSize(width: 1200, height: 1200), contentMode: .aspectFit) { @Sendable photo, info in
                        if (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true { return }
                        if let photo { continuation.resume(returning: photo) }
                        else { continuation.resume(throwing: (info[PHLivePhotoInfoErrorKey] as? Error) ?? URLError(.cannotDecodeContentData)) }
                    }
                }
            } else if let first = local.first, let source = CGImageSourceCreateWithURL(first as CFURL, nil), let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) { image = UIImage(cgImage: thumbnail) }
            else { throw URLError(.cannotDecodeContentData) }
        } catch { self.error = error.localizedDescription }
    }
    private func saveToPhotos() async {
        saving = true; error = nil; notice = nil
        defer { saving = false }
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else { error = String(localized: "Allow Photos access in Settings, or use Save to Files."); return }
        do {
            let local = try await originals()
            let isPhoto = item.isPhoto
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: isPhoto ? .photo : .video, fileURL: local[0], options: nil)
                if local.count > 1 { request.addResource(with: .pairedVideo, fileURL: local[1], options: nil) }
            }
            notice = String(localized: "Original saved to Photos.")
        } catch { self.error = error.localizedDescription }
    }
    private func exportFiles() async {
        saving = true; error = nil
        defer { saving = false }
        do { share = ExportedFiles(urls: try await originals()) } catch { self.error = error.localizedDescription }
    }
    private func delete() async {
        do { let _: OKResponse = try await api.request("/api/videos/delete", method: "POST", body: ["mediaId": item.id, "mediaType": item.type]); api.libraryRevision += 1; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
private struct LivePhotoPlayer: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    func makeUIView(context: Context) -> PHLivePhotoView { let view = PHLivePhotoView(); view.contentMode = .scaleAspectFit; view.isMuted = true; return view }
    func updateUIView(_ view: PHLivePhotoView, context: Context) { view.livePhoto = livePhoto }
}
private struct ExportedFiles: Identifiable { let id = UUID(); let urls: [URL] }
private struct ShareFiles: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ view: UIActivityViewController, context: Context) {}
}
private struct MediaInfoView: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("File name", value: item.title)
                LabeledContent("Date", value: item.date.formatted(date: .abbreviated, time: .shortened))
                if let size = item.size { LabeledContent("Size", value: size.formatted(.byteCount(style: .file))) }
                if let width = item.width, let height = item.height { LabeledContent("Resolution", value: "\(width) × \(height)") }
                if let device = item.deviceModel { LabeledContent("Device", value: device) }
                if let city = item.captureCity { LabeledContent("Location", value: city) }
            }.navigationTitle("Media details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
