import SwiftUI
import SwiftData

@main struct PinHaoYunApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var api: APIClient
    @State private var transfers: TransferManager
    @State private var backup: BackupManager
    @State private var photoImport = PhotoImportSession()
    private let container: ModelContainer
    init() {
        do { container = try ModelContainer(for: TransferRecord.self, BackupSettings.self, BackupAsset.self) }
        catch { fatalError("Unable to open the durable transfer store: \(error)") }
        let client = APIClient()
        let manager = TransferManager(api: client, container: container)
        _api = State(initialValue: client); _transfers = State(initialValue: manager)
        _backup = State(initialValue: BackupManager(api: client, transfers: manager))
        AppDelegate.transfers = manager
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(api).environment(transfers).environment(backup).environment(photoImport).modelContainer(container).environment(\.modelContext, transfers.context)
                .tint(.blue)
                .task(id: api.tokens?.sub) { await backup.activate(); if api.tokens != nil { await transfers.resume() } }
                .onChange(of: api.tokens?.requiresConsent) { _, _ in backup.check() }
                .onChange(of: api.tokens?.sub) { _, owner in if photoImport.owner != owner { photoImport.stop() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await backup.activate(); await transfers.resume() } }
                    if phase == .background { backup.enterBackground() }
                }
        }
    }
}
private struct RootView: View {
    private enum Tab { case library, transfers, account }
    @State private var selectedTab = Tab.library
    @Environment(APIClient.self) private var api
    @Environment(TransferManager.self) private var transfers
    var body: some View {
        Group {
            if api.tokens != nil {
                if api.tokens?.requiresConsent == true { ConsentView() }
                else {
                    TabView(selection: $selectedTab) {
                        LibraryView(showTransfers: { selectedTab = .transfers }).tabItem { Label("Library", systemImage: "photo.on.rectangle") }.tag(Tab.library)
                        TransfersView(showLibrary: { selectedTab = .library }).tabItem { Label("Transfers", systemImage: "arrow.up.arrow.down") }.tag(Tab.transfers)
                        AccountView().tabItem { Label("Account", systemImage: "person.crop.circle") }.tag(Tab.account)
                    }.task { await transfers.resume() }
                }
            } else if api.deletionReceipt != nil { DeletionReceiptView() }
            else { AuthView() }
        }.onChange(of: api.tokens?.sub) { _, _ in selectedTab = .library }
    }
}
@MainActor final class AppDelegate: NSObject, UIApplicationDelegate {
    static var transfers: TransferManager?
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == "com.jake177.pinhaoyun.transfers" else { completionHandler(); return }
        Self.transfers?.backgroundCompletion = completionHandler
        if Self.transfers == nil { completionHandler() }
    }
}
