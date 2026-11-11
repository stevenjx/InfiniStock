import SwiftUI
import SwiftData

@main
struct InfiniStockApp: App {
    private let container: ModelContainer
    private let cloudSyncEnabled: Bool

    @State private var appState = AppState()
    @State private var showingSettings = false

    init() {
        let store = AppStore.shared
        container = store.container
        cloudSyncEnabled = store.cloudSyncEnabled
    }

    var body: some Scene {
        WindowGroup {
            RootView(cloudSyncEnabled: cloudSyncEnabled)
                .environment(appState)
        }
        .defaultSize(width: 1280, height: 800)
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("入库…") {
                    appState.showingIntake = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("搜索…") {
                    appState.showingSearch = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("批量导入 CSV…") {
                    appState.showingImport = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("统计") {
                    appState.showingDashboard = true
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    appState.showingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("统计", id: "dashboard") {
            DashboardView(cloudSyncEnabled: cloudSyncEnabled)
                .environment(appState)
        }
        .modelContainer(container)
    }
}
