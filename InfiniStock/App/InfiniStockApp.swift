import SwiftUI
import SwiftData

@main
struct InfiniStockApp: App {
    private let container: ModelContainer
    private let cloudSyncEnabled: Bool

    init() {
        let store = AppStore.make()
        container = store.container
        cloudSyncEnabled = store.cloudSyncEnabled
    }

    var body: some Scene {
        WindowGroup {
            RootView(cloudSyncEnabled: cloudSyncEnabled)
        }
        .modelContainer(container)
    }
}
