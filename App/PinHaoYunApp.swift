import SwiftUI
import SwiftData

@main struct PinHaoYunApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var api: APIClient
    @State private var transfers: TransferManager
    private let container: ModelContainer
    init() {
        do { container = try ModelContainer(for: TransferRecord.self) }
        catch { fatalError("Unable to open the durable transfer store: \(error)") }
        let client = APIClient()
        let manager = TransferManager(api: client, container: container)
        _api = State(initialValue: client); _transfers = State(initialValue: manager)
        AppDelegate.transfers = manager
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(api).environment(transfers).modelContainer(container).environment(\.modelContext, transfers.context)
                .tint(.blue)
                .task(id: api.tokens?.sub) { if api.tokens != nil { await transfers.resume() } }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await transfers.resume() } } }
        }
    }
}
private struct RootView: View {
    @Environment(APIClient.self) private var api
    @Environment(TransferManager.self) private var transfers
    var body: some View {
        Group {
            if api.tokens != nil {
                if api.tokens?.requiresConsent == true { ConsentView() }
                else {
                    TabView {
                        LibraryView().tabItem { Label("Library", systemImage: "photo.on.rectangle") }
                        TransfersView().tabItem { Label("Transfers", systemImage: "arrow.up.arrow.down") }
                        AccountView().tabItem { Label("Account", systemImage: "person.crop.circle") }
                    }.task { await transfers.resume() }
                }
            } else if api.deletionReceipt != nil { DeletionReceiptView() }
            else { AuthView() }
        }
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
