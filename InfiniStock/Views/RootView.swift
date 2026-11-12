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
    @State private var selectedOrderID: PersistentIdentifier?
    @State private var pendingDelete: [Item] = []
    @State private var deleteError: String?

    @Query private var allItems: [Item]
    @Query private var allOrders: [Order]

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            List(selection: $filter) {
                Section("库存") {
                    ForEach(InventoryFilter.allCases, id: \.self) { item in
                        Label(item.label, systemImage: item.icon)
                            .tag(Optional(item))
                    }
                }
                Section("交易") {
                    Label("单据", systemImage: "doc.text")
                        .tag(Optional<InventoryFilter>(nil))
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } content: {
            if showingOrders {
                OrdersView(selection: $selectedOrderID)
                    .navigationSplitViewColumnWidth(min: 520, ideal: 760)
            } else {
                InventoryTableView(
                    statusFilter: activeFilter.status,
                    selection: $selection,
                    searchPresented: $appState.showingSearch,
                    onDeleteRequest: { items in pendingDelete = items }
                )
                .navigationSplitViewColumnWidth(min: 460, ideal: 700)
                .navigationTitle(activeFilter.label)
            }
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
                .disabled(showingOrders)
                .help("入库（⌘N）")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSale = true
                } label: {
                    Label("出库销售", systemImage: "arrow.up.forward.square")
                }
                .disabled(!canSell || showingOrders)
                .help("出库销售")
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("批量导入 CSV…") { appState.showingImport = true }
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
        .sheet(isPresented: $appState.showingImport) {
            ImportSheet()
        }
        .sheet(isPresented: $appState.showingSettings) {
            NavigationStack { SettingsView() }
                .frame(minWidth: 520, minHeight: 520)
        }
        .onChange(of: appState.showingDashboard) { _, showing in
            if showing {
                openWindow(id: "dashboard")
                appState.showingDashboard = false
            }
        }
        .sheet(isPresented: $showingSale) {
            SaleSheet(items: selectedItems)
        }
        .onChange(of: showingSale) { _, isPresented in
            if !isPresented { selection.removeAll() }
        }
        .confirmationDialog(
            pendingDelete.count == 1
                ? "删除 1 台机器？"
                : "删除 \(pendingDelete.count) 台机器？",
            isPresented: Binding(
                get: { !pendingDelete.isEmpty },
                set: { if !$0 { pendingDelete = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await performBatchDelete() }
            }
            Button("取消", role: .cancel) { pendingDelete = [] }
        } message: {
            Text("仅用于清理误录入。删除后不可恢复，且需要系统身份验证。已售出的机器请先退货或作废单据。")
        }
        .alert("删除失败", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("好", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .task {
            #if DEBUG
            DebugSeed.seedIfRequested(modelContext)
            #endif
            BackupService.autoBackupIfNeeded(from: modelContext)
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

    private func performBatchDelete() async {
        let targets = pendingDelete
        pendingDelete = []

        let passed = await BiometricGate.authenticate(reason: "删除 \(targets.count) 台机器")
        guard passed else {
            deleteError = "身份验证未通过，删除已取消"
            return
        }

        var failures: [String] = []
        for item in targets {
            do {
                try InventoryService.delete(item, in: modelContext)
            } catch {
                failures.append(item.serialNumber)
            }
        }
        selection.subtract(Set(targets.map(\.id)))
        if !failures.isEmpty {
            deleteError = "以下机器未删除：\(failures.joined(separator: "、"))"
        }
    }

    private var showingOrders: Bool { filter == nil }

    private var selectedOrder: Order? {
        guard let selectedOrderID else { return nil }
        return allOrders.first { $0.id == selectedOrderID }
    }

    @ViewBuilder
    private var detailPane: some View {
        if showingOrders {
            if let order = selectedOrder {
                OrderDetailView(order: order)
            } else {
                EmptyState(
                    title: "选择一张单据",
                    message: "中间列表可搜索单号、客户或序列号",
                    systemImage: "doc.text"
                )
            }
        } else if selection.count == 1, let item = selectedItems.first {
            ItemDetailView(item: item)
        } else if selection.count > 1 {
            EmptyState(
                title: "已选中 \(selection.count) 台",
                message: "点工具栏「出库销售」批量处理，价格可逐台修改",
                systemImage: "square.stack.3d.up"
            )
        } else {
            EmptyState(
                title: "选择一台机器",
                message: "中间列表可按序列号、型号或客户筛选",
                systemImage: "shippingbox"
            )
        }
    }
}
