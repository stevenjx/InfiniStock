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
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 820)
        .windowResizability(.contentMinSize)
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

                Button("出库销售") {
                    appState.saleRequest = true
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("批量导入 CSV…") {
                    appState.showingImport = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("统计") {
                    appState.showingDashboard = true
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("显示或隐藏详情") {
                    appState.detailToggleRequest = true
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }
            CommandGroup(after: .sidebar) {
                Button("待办") { appState.sectionRequest = .todos }
                    .keyboardShortcut("1", modifiers: .command)
                Button("库存管理") { appState.sectionRequest = .stock(.inStock) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("销售记录") { appState.sectionRequest = .orders }
                    .keyboardShortcut("3", modifiers: .command)
                Button("采购记录") { appState.sectionRequest = .batches }
                    .keyboardShortcut("4", modifiers: .command)
                Button("客户管理") { appState.sectionRequest = .customers }
                    .keyboardShortcut("5", modifiers: .command)
                Button("报表") { appState.sectionRequest = .report }
                    .keyboardShortcut("6", modifiers: .command)
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
                .frame(minWidth: 780, minHeight: 560)
                .background(WindowFrameGuard())
        }
        .defaultSize(width: 1060, height: 820)
        .windowResizability(.contentMinSize)
        .modelContainer(container)
    }
}
