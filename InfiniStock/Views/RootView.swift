import SwiftUI
import SwiftData

/// 侧栏分区。库存再按状态细分，其余是独立列表。
enum SidebarSection: Hashable {
    case stock(ItemStatus?)
    case orders
    case batches
    case customers

    var label: String {
        switch self {
        case .stock(let status):
            switch status {
            case .inStock: "在库"
            case .sold: "已售"
            case .locked: "锁定"
            case nil: "全部"
            }
        case .orders: "单据"
        case .batches: "批次"
        case .customers: "客户"
        }
    }

    var icon: String {
        switch self {
        case .stock(let status):
            switch status {
            case .inStock: "shippingbox"
            case .sold: "checkmark.seal"
            case .locked: "lock"
            case nil: "square.grid.2x2"
            }
        case .orders: "doc.text"
        case .batches: "shippingbox.and.arrow.backward"
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

    @State private var showingSale = false
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
        .sheet(isPresented: $appState.showingIntake) { IntakeSheet() }
        .sheet(isPresented: $appState.showingImport) { ImportSheet() }
        .sheet(isPresented: $appState.showingSettings) {
            NavigationStack { SettingsView() }
                .frame(minWidth: 520, minHeight: 520)
        }
        .sheet(isPresented: $showingSale) { SaleSheet(items: selectedItems) }
        .onChange(of: appState.showingDashboard) { _, showing in
            if showing {
                openWindow(id: "dashboard")
                appState.showingDashboard = false
            }
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
                        showingSale = true
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

            sectionBody(searchPresented: searchPresented)
                .cardSurface()
                .padding(.horizontal, Token.Space.l)
                .padding(.bottom, Token.Space.l)
        }
        .background(Token.Surface.canvas)
        .navigationTitle("")
    }

    @ViewBuilder
    private func sectionBody(searchPresented: Binding<Bool>) -> some View {
        switch activeSection {
        case .stock(let status):
            InventoryTableView(
                statusFilter: status,
                selection: $itemSelection,
                searchPresented: searchPresented,
                onStatusChange: { section = .stock($0) },
                onDeleteRequest: { pendingDelete = $0 }
            )
        case .orders:
            OrdersView(selection: $orderSelection, searchPresented: searchPresented)
        case .batches:
            BatchesView(selection: $batchSelection, searchPresented: searchPresented)
        case .customers:
            CustomersView(selection: $customerSelection, searchPresented: searchPresented)
        }
    }

    /// 页面头右侧摘要，口径与列表同源
    private var headerItems: [PageHeaderSummary] {
        switch activeSection {
        case .stock(let status):
            let pool = allItems.filter { status == nil || $0.status == status }
            let cost = pool.reduce(Decimal(0)) { $0 + $1.landedCostCNY }
            let listed = pool.reduce(Decimal(0)) { $0 + $1.listPriceCNY }
            return [
                .init(label: status?.label ?? "全部", value: "\(pool.count) 台"),
                .init(label: "成本", value: cost.cny),
                .init(label: "标价", value: listed.cny),
            ]
        case .orders:
            let valid = allOrders.filter { !$0.isVoided }
            let revenue = valid.reduce(Decimal(0)) { $0 + $1.totalCNY }
            let profit = valid.reduce(Decimal(0)) { $0 + $1.profitCNY }
            return [
                .init(label: "单据", value: "\(allOrders.count) 张"),
                .init(label: "应收", value: revenue.cny),
                .init(label: "毛利", value: profit.cny),
            ]
        case .batches:
            let cost = allBatches.reduce(Decimal(0)) { total, batch in
                total + batch.itemList.reduce(Decimal(0)) { $0 + $1.landedCostCNY }
            }
            return [
                .init(label: "批次", value: "\(allBatches.count) 批"),
                .init(label: "成本合计", value: cost.cny),
            ]
        case .customers:
            let summaries = CustomerSummary.build(from: allOrders)
            let revenue = summaries.reduce(Decimal(0)) { $0 + $1.revenue }
            return [
                .init(label: "客户", value: "\(summaries.count) 位"),
                .init(label: "累计消费", value: revenue.cny),
            ]
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

    private var selectedBatch: Batch? {
        guard let batchSelection else { return nil }
        return allBatches.first { $0.id == batchSelection }
    }

    private var selectedCustomer: CustomerSummary? {
        guard let customerSelection else { return nil }
        return CustomerSummary.build(from: allOrders).first { $0.id == customerSelection }
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