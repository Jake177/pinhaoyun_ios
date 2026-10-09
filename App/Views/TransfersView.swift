import SwiftUI
import SwiftData

struct TransfersView: View {
    let showLibrary: () -> Void
    @Environment(APIClient.self) private var api
    @Environment(TransferManager.self) private var manager
    @Environment(PhotoImportSession.self) private var photoImport
    @Query(sort: \TransferRecord.createdAt, order: .reverse) private var records: [TransferRecord]
    private var visible: [TransferRecord] { records.filter { $0.ownerSub == api.tokens?.sub } }
    var body: some View {
        NavigationStack {
            List {
                if photoImport.total > 0 && photoImport.owner == api.tokens?.sub {
                    Section { PhotoImportStatusView() }
                }
                if visible.isEmpty && !photoImport.isPreparing {
                    ContentUnavailableView {
                        Label("No transfers yet", systemImage: "arrow.up.arrow.down")
                    } description: { Text("Add photos and videos from your library. Uploads and retries appear here.") }
                    actions: { Button("Go to library", action: showLibrary).buttonStyle(.bordered) }
                        .listRowBackground(Color.clear)
                }
                let pending = visible.filter { !$0.isFinished }
                let history = visible.filter(\.isFinished)
                if !pending.isEmpty { Section("In progress") { ForEach(pending) { TransferRow(record: $0) } } }
                if !history.isEmpty { Section("History") { ForEach(history) { TransferRow(record: $0) } } }
                Section {
                    DisclosureGroup("About background uploads") {
                        Text("Background transfers resume when iOS allows. Reopen the app after force quitting.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("Transfers")
                .refreshable { await manager.resume() }
        }
    }
}
private struct TransferRow: View {
    let record: TransferRecord
    @Environment(TransferManager.self) private var manager
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: symbol).foregroundStyle(record.state == "failed" ? Color.red : record.state == "cancelled" ? Color.secondary : Color.accentColor).accessibilityHidden(true)
                    Text(record.displayName).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    Spacer(minLength: 0)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { Text(record.stateLabel); Spacer(); Text(bytes).monospacedDigit() }
                    VStack(alignment: .leading, spacing: 4) { Text(record.stateLabel); Text(bytes).monospacedDigit() }
                }.font(.caption).foregroundStyle(.secondary)
                if !record.isFinished { ProgressView(value: record.progress).accessibilityLabel("Upload progress") }
            }.accessibilityElement(children: .combine)
            if let message = record.message { Text(message).font(.footnote).foregroundStyle(.red) }
            if !record.isFinished {
                HStack {
                    if record.state == "failed" { Button("Retry") { manager.retry(record) }.buttonStyle(.bordered) }
                    Button("Cancel upload", role: .destructive) { Task { await manager.cancel(record) } }.buttonStyle(.borderless)
                }
            }
        }.padding(.vertical, record.isFinished ? 2 : 6)
    }
    private var symbol: String {
        switch record.state { case "completed": "checkmark.circle.fill"; case "failed": "exclamationmark.circle"; case "cancelled": "xmark.circle"; default: "arrow.up.circle" }
    }
    private var bytes: String {
        String(format: String(localized: "%@ of %@"), record.completedBytes.formatted(.byteCount(style: .file)), record.totalBytes.formatted(.byteCount(style: .file)))
    }
}
