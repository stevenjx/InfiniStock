import SwiftUI
import SwiftData

enum InventoryFilter: Hashable, CaseIterable {
    case inStock
    case sold
    case all

    var status: ItemStatus? {
        switch self {
        case .inStock: .inStock
        case .sold: .sold
        case .all: nil
        }
    }

    var label: String {
        switch self {
        case .inStock: "在库"
        case .sold: "已售"
        case .all: "全部"
        }
    }

    var icon: String {
        switch self {
        case .inStock: "shippingbox"
        case .sold: "checkmark.seal"
        case .all: "square.grid.2x2"
        }
    }
}

struct RootView: View {
    let cloudSyncEnabled: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext

    @State private var filter: InventoryFilter? = .inStock
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var showingSale = false
    @State private var showingInspector = false

    @Query private var allItems: [Item]

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            List(selection: $filter) {
                ForEach(InventoryFilter.allCases, id: \.self) { item in
                    Label(item.label, systemImage: item.icon)
                        .tag(Optional(item))
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } content: {
            InventoryTableView(
                statusFilter: activeFilter.status,
                selection: $selection,
                searchPresented: $appState.showingSearch
            )
            .navigationSplitViewColumnWidth(min: 460, ideal: 700)
            .navigationTitle(activeFilter.label)
        } detail: {
            detailPane
                .inspector(isPresented: $showingInspector) {
                    CostInspector(items: selectedItems)
                        .inspectorColumnWidth(min: 220, ideal: 260, max: 340)
                }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.showingIntake = true
                } label: {
                    Label("入库", systemImage: "plus")
                }
                .help("入库（⌘N）")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSale = true
                } label: {
                    Label("出库销售", systemImage: "arrow.up.forward.square")
                }
                .disabled(!canSell)
                .help("出库销售")
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("统计") { openWindow(id: "dashboard") }
                    Divider()
                    Button(showingInspector ? "隐藏检查器" : "显示检查器") {
                        showingInspector.toggle()
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $appState.showingIntake) {
            IntakeSheet()
        }
        .sheet(isPresented: $showingSale) {
            SaleSheet(items: selectedItems)
        }
        .onChange(of: showingSale) { _, isPresented in
            if !isPresented { selection.removeAll() }
        }
        .task {
            #if DEBUG
            DebugSeed.seedIfRequested(modelContext)
            #endif
        }
    }

    private var activeFilter: InventoryFilter {
        filter ?? .inStock
    }

    private var selectedItems: [Item] {
        allItems.filter { selection.contains($0.id) }
            .sorted { $0.serialNumber < $1.serialNumber }
    }

    private var canSell: Bool {
        !selection.isEmpty && selectedItems.allSatisfy { $0.status == .inStock }
    }

    @ViewBuilder
    private var detailPane: some View {
        if selection.count == 1, let item = selectedItems.first {
            ItemDetailView(item: item)
        } else if selection.count > 1 {
            ContentUnavailableView(
                "已选中 \(selection.count) 台",
                systemImage: "square.stack.3d.up",
                description: Text("点工具栏「出库销售」按标价批量处理")
            )
        } else {
            ContentUnavailableView(
                "选择一台机器",
                systemImage: "shippingbox",
                description: Text("中间列表可按序列号或型号筛选")
            )
        }
    }
}
