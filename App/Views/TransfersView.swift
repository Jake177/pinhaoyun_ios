import SwiftUI
import SwiftData

struct TransfersView: View {
    @Environment(APIClient.self) private var api
    @Environment(TransferManager.self) private var manager
    @Query(sort: \TransferRecord.createdAt, order: .reverse) private var records: [TransferRecord]
    private var visible: [TransferRecord] { records.filter { $0.ownerSub == api.tokens?.sub } }
    var body: some View {
        NavigationStack {
            List {
                if visible.isEmpty {
                    ContentUnavailableView("No transfers yet", systemImage: "arrow.up.arrow.down", description: Text("Add photos and videos from your library. Uploads and retries appear here."))
                        .listRowBackground(Color.clear)
                }
                ForEach(visible) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: record.state == "completed" ? "checkmark.circle.fill" : record.state == "failed" ? "exclamationmark.circle" : "arrow.up.circle")
                                .foregroundStyle(record.state == "failed" ? Color.red : Color.accentColor)
                            Text(record.displayName).font(.headline).lineLimit(2)
                            Spacer()
                        }
                        HStack { Text(record.stateLabel); Spacer(); Text(record.completedBytes.formatted(.byteCount(style: .file))).monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                        if !record.isFinished { ProgressView(value: record.progress).accessibilityLabel("Upload progress") }
                        if let message = record.message { Text(message).font(.footnote).foregroundStyle(.red) }
                        HStack {
                            if record.state == "failed" { Button("Retry") { manager.retry(record) }.buttonStyle(.bordered) }
                            if !record.isFinished { Button("Cancel upload", role: .destructive) { Task { await manager.cancel(record) } }.buttonStyle(.borderless) }
                        }
                    }.padding(.vertical, 6)
                }
            }
            .navigationTitle("Transfers")
            .refreshable { await manager.resume() }
            .safeAreaInset(edge: .bottom) { Text("Background transfers resume when iOS allows. Reopen the app after force quitting.").font(.footnote).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity).background(.bar) }
        }
    }
}
