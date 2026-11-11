import SwiftUI
import SwiftData

struct RootView: View {
    let cloudSyncEnabled: Bool

    var body: some View {
        #if os(macOS)
        MacRootView(cloudSyncEnabled: cloudSyncEnabled)
        #else
        PhoneRootView(cloudSyncEnabled: cloudSyncEnabled)
        #endif
    }
}

#if os(macOS)
private struct MacRootView: View {
    let cloudSyncEnabled: Bool
    @State private var selection: Item?
    @State private var showingDashboard = false

    var body: some View {
        NavigationSplitView {
            InventoryListView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            if let selection {
                ItemDetailView(item: selection)
            } else {
                ContentUnavailableView(
                    "选择一台机器",
                    systemImage: "shippingbox",
                    description: Text("左侧列表可按序列号或型号筛选")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingDashboard = true
                } label: {
                    Label("统计", systemImage: "chart.bar")
                }
            }
        }
        .sheet(isPresented: $showingDashboard) {
            NavigationStack {
                DashboardView(cloudSyncEnabled: cloudSyncEnabled)
            }
            .frame(minWidth: 560, minHeight: 460)
        }
    }
}
#endif

#if os(iOS)
private struct PhoneRootView: View {
    let cloudSyncEnabled: Bool

    var body: some View {
        TabView {
            NavigationStack {
                InventoryListView(selection: .constant(nil))
            }
            .tabItem { Label("库存", systemImage: "shippingbox") }

            NavigationStack {
                DashboardView(cloudSyncEnabled: cloudSyncEnabled)
            }
            .tabItem { Label("统计", systemImage: "chart.bar") }
        }
    }
}
#endif
