import AppKit
import SwiftUI
import SwiftData

/// 库存页的结论层。页头那行小字只能报三个数，这里把「压了多少钱、能赚多少、
/// 有多少台已经放旧了」分开摆——和销售/采购/客户三页保持同一套骨架。
struct StockKpiStrip: View {
    let statusFilter: ItemStatus?

    @Query private var items: [Item]

    private var pool: [Item] {
        items.filter { statusFilter == nil || $0.status == statusFilter }
    }

    private var cost: Decimal {
        pool.reduce(Decimal(0)) { $0 + $1.landedCost }
    }

    private var listed: Decimal {
        pool.reduce(Decimal(0)) { $0 + $1.listPrice }
    }

    private var overdue: [Item] {
        pool.filter(\.isOverdue)
    }

    private var averageAge: Int {
        guard !pool.isEmpty else { return 0 }
        return pool.reduce(0) { $0 + $1.ageInDays } / pool.count
    }

    private var oldestAge: Int {
        pool.map(\.ageInDays).max() ?? 0
    }

    private var unpricedCount: Int {
        pool.filter { $0.status == .inStock && $0.listPrice <= 0 }.count
    }

    var body: some View {
        HStack(spacing: Token.Space.m) {
            StatCard(
                title: statusFilter?.label ?? "全部机器",
                value: String(
                    format: String(localized: "%lld 台"),
                    Int64(pool.count)
                ),
                systemImage: "shippingbox.fill",
                tone: .brand,
                delta: unpricedCount > 0
                    ? String(format: String(localized: "%lld 台未标价"), Int64(unpricedCount))
                    : String(localized: "全部已定价"),
                deltaTone: unpricedCount > 0 ? .warn : .ok
            )
            StatCard(
                title: "占用成本",
                value: cost.mmk,
                systemImage: "banknote.fill",
                tone: .warn,
                delta: String(localized: "标价合计 \(listed.mmk)")
            )
            StatCard(
                title: "预计毛利",
                value: (listed - cost).signedMMK,
                systemImage: "chart.line.uptrend.xyaxis",
                tone: listed - cost < 0 ? .danger : .ok,
                delta: listed > 0
                    ? String(localized: "毛利率 \(Money.text(((listed - cost) / listed * 100).rounded(1)))%")
                    : String(localized: "还没有标价"),
                deltaTone: listed - cost < 0 ? .danger : .ok
            )
            StatCard(
                title: "平均库龄",
                value: String(
                    format: String(localized: "%lld 天"),
                    Int64(averageAge)
                ),
                systemImage: "clock",
                tone: overdue.isEmpty ? .neutral : .danger,
                delta: overdue.isEmpty
                    ? String(localized: "无呆滞")
                    : String(
                        format: String(localized: "%lld 台超 %lld 天"),
                        Int64(overdue.count),
                        Int64(Item.overdueDays)
                    ),
                deltaTone: overdue.isEmpty ? .neutral : .danger
            )
        }
    }
}

/// 库存主表。工具条 + 表格 + 统计条组成一张完整卡片，
/// 型号列合并序列号成双行单元格，状态走语义徽章。
struct InventoryTableView: View {
    let statusFilter: ItemStatus?
    @Binding var selection: Set<PersistentIdentifier>
    @Binding var searchPresented: Bool
    /// 详情栏是否展开：收起时，选中行要给一个「查看详情」的出口
    var detailVisible: Bool = true
    /// 顶部胶囊切换状态；由上层映射到侧栏分区
    var onStatusChange: (ItemStatus?) -> Void = { _ in }
    /// Delete 键触发；由上层做身份验证与落库
    var onDeleteRequest: ([Item]) -> Void = { _ in }
    /// 空状态里的「入库第一台」
    var onIntake: () -> Void = {}
    /// 批量条与右键菜单的「出库销售」
    var onSell: ([Item]) -> Void = { _ in }
    /// 单台改标价
    var onEdit: (Item) -> Void = { _ in }
    /// 展开详情并选中这台
    var onShowDetail: (Item) -> Void = { _ in }

    @Query(sort: \Item.inboundAt, order: .reverse) private var items: [Item]
    @State private var sortOrder: [KeyPathComparator<Item>] = [KeyPathComparator(\Item.inboundAt, order: .reverse)]
    @State private var searchText = ""
    @State private var sortChoice: SortChoice = .newest

    enum SortChoice: String, CaseIterable, Identifiable {
        case newest = "入库时间"
        case cost = "总进价"
        case price = "标价"
        case age = "库龄"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar {
                SearchField(text: $searchText, prompt: "序列号 / 型号 / 客户", focusRequest: $searchPresented)

                FilterPillGroup(label: "状态", options: statusOptions, selection: statusFilter) { status in
                    onStatusChange(status)
                }

                Spacer(minLength: Token.Space.s)
                sortMenu
            }

            table

            footer
        }
    }

    /// 选中行时脚注变成动作条：原来选中之后唯一的出口在页头，眼睛要跳半个屏幕。
    @ViewBuilder
    private var footer: some View {
        if chosenItems.isEmpty {
            TableFooter(leading: footerLeading)
        } else {
            SelectionActionBar(
                items: chosenItems,
                detailVisible: detailVisible,
                onShowDetail: onShowDetail,
                onEdit: onEdit,
                onSell: onSell,
                onClear: { selection.removeAll() }
            )
        }
    }

    private var chosenItems: [Item] {
        rows.filter { selection.contains($0.id) }
    }

    private var table: some View {
        Table(of: Item.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("型号", value: \.modelName) { item in
                HStack(spacing: 8) {
                    MachineThumb(item: item)
                    CellTitle(title: item.modelName, subtitle: item.serialNumber)
                }
                .padding(.vertical, 6)
            }
            .width(min: 150, ideal: 166)

            TableColumn("规格") { item in
                Text(specText(item))
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
            }
            // 规格要能放下「16GB 512GB」；面板展开时表格会窄掉 340pt，这一列最容易被压
            .width(min: 68, ideal: 76)

            TableColumn("成色") { item in
                Text(item.condition.label)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
            }
            .width(min: 40, ideal: 46)

            TableColumn("电池") { item in
                batteryCell(item)
            }
            .width(min: 46, ideal: 54)

            TableColumn("总进价", value: \.landedCost) { item in
                Text(item.landedCost.mmk)
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 90)

            TableColumn("标价 / 毛利", value: \.listPrice) { item in
                let profit = item.listPrice - item.landedCost
                VStack(alignment: .trailing, spacing: 1) {
                    Text(item.listPrice.mmk)
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.primary)
                    if item.listPrice > 0 {
                        Text(profit.signedMMK)
                            .font(Token.Typography.caption)
                            .foregroundStyle(profit < 0 ? Token.Status.danger : Token.Status.ok)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 90)

            TableColumn("库龄") { item in
                if item.isOverdue {
                    Badge(text: "\(item.ageInDays) 天", tone: .danger, style: .filled)
                } else {
                    Text(String(localized: "\(item.ageInDays) 天"))
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .width(min: 42, ideal: 48)

            if statusFilter == nil {
                TableColumn("状态", value: \.statusRaw) { item in
                    Badge(
                        text: item.status.label,
                        tone: item.status.tone,
                        style: item.status == .inStock ? .outline : .filled
                    )
                }
                .width(min: 54, ideal: 62)
            }

            // 末尾空列专门吸收多余宽度。没有它，SwiftUI 会把整张卡的空白全塞给最后一列，
            // 表头贴左、数字贴右，中间空出三百点——比列宽不够还难看。
            TableColumn("") { _ in EmptyView() }
                .width(min: 0, ideal: 0)
        } rows: {
            ForEach(rows) { item in
                TableRow(item)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .onDeleteCommand {
            let chosen = rows.filter { selection.contains($0.id) }
            guard !chosen.isEmpty else { return }
            onDeleteRequest(chosen)
        }
        .contextMenu(forSelectionType: Item.self) { selected in
            // 只有一台时才给「打开」「改价」：这两件事对一批机器没有单一定义
            if selected.count == 1, let item = selected.first {
                Button("查看详情") { onShowDetail(item) }
                Button("改标价…") { onEdit(item) }
                Divider()
            }
            if !selected.isEmpty {
                let chosen = Array(selected)
                Button(chosen.count == 1 ? "出库销售…" : String(localized: "批量出库 \(chosen.count) 台…")) {
                    onSell(chosen)
                }
                Divider()
                Button("复制序列号") {
                    copy(chosen.map(\.serialNumber).sorted().joined(separator: "\n"))
                }
                Button("复制型号") {
                    copy(chosen.map(\.modelName).sorted().joined(separator: "\n"))
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                EmptyState(
                    title: searchText.isEmpty ? "还没有机器" : "没有匹配结果",
                    message: searchText.isEmpty ? "录入第一台 MacBook，成本、标价与电池一次填完" : "换个序列号或型号关键词试试",
                    systemImage: searchText.isEmpty ? "shippingbox" : "magnifyingglass",
                    actionTitle: searchText.isEmpty ? "入库第一台" : nil,
                    action: searchText.isEmpty ? onIntake : nil
                )
            }
        }
    }

    private var statusOptions: [PillOption<ItemStatus?>] {
        [
            PillOption(value: ItemStatus?.none, title: "全部"),
            PillOption(value: ItemStatus?.some(.inStock), title: "在库"),
            PillOption(value: ItemStatus?.some(.sold), title: "已售"),
            PillOption(value: ItemStatus?.some(.locked), title: "锁定"),
        ]
    }

    private var sortMenu: some View {
        HStack(spacing: 2) {
            Text("排序")
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.tertiary)
            Picker("排序", selection: $sortChoice) {
                ForEach(SortChoice.allCases) { choice in
                    Text(LocalizedStringKey(choice.rawValue)).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .onChange(of: sortChoice) { _, choice in
                sortOrder = [comparator(for: choice)]
            }
        }
        .help("排序方式")
    }

    private func comparator(for choice: SortChoice) -> KeyPathComparator<Item> {
        switch choice {
        case .newest: KeyPathComparator(\Item.inboundAt, order: .reverse)
        case .cost: KeyPathComparator(\Item.landedCost, order: .reverse)
        case .price: KeyPathComparator(\Item.listPrice, order: .reverse)
        case .age: KeyPathComparator(\Item.inboundAt, order: .forward)
        }
    }

    /// 返回本地化资源而不是 String：TableFooter 内部才做查表，
    /// 提前用 String(localized:) 会把筛选关键词当参数，格式串无法翻译。
    private var footerLeading: LocalizedStringResource {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if keyword.isEmpty {
            return "共 \(rows.count) 台"
        }
        return "共 \(rows.count) 台 · 筛选「\(keyword)」"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 电池：健康度为主、循环次数为副。低于阈值转黄，这是二手 MacBook 的压价点。
    private func batteryCell(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.batteryHealthText)
                .font(Token.Typography.money)
                .foregroundStyle(item.isBatteryWeak ? Token.Status.warn : Token.Ink.primary)
            if item.batteryCycles > 0 {
                Text(String(localized: "\(item.batteryCycles) 次"))
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func specText(_ item: Item) -> String {
        let parts = [item.memory, item.storage].filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    private var rows: [Item] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = items.filter { item in
            let statusOK = statusFilter == nil || item.status == statusFilter
            guard statusOK else { return false }
            guard !keyword.isEmpty else { return true }
            return item.serialNumber.localizedCaseInsensitiveContains(keyword)
                || item.modelName.localizedCaseInsensitiveContains(keyword)
                || item.order?.customerName.localizedCaseInsensitiveContains(keyword) == true
        }
        return filtered.sorted(using: sortOrder)
    }
}

/// 机型缩略图。有实物照片就显示照片，没有就用产品线缩写占位。
/// 整列都是文字型号时，30pt 的方块是这张表里唯一能快速定位的视觉锚点。
private struct MachineThumb: View {
    let item: Item
    var size: CGFloat = 28

    private var family: String {
        let name = item.modelName
        if name.localizedCaseInsensitiveContains("Pro") { return "Pro" }
        if name.localizedCaseInsensitiveContains("Air") { return "Air" }
        return "Mac"
    }

    var body: some View {
        ZStack {
            if let data = item.photoData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Token.Surface.field
                Text(family)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Token.Ink.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Token.Border.hairline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// 选中行之后接手的动作条。
///
/// 原来选中一批机器，唯一的出口在页头（隔着整张表），脚注只报一句"已选中 N 台"。
/// 这里把它换成贴着表格的动作：改价、出库、看详情都在鼠标旁边。
private struct SelectionActionBar: View {
    let items: [Item]
    let detailVisible: Bool
    let onShowDetail: (Item) -> Void
    let onEdit: (Item) -> Void
    let onSell: ([Item]) -> Void
    let onClear: () -> Void

    private var cost: Decimal {
        items.reduce(Decimal(0)) { $0 + $1.landedCost }
    }

    /// 已售/锁定的机器不能出库，混选时整体禁用，避免点了才发现一半失败
    private var canSell: Bool {
        !items.isEmpty && items.allSatisfy { $0.status == .inStock }
    }

    var body: some View {
        HStack(spacing: Token.Space.s) {
            Text(String(localized: "已选中 \(items.count) 台"))
                .font(Token.Typography.caption.weight(.medium))
                .foregroundStyle(Token.Ink.primary)
            Text(String(localized: "· 成本 \(cost.mmk)"))
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.secondary)
                .monospacedDigit()

            Spacer(minLength: Token.Space.s)

            if items.count == 1, let item = items.first {
                if !detailVisible {
                    Button("查看详情") { onShowDetail(item) }
                        .controlSize(.small)
                }
                Button("改标价") { onEdit(item) }
                    .controlSize(.small)
            }

            Button("出库销售") { onSell(items) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSell)
                .help(canSell ? "为选中的机器开单" : "选中项里有已售或锁定的机器")

            Button {
                onClear()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Token.Ink.secondary)
            .help("取消选择")
            .accessibilityLabel("取消选择")
        }
        .padding(.horizontal, Token.Space.m)
        .frame(height: 40)
        .background(Token.Accent.fill)
        .overlay(alignment: .top) { Hairline() }
        .accessibilityElement(children: .contain)
    }
}
