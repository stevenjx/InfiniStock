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
    case report

    var label: String {
        switch self {
        case .todos: "待办"
        case .stock(_):
            "库存管理"
        case .orders: "销售记录"
        case .batches: "采购记录"
        case .customers: "客户管理"
        case .report: "报表"
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
        case .report: "chart.bar.doc.horizontal"
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
    @State private var reportRange: ReportRange = .thisMonth
    /// 只在 Debug 截图核对时被 `ui.flag` 赋值，Release 恒为 nil。
    @State private var debugScheme: ColorScheme?

    @State private var showingSale = false
    /// 打开出库单那一刻的机器快照。不能直接把派生的 selectedItems 传进 sheet：
    /// 它是每次 body 重算出来的新数组，而 sheet 内部的 @State 只在首次 init 时初始化，
    /// 两边一旦错位，输入框里的价格就会对不上机器。
    @State private var saleItems: [Item] = []
    /// 详情栏是否展开。收起来之后列表独占整栏，不再被固定宽度的右栏挤着。
    /// 存进 UserDefaults：下次打开还是上次的选择，不用每次手动收起。
    @AppStorage("infinistock.detailVisible") private var detailVisible = true
    /// 从列表批量条/右键菜单发起的改标价
    @State private var editingItem: Item?
    @State private var pendingDelete: [Item] = []
    @State private var deleteError: String?
    @State private var showingBackupPrompt = false

    @Query private var allItems: [Item]
    @Query private var allOrders: [Order]
    @Query private var allBatches: [Batch]

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 158, ideal: 176, max: 220)
        } detail: {
            contentColumn(searchPresented: $appState.showingSearch)
                // 详情栏交给原生 inspector：滑入/滑出、可拖宽度、减弱动态效果
                // 都是系统的行为，比自己拿 HStack 拼一列再插值宽度稳。
                .inspector(isPresented: $detailVisible) {
                    detailPane
                        .inspectorColumnWidth(min: 304, ideal: 340, max: 420)
                        .environment(\.dismissDetail, DetailDismissAction { setDetailVisible(false) })
                }
        }
        .frame(minWidth: 960, minHeight: 620)
        // 系统标题栏默认用窗口材质，和这套暖白画布不是一回事，会横出一条灰带。
        // 显式铺成画布色，标题栏和内容才连成一片。
        .toolbarBackground(Token.Surface.canvas, for: .windowToolbar)
        .background(WindowFrameGuard())
        .sheet(isPresented: $appState.showingIntake) { IntakeSheet() }
        .sheet(isPresented: $appState.showingImport) { ImportSheet() }
        .sheet(isPresented: $appState.showingSettings) {
            NavigationStack { SettingsView(initialPane: appState.settingsPane) }
                .frame(minWidth: 760, minHeight: 560)
        }
        .onChange(of: appState.showingSettings) { _, showing in
            // 关掉之后复位，下次用 ⌘, 打开仍然是「店铺」，不会永远停在备份栏
            if !showing { appState.settingsPane = .shop }
        }
        .sheet(isPresented: $showingBackupPrompt) {
            BackupPromptSheet()
                .frame(width: 420)
        }
        .sheet(isPresented: $showingSale) { SaleSheet(items: saleItems) }
        .sheet(isPresented: Binding(
            get: { editingItem != nil },
            set: { if !$0 { editingItem = nil } }
        )) {
            if let editingItem {
                ItemEditSheet(item: editingItem)
            }
        }
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
        .onChange(of: appState.detailToggleRequest) { _, requested in
            guard requested else { return }
            appState.detailToggleRequest = false
            setDetailVisible(!detailVisible)
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
            applyDebugUIRequest()
            #endif
            // 调试库里的样例数据不能写进用户真实的备份目录：那会污染备份历史，
            // 还会因为保留份数把真正的快照挤掉。
            if !AppStore.shared.isDebugStore {
                BackupService.autoBackupIfNeeded(from: modelContext)
            }
            maybePromptForBackupFolder()
        }
        .preferredColorScheme(debugScheme)
    }

    // MARK: - 调试入口

    #if DEBUG
    /// 截图核对用的入口。参数走文件而不是启动参数：`open --args` 只在首次冷启动时
    /// 才把参数递进来，重开一次就只剩 argv[0]，靠它做验收会时灵时不灵。
    ///
    ///   ~/Library/Containers/com.infinistock.app/Data/Library/Application Support/ui.flag
    ///
    /// 内容按行写，读完即删：
    ///
    ///   section=report | orders | batches | customers | todos
    ///   dark / light        强制外观
    ///   detail=off          收起详情栏
    ///   select=first|sold|unpriced   选中一台机器
    ///   settings            0.5 秒后弹出设置
    ///
    /// 不参与 Release 构建，也不碰 UserDefaults（`detail=off` 会写 AppStorage，属例外）。
    private func applyDebugUIRequest() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let flag = support.appendingPathComponent("ui.flag")
        guard let text = try? String(contentsOf: flag, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: flag)

        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        func value(_ name: String) -> String? {
            lines.first { $0.hasPrefix("\(name)=") }?
                .split(separator: "=", maxSplits: 1)
                .last
                .map(String.init)
        }

        switch value("section") {
        case "todos": section = .todos
        case "orders": section = .orders
        case "batches": section = .batches
        case "customers": section = .customers
        case "report": section = .report
        default: break
        }

        if lines.contains("dark") { debugScheme = .dark }
        if lines.contains("light") { debugScheme = .light }
        if value("detail") == "off" { detailVisible = false }
        if value("detail") == "on" { detailVisible = true }

        // 截图详情面板用：按状态挑一台自动选中，省掉手点
        let target: Item? = switch value("select") {
        case "first": allItems.first { $0.status == .inStock }
        case "sold": allItems.first { $0.status == .sold }
        case "unpriced": allItems.first { $0.status == .inStock && $0.listPrice <= 0 }
        default: nil
        }
        if let target { itemSelection = [target.id] }
        if value("select") == "many" {
            itemSelection = Set(allItems.filter { $0.status == .inStock }.prefix(3).map(\.id))
        }

        // 截图验收设置窗口：等首帧渲染完再弹，否则 sheet 会被同一轮布局吞掉
        if lines.contains("settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appState.showingSettings = true
            }
        }

        // 验收备份相关界面：settings=backup 直接落到备份分栏，backup-prompt 强制弹首次提示
        if value("settings") == "backup" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appState.settingsPane = .backup
                appState.showingSettings = true
            }
        }
        // 同理，截图验收统计窗口
        if lines.contains("dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                appState.showingDashboard = true
            }
        }
    }
    #endif

    // MARK: - 侧栏

    private var sidebar: some View {
        SidebarView(
            selection: Binding(
                get: { activeSection },
                set: { section = $0 }
            ),
            onSettings: { openSettings() },
            onOpenBackup: { openSettings(.backup) }
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
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Button {
                    setDetailVisible(!detailVisible)
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12, weight: .medium))
                        // 图标本身就表示状态：开着用品牌色，收起时退回次要灰
                        .foregroundStyle(detailVisible ? Token.Accent.brand : Token.Ink.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(detailVisible ? "收起详情（⌥⌘D）" : "展开详情（⌥⌘D）")
                .accessibilityLabel(detailVisible ? "收起详情" : "展开详情")
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
        case .report:
            sectionBody(searchPresented: searchPresented)
                .cardSurface()
        case .stock(let status):
            VStack(spacing: Token.Space.m) {
                StockKpiStrip(statusFilter: status)
                sectionBody(searchPresented: searchPresented)
                    .cardSurface()
            }
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
                onOpenOrder: { order in
                    section = .orders
                    orderSelection = order.id
                },
                onIntake: { appState.showingIntake = true },
                onOpenBackup: { openSettings(.backup) }
            )
        case .stock(let status):
            InventoryTableView(
                statusFilter: status,
                selection: $itemSelection,
                searchPresented: searchPresented,
                detailVisible: detailVisible,
                onStatusChange: { section = .stock($0) },
                onDeleteRequest: { pendingDelete = $0 },
                onIntake: { appState.showingIntake = true },
                onSell: { items in
                    // 先选中再打开：出库单取消后，选中的仍是这批机器
                    itemSelection = Set(items.map(\.id))
                    saleItems = items
                    showingSale = true
                },
                onEdit: { editingItem = $0 },
                onShowDetail: { item in
                    itemSelection = [item.id]
                    setDetailVisible(true)
                }
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
        case .report:
            ReportView(range: $reportRange)
        }
    }

    /// 页头不再报数：库存页的结论已经由 KPI 卡承担，重复一遍只是噪音
    private var headerItems: [PageHeaderSummary] {
        []
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
            } else if let order = selectedTodoOrder {
                OrderDetailView(order: order)
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
                SelectionSummaryView(items: selectedItems)
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
        case .report:
            ReportScopePanel(range: reportRange)
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

    private var selectedTodoOrder: Order? {
        guard let todoSelection else { return nil }
        return allOrders.first { $0.persistentModelID == todoSelection.target }
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

    private func openSettings(_ pane: SettingsPane = .shop) {
        appState.settingsPane = pane
        appState.showingSettings = true
    }

    /// 库里有货、又没配备份目录时，开机提示一次。
    /// 「以后再说」只关掉这个弹窗，待办里那条备份提醒仍然会在。
    private func maybePromptForBackupFolder() {
        guard !AppStore.shared.isDebugStore, !allItems.isEmpty else { return }
        let settings = ShopSettings.load()
        guard settings.autoBackupEnabled, !settings.backupPromptDismissed else { return }
        guard BackupService.backupFolder() == nil else { return }
        showingBackupPrompt = true
    }

    private func setDetailVisible(_ visible: Bool) {
        // 动画曲线交给 HStack 上的 .animation(.easeOut(duration: 0.18))，
        // 这里再包一层 withAnimation 会和它打架，两边各用一条曲线。
        detailVisible = visible
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