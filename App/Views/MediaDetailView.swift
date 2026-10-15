import SwiftUI
import AVKit
@preconcurrency import Photos
@preconcurrency import PhotosUI
import ImageIO

struct MediaDetailView: View {
    private enum Operation { case preview, save, share, delete, permission }
    private struct Failure { let message: String; let operation: Operation }
    let item: MediaItem
    @Environment(APIClient.self) private var api
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var player: AVPlayer?
    @State private var playerObservation: NSKeyValueObservation?
    @State private var videoLoading = false
    @State private var previewID = UUID()
    @State private var image: UIImage?
    @State private var livePhoto: PHLivePhoto?
    @State private var livePlayback = 0
    @State private var files: [URL] = []
    @State private var busy: Operation? = .preview
    @State private var failure: Failure?
    @State private var notice: String?
    @State private var confirmingDeletion = false
    @State private var share: ExportedFiles?
    @State private var details = false
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if let livePhoto {
                LivePhotoPlayer(livePhoto: livePhoto, playback: livePlayback)
                    .accessibilityLabel(item.accessibleDescription)
                    .accessibilityAction(named: Text("Play Live Photo")) { livePlayback += 1 }
            } else if let player { VideoPlayer(player: player) }
            else if let image { ZoomablePhoto(image: image, title: item.title) }
            else if busy != .preview { ContentUnavailableView("Unable to load media", systemImage: "photo", description: Text("Try loading this original again.")) }
            if busy == .preview || videoLoading { ProgressView("Loading original").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
        }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { status }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { Task { await saveToPhotos() } } label: { if busy == .save { ProgressView() } else { Image(systemName: "square.and.arrow.down") } }
                    .disabled(busy != nil || videoLoading).accessibilityLabel("Save original to Photos")
                Spacer()
                Button { Task { await exportFiles() } } label: { if busy == .share { ProgressView() } else { Image(systemName: "square.and.arrow.up") } }
                    .disabled(busy != nil || videoLoading).accessibilityLabel("Save to Files or share")
                Spacer()
                Button { details = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("Media details")
                Spacer()
                Button(role: .destructive) { confirmingDeletion = true } label: { if busy == .delete { ProgressView() } else { Image(systemName: "trash") } }
                    .disabled(busy != nil).accessibilityLabel("Delete cloud copy")
            }
        }
        .confirmationDialog("Delete this cloud copy?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete cloud copy", role: .destructive) { Task { await delete() } }
        } message: { Text("This removes the cloud original and thumbnail. Photos on your device are kept.") }
        .sheet(item: $share) { ShareFiles(urls: $0.urls) }
        .sheet(isPresented: $details) { MediaInfoView(item: item) }
        .task { await load() }
        .onDisappear {
            previewID = UUID(); playerObservation?.invalidate(); player?.pause()
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }
    @ViewBuilder private var status: some View {
        if livePhoto != nil || failure != nil || notice != nil || (busy != nil && busy != .preview) {
            VStack(alignment: .leading, spacing: 8) {
                if livePhoto != nil {
                    HStack { Label("Touch and hold to play", systemImage: "livephoto").font(.footnote); Spacer(); Button("Play Live Photo") { livePlayback += 1 } }
                }
                if let busy, busy != .preview { ProgressView(operationTitle(busy)).font(.footnote) }
                if let notice {
                    HStack(alignment: .top) { Label(notice, systemImage: "checkmark.circle").font(.footnote); Spacer(); Button("Dismiss") { self.notice = nil }.font(.footnote) }
                }
                if let failure {
                    Text(failure.message).font(.footnote)
                    HStack {
                        Button(retryTitle(failure.operation)) { retry(failure.operation) }.disabled(busy != nil)
                        if failure.operation == .permission { Button("Save to Files or share") { Task { await exportFiles() } }.disabled(busy != nil) }
                    }
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
        }
    }
    private func operationTitle(_ operation: Operation) -> String {
        switch operation { case .save: String(localized: "Saving original to Photos"); case .share: String(localized: "Preparing files to share"); case .delete: String(localized: "Deleting cloud copy"); default: String(localized: "Loading original") }
    }
    private func retryTitle(_ operation: Operation) -> String {
        switch operation { case .save: String(localized: "Retry saving to Photos"); case .share: String(localized: "Retry preparing files"); case .delete: String(localized: "Retry cloud deletion"); case .permission: String(localized: "Open Settings"); case .preview: String(localized: "Try loading again") }
    }
    private func retry(_ operation: Operation) {
        switch operation {
        case .preview: Task { await load() }
        case .save: Task { await saveToPhotos() }
        case .share: Task { await exportFiles() }
        case .delete: confirmingDeletion = true
        case .permission: if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }
    private func urls() async throws -> MediaURLs { try await api.request("/api/media/urls", method: "POST", body: ["id": item.id, "type": item.type]) }
    private var originalExtension: String { let ext = URL(fileURLWithPath: item.originalName ?? "").pathExtension; return ext.isEmpty ? (item.isPhoto ? "heic" : "mp4") : ext }
    private func originals() async throws -> [URL] {
        if !files.isEmpty && files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { return files }
        let links = try await urls()
        guard let original = links.originalPhotoUrl ?? links.originalUrl else { throw URLError(.resourceUnavailable) }
        let first = try await api.download(original, extension: originalExtension)
        var result = [first]
        do { if let motion = links.liveVideoUrl, item.isPhoto { result.append(try await api.download(motion, extension: "mov")) } }
        catch { try? FileManager.default.removeItem(at: first); throw error }
        files = result
        return result
    }
    private func load() async {
        guard busy == nil || busy == .preview else { return }
        busy = .preview; failure = nil
        let requestID = UUID(); previewID = requestID
        defer { busy = nil }
        do {
            if !item.isPhoto {
                let links = try await urls()
                try Task.checkCancellation()
                guard let url = links.originalUrl else { throw URLError(.resourceUnavailable) }
                playerObservation?.invalidate()
                let playerItem = AVPlayerItem(url: url)
                player = AVPlayer(playerItem: playerItem); videoLoading = true
                playerObservation = playerItem.observe(\.status, options: [.initial, .new]) { observed, _ in
                    let state = observed.status.rawValue
                    let message = observed.error?.localizedDescription
                    Task { @MainActor in
                        guard requestID == previewID else { return }
                        videoLoading = state == AVPlayerItem.Status.unknown.rawValue
                        if state == AVPlayerItem.Status.failed.rawValue {
                            failure = Failure(message: message ?? String(localized: "Video playback failed. Try loading it again."), operation: .preview)
                        }
                    }
                }
                return
            }
            let local = try await originals()
            try Task.checkCancellation()
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
        } catch { if !Task.isCancelled { failure = Failure(message: error.localizedDescription, operation: .preview) } }
    }
    private func saveToPhotos() async {
        guard busy == nil else { return }
        busy = .save; failure = nil; notice = nil
        defer { busy = nil }
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else { failure = Failure(message: String(localized: "Allow Photos access in Settings, or use Save to Files."), operation: .permission); return }
        do {
            let local = try await originals()
            let isPhoto = item.isPhoto
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: isPhoto ? .photo : .video, fileURL: local[0], options: nil)
                if local.count > 1 { request.addResource(with: .pairedVideo, fileURL: local[1], options: nil) }
            }
            notice = String(localized: "Original saved to Photos.")
        } catch { failure = Failure(message: error.localizedDescription, operation: .save) }
    }
    private func exportFiles() async {
        guard busy == nil else { return }
        busy = .share; failure = nil; notice = nil
        defer { busy = nil }
        do { share = ExportedFiles(urls: try await originals()) } catch { failure = Failure(message: error.localizedDescription, operation: .share) }
    }
    private func delete() async {
        guard busy == nil else { return }
        busy = .delete; failure = nil; notice = nil
        defer { busy = nil }
        do { let _: OKResponse = try await api.request("/api/videos/delete", method: "POST", body: ["mediaId": item.id, "mediaType": item.type]); api.libraryRevision += 1; dismiss() }
        catch { failure = Failure(message: error.localizedDescription, operation: .delete) }
    }
}
private struct LivePhotoPlayer: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let playback: Int
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PHLivePhotoView { let view = PHLivePhotoView(); view.contentMode = .scaleAspectFit; view.isMuted = true; return view }
    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto !== livePhoto { view.livePhoto = livePhoto }
        if context.coordinator.playback != playback { context.coordinator.playback = playback; if playback > 0 { view.startPlayback(with: .full) } }
    }
    final class Coordinator { var playback = 0 }
}
private struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    let title: String
    func makeUIView(context: Context) -> PhotoZoomView { PhotoZoomView() }
    func updateUIView(_ view: PhotoZoomView, context: Context) { view.setImage(image); view.accessibilityLabel = title }
}
final class PhotoZoomView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var lastSize = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self; minimumZoomScale = 1; maximumZoomScale = 4
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit; addSubview(imageView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:))); tap.numberOfTapsRequired = 2; addGestureRecognizer(tap)
        isAccessibilityElement = true; accessibilityTraits = [.image, .adjustable]
        accessibilityHint = String(localized: "Swipe up or down to zoom.")
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: String(localized: "Reset zoom"), target: self, selector: #selector(resetZoom))]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setImage(_ image: UIImage) { if imageView.image !== image { imageView.image = image; lastSize = .zero; setNeedsLayout() } }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize, bounds.width > 0, bounds.height > 0, let image = imageView.image else { return }
        lastSize = bounds.size; setZoomScale(1, animated: false)
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: size); contentSize = size
        centerImage()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    private func centerImage() {
        imageView.center = CGPoint(x: max(contentSize.width, bounds.width) / 2, y: max(contentSize.height, bounds.height) / 2)
        accessibilityValue = String(format: String(localized: "%lld percent zoom"), Int64((zoomScale * 100).rounded()))
    }
    @objc private func doubleTap(_ tap: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale { _ = resetZoom(); return }
        let point = tap.location(in: imageView), scale: CGFloat = 2.5
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: !UIAccessibility.isReduceMotionEnabled)
    }
    @objc private func resetZoom() -> Bool { setZoomScale(minimumZoomScale, animated: !UIAccessibility.isReduceMotionEnabled); return true }
    override func accessibilityIncrement() { setZoomScale(min(maximumZoomScale, zoomScale + 0.5), animated: false) }
    override func accessibilityDecrement() { setZoomScale(max(minimumZoomScale, zoomScale - 0.5), animated: false) }
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
                LabeledContent("File name") { Text(item.title).multilineTextAlignment(.trailing).textSelection(.enabled) }
                    .contextMenu { Button("Copy file name") { UIPasteboard.general.string = item.title } }
                LabeledContent("Date", value: item.date == .distantPast ? String(localized: "Date unknown") : item.date.formatted(date: .abbreviated, time: .shortened))
                if let size = item.size { LabeledContent("Size", value: size.formatted(.byteCount(style: .file))) }
                if let width = item.width, let height = item.height { LabeledContent("Resolution", value: "\(width) × \(height)") }
                if let device = item.deviceModel { LabeledContent("Device", value: device) }
                if let city = item.captureCity { LabeledContent("Location", value: city) }
            }.navigationTitle("Media details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
