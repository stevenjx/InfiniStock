import SwiftUI
import SwiftData

/// 侧栏分区。库存再按状态细分，其余是独立列表。
/// 声明顺序即侧栏顺序，也和 ⌘1–⌘5 一一对应，改顺序时两处必须同时改。
enum SidebarSection: Hashable {
    case todos
    case stock(ItemStatus?)
    case orders
    case batches
    case customers

    var label: String {
        switch self {
        case .todos: "待办"
        case .stock(_):
            "库存管理"
        case .orders: "销售记录"
        case .batches: "采购记录"
        case .customers: "客户管理"
        }
    }

    var icon: String {
        switch self {
        case .todos: "checklist"
        case .stock(_):
            "shippingbox"
        case .orders: "doc.text"
        case .batches: "cart"
        case .customers: "person.2"
        }
    }

    var isStock: Bool {
        if case .stock = self { return true }
        return false
    }
}

struct RootView: View {
    let cloudSyncEnabled: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext

    @State private var section: SidebarSection? = .stock(.inStock)
    @State private var itemSelection: Set<PersistentIdentifier> = []
    @State private var orderSelection: PersistentIdentifier?
    @State private var batchSelection: PersistentIdentifier?
    @State private var customerSelection: String?
    @State private var todoSelection: TodoEntry.Key?

    @State private var showingSale = false
    /// 打开出库单那一刻的机器快照。不能直接把派生的 selectedItems 传进 sheet：
    /// 它是每次 body 重算出来的新数组，而 sheet 内部的 @State 只在首次 init 时初始化，
    /// 两边一旦错位，输入框里的价格就会对不上机器。
    @State private var saleItems: [Item] = []
    @State private var showingInspector = false
    @State private var pendingDelete: [Item] = []
    @State private var deleteError: String?

    @Query private var allItems: [Item]
    @Query private var allOrders: [Order]
    @Query private var allBatches: [Batch]

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 158, ideal: 176, max: 220)
        } content: {
            contentColumn(searchPresented: $appState.showingSearch)
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
        } detail: {
            detailPane
                .inspector(isPresented: $showingInspector) {
                    CostInspector(items: selectedItems)
                        .inspectorColumnWidth(min: 230, ideal: 270, max: 340)
                }
        }
        .frame(minWidth: 1080, minHeight: 700)
        .sheet(isPresented: $appState.showingIntake) { IntakeSheet() }
        .sheet(isPresented: $appState.showingImport) { ImportSheet() }
        .sheet(isPresented: $appState.showingSettings) {
            NavigationStack { SettingsView() }
                .frame(minWidth: 520, minHeight: 520)
        }
        .sheet(isPresented: $showingSale) { SaleSheet(items: saleItems) }
        .onChange(of: appState.showingDashboard) { _, showing in
            if showing {
                openWindow(id: "dashboard")
                appState.showingDashboard = false
            }
        }
        .onChange(of: appState.saleRequest) { _, requested in
            guard requested else { return }
            appState.saleRequest = false
            if canSell { openSale() }
        }
        .onChange(of: appState.sectionRequest) { _, request in
            guard let request else { return }
            section = request
            appState.sectionRequest = nil
        }
        .onChange(of: showingSale) { _, isPresented in
            if !isPresented { itemSelection.removeAll() }
        }
        .confirmationDialog(
            pendingDelete.count == 1 ? "删除 1 台机器？" : "删除 \(pendingDelete.count) 台机器？",
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

    // MARK: - 侧栏

    private var sidebar: some View {
        SidebarView(
            selection: Binding(
                get: { activeSection },
                set: { section = $0 }
            ),
            onSettings: { appState.showingSettings = true }
        )
    }

    private func contentColumn(searchPresented: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            PageHeader(title: activeSection.label, items: headerItems) {
                if activeSection.isStock {
                    Button {
                        appState.showingIntake = true
                    } label: {
                        Label("入库", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("入库（⌘N）")

                    Button {
                        openSale()
                    } label: {
                        Label("出库", systemImage: "arrow.up.forward.square")
                    }
                    .controlSize(.small)
                    .disabled(!canSell)
                    .help("出库销售（⌘⇧S）")
                }

                Menu {
                    Button("批量导入 CSV…") { appState.showingImport = true }
                    Button("统计") { openWindow(id: "dashboard") }
                    Divider()
                    Button(showingInspector ? "隐藏检查器" : "显示检查器") {
                        showingInspector.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
                .padding(.horizontal, Token.Space.l)
                .padding(.top, Token.Space.m)
                .padding(.bottom, Token.Space.m)

            bodyColumn(searchPresented: searchPresented)
                .padding(.horizontal, Token.Space.l)
                .padding(.bottom, Token.Space.l)
        }
        .background(Token.Surface.canvas)
        .navigationTitle("")
    }

    /// 销售/采购/客户/待办四页在卡片上方多一层 KPI 结论，库存页直接是卡片。
    @ViewBuilder
    private func bodyColumn(searchPresented: Binding<Bool>) -> some View {
        switch activeSection {
        case .todos:
            VStack(spacing: Token.Space.m) {
                TodosKpiStrip()
                sectionBody(searchPresented: searchPresented)
                    .cardSurface()
            }
        case .orders:
            VStack(spacing: Token.Space.m) {
                OrdersKpiStrip()
                sectionBody(searchPresented: searchPresented)
                    .cardSurface()
            }
        case .batches:
            VStack(spacing: Token.Space.m) {
                BatchesKpiStrip()
                sectionBody(searchPresented: searchPresented)
                    .cardSurface()
            }
        case .customers:
            VStack(spacing: Token.Space.m) {
                CustomersKpiStrip()
                sectionBody(searchPresented: searchPresented)
                    .cardSurface()
            }
        case .stock:
            sectionBody(searchPresented: searchPresented)
                .cardSurface()
        }
    }

    @ViewBuilder
    private func sectionBody(searchPresented: Binding<Bool>) -> some View {
        switch activeSection {
        case .todos:
            TodosView(
                selection: $todoSelection,
                searchPresented: searchPresented,
                onOpenItem: { item in
                    section = .stock(nil)
                    itemSelection = [item.id]
                },
                onOpenBatch: { batch in
                    section = .batches
                    batchSelection = batch.id
                },
                onIntake: { appState.showingIntake = true }
            )
        case .stock(let status):
            InventoryTableView(
                statusFilter: status,
                selection: $itemSelection,
                searchPresented: searchPresented,
                onStatusChange: { section = .stock($0) },
                onDeleteRequest: { pendingDelete = $0 },
                onIntake: { appState.showingIntake = true }
            )
        case .orders:
            OrdersView(
                selection: $orderSelection,
                searchPresented: searchPresented,
                onOpenStock: { section = .stock(.inStock) }
            )
        case .batches:
            BatchesView(selection: $batchSelection, searchPresented: searchPresented)
        case .customers:
            CustomersView(
                selection: $customerSelection,
                searchPresented: searchPresented,
                onOpenStock: { section = .stock(.inStock) }
            )
        }
    }

    /// 页面头右侧摘要，口径与列表同源
    private var headerItems: [PageHeaderSummary] {
        switch activeSection {
        case .stock(let status):
            let pool = allItems.filter { status == nil || $0.status == status }
            let cost = pool.reduce(Decimal(0)) { $0 + $1.landedCost }
            let listed = pool.reduce(Decimal(0)) { $0 + $1.listPrice }
            return [
                .init(label: status?.label ?? "全部", value: "\(pool.count) 台"),
                .init(label: "成本", value: cost.mmk),
                .init(label: "标价", value: listed.mmk),
            ]
        case .todos, .orders, .batches, .customers:
            // 金额已由页面上方的 KPI 卡承担，页头不再重复报数
            return []
        }
    }

    /// 未选中机器时的落脚点
    private var recentItems: [Item] {
        Array(
            allItems
                .filter { $0.status == .inStock }
                .sorted { $0.inboundAt > $1.inboundAt }
                .prefix(3)
        )
    }

    // MARK: - 详情

    @ViewBuilder
    private var detailPane: some View {
        switch activeSection {
        case .todos:
            if let item = selectedTodoItem {
                ItemDetailView(item: item)
            } else if let batch = selectedTodoBatch {
                BatchDetailView(batch: batch)
            } else {
                DetailPlaceholder(
                    title: "选择一条待办",
                    message: "右边是这台机器的完整信息，可直接改标价、出库或分摊运费",
                    systemImage: "checklist"
                )
            }
        case .stock:
            if itemSelection.count == 1, let item = selectedItems.first {
                ItemDetailView(item: item)
            } else if itemSelection.count > 1 {
                DetailPlaceholder(
                    title: "已选中 \(itemSelection.count) 台",
                    message: "点工具栏「出库销售」批量处理，价格可逐台修改",
                    systemImage: "square.stack.3d.up",
                    subtitle: "多选"
                )
            } else {
                RecentItemsPanel(items: recentItems) { item in
                    itemSelection = [item.id]
                }
            }
        case .orders:
            if let order = selectedOrder {
                OrderDetailView(order: order)
            } else {
                DetailPlaceholder(
                    title: "选择一张单据",
                    message: "可查看明细、重出凭证或办理退货",
                    systemImage: "doc.text"
                )
            }
        case .batches:
            if let batch = selectedBatch {
                BatchDetailView(batch: batch)
            } else {
                DetailPlaceholder(
                    title: "选择一个批次",
                    message: "批次里锁定汇率与运费，逐台分摊",
                    systemImage: "shippingbox.and.arrow.backward"
                )
            }
        case .customers:
            if let customer = selectedCustomer {
                CustomerDetailView(customer: customer, orders: allOrders)
            } else {
                DetailPlaceholder(
                    title: "选择一位客户",
                    message: "客户由单据自动汇总，无需单独建档",
                    systemImage: "person.2"
                )
            }
        }
    }

    // MARK: - 派生

    private var activeSection: SidebarSection {
        section ?? .stock(.inStock)
    }

    private var selectedItems: [Item] {
        allItems.filter { itemSelection.contains($0.id) }
            .sorted { $0.serialNumber < $1.serialNumber }
    }

    private var canSell: Bool {
        activeSection.isStock && !itemSelection.isEmpty && selectedItems.allSatisfy { $0.status == .inStock }
    }

    private var selectedOrder: Order? {
        guard let orderSelection else { return nil }
        return allOrders.first { $0.id == orderSelection }
    }

    /// 待办的选中项按目标反查实体，而不是按 TodoEntry 反查：
    /// 定价一改，那条待办就消失了，但右栏不该跟着变空。
    private var selectedTodoItem: Item? {
        guard let todoSelection else { return nil }
        return allItems.first { $0.persistentModelID == todoSelection.target }
    }

    private var selectedTodoBatch: Batch? {
        guard let todoSelection else { return nil }
        return allBatches.first { $0.persistentModelID == todoSelection.target }
    }

    private var selectedBatch: Batch? {
        guard let batchSelection else { return nil }
        return allBatches.first { $0.id == batchSelection }
    }

    private var selectedCustomer: CustomerSummary? {
        guard let customerSelection else { return nil }
        return CustomerSummary.build(from: allOrders).first { $0.id == customerSelection }
    }

    private func openSale() {
        guard canSell else { return }
        saleItems = selectedItems
        showingSale = true
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
        itemSelection.subtract(Set(targets.map(\.id)))
        if !failures.isEmpty {
            deleteError = "以下机器未删除：\(failures.joined(separator: "、"))"
        }
    }
}