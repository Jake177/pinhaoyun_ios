import SwiftUI

struct LibraryView: View {
    let showTransfers: () -> Void
    @Environment(APIClient.self) private var api
    @Environment(TransferManager.self) private var transfers
    @Environment(PhotoImportSession.self) private var photoImport
    @State private var items: [MediaItem] = []
    @State private var cursor: String?
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadGeneration = UUID()
    @State private var error: String?
    @State private var importing = false
    @State private var filter = ""
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 3)]
    private var groups: [(date: Date, items: [MediaItem])] {
        Dictionary(grouping: items, by: { $0.date == .distantPast ? .distantPast : Calendar.current.startOfDay(for: $0.date) })
            .map { (date: $0.key, items: $0.value) }.sorted { $0.date > $1.date }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                PhotoImportStatusView(showTransfers: showTransfers).padding(.horizontal).padding(.vertical, photoImport.total > 0 ? 8 : 0)
                if let error {
                    VStack(spacing: 12) { Label(error, systemImage: "wifi.exclamationmark"); Button("Try again") { Task { await load(reset: true) } } }.padding()
                }
                if items.isEmpty && !loading && error == nil {
                    ContentUnavailableView {
                        Label(filter.isEmpty ? String(localized: "Your library starts here") : filter == "VIDEO" ? String(localized: "No videos match this filter") : String(localized: "No photos match this filter"), systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text(filter.isEmpty ? String(localized: "Add photos, videos and Live Photos. Your originals stay on your device.") : String(localized: "Change the filter to see other media in your library."))
                    } actions: {
                        if filter.isEmpty { Button("Add photos and videos") { importing = true }.buttonStyle(.borderedProminent).disabled(photoImport.isPreparing) }
                        else { Button("Show all media") { filter = "" }.buttonStyle(.bordered) }
                    }.padding(.top, 24)
                }
                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.date) { group in
                        Section {
                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(group.items) { item in
                                    NavigationLink(value: item) { MediaCell(item: item) }.buttonStyle(.plain).accessibilityLabel(item.accessibleDescription).accessibilityHint("Open media")
                                        .onAppear { if item.id == items.last?.id && hasMore && !loading { Task { await load(reset: false) } } }
                                }
                            }
                        } header: {
                            Text(group.date == .distantPast ? String(localized: "Date unknown") : group.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.headline).padding(.vertical, 8).padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).background(.background)
                        }
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                    if hasMore && !loading { Button("Load more") { Task { await load(reset: false) } }.frame(maxWidth: .infinity).padding() }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Media type", selection: $filter) { Text("All media").tag(""); Text("Photos").tag("PHOTO"); Text("Videos").tag("VIDEO") }
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "line.3.horizontal.decrease.circle"); Text(filterTitle) }.frame(minHeight: 44)
                    }.accessibilityLabel("Filter library").accessibilityValue(filterTitle)
                }
                ToolbarItem(placement: .primaryAction) { Button { importing = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }.disabled(photoImport.isPreparing).accessibilityLabel("Add photos and videos").accessibilityIdentifier("library.add") }
            }
            .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
            .sheet(isPresented: $importing) {
                let owner = api.tokens?.sub ?? ""
                PhotoImporter(session: photoImport, owner: owner, receive: { components, name in try transfers.enqueue(displayName: name, components: components, owner: owner) })
                    .ignoresSafeArea()
            }
            .refreshable { await load(reset: true) }
            .task(id: "\(api.libraryRevision)-\(filter)") { await load(reset: true) }
        }
    }
    private var filterTitle: String { filter == "PHOTO" ? String(localized: "Photos") : filter == "VIDEO" ? String(localized: "Videos") : String(localized: "All media") }
    private func load(reset: Bool) async {
        guard reset || !loading else { return }
        let generation = UUID()
        loadGeneration = generation
        loading = true; error = nil
        defer { if generation == loadGeneration { loading = false } }
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "limit", value: "60")]
        if !filter.isEmpty { query.queryItems?.append(URLQueryItem(name: "type", value: filter)) }
        if !reset, let cursor { query.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        do {
            let page: LibraryPage = try await api.request("/api/videos/list?" + (query.percentEncodedQuery ?? ""))
            guard generation == loadGeneration, !Task.isCancelled else { return }
            if reset { items = page.videos } else {
                let existing = Set(items.map { $0.type + ":" + $0.id })
                items += page.videos.filter { !existing.contains($0.type + ":" + $0.id) }
            }
            cursor = page.nextCursor; hasMore = page.hasMore
        } catch {
            if generation == loadGeneration, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
private struct MediaCell: View {
    let item: MediaItem
    var body: some View {
        Color(uiColor: .secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: item.thumbnailUrl ?? item.thumbnailUrlAlt) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: item.isPhoto ? "photo" : "video").font(.title2).foregroundStyle(.secondary) }
                }
            }.clipped()
            .overlay(alignment: .bottomLeading) {
                if !item.isPhoto || item.isLivePhoto {
                    Label(item.isLivePhoto ? "LIVE" : duration, systemImage: item.isLivePhoto ? "livephoto" : "play.fill")
                        .font(.caption2.bold()).foregroundStyle(.white).padding(5).background(.black.opacity(0.65), in: Capsule()).padding(5)
                }
            }
            .accessibilityHidden(true)
    }
    private var duration: String { let seconds = Int(item.durationSec ?? 0); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
}

extension MediaItem {
    var accessibleDescription: String {
        let kind = isLivePhoto ? String(localized: "Live Photo") : isPhoto ? String(localized: "Photo") : String(localized: "Video")
        let dateText = date == .distantPast ? String(localized: "Date unknown") : date.formatted(date: .abbreviated, time: .shortened)
        var description = "\(kind), \(title), \(dateText)"
        if !isPhoto, let durationSec { description += ", " + Duration.seconds(durationSec).formatted(.time(pattern: .minuteSecond)) }
        return description
    }
}
