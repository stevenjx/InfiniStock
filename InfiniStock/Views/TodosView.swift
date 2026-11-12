import SwiftUI
import SwiftData

/// 待办页的结论层：先回答"今天有多少事、卡了多少钱"，再给清单。
struct TodosKpiStrip: View {
    @Query private var items: [Item]
    @Query private var batches: [Batch]
    @Query private var orders: [Order]

    private var entries: [TodoEntry] {
        TodoCenter.build(items: items, batches: batches, orders: orders,
                                 currentRate: ShopSettings.load().defaultExchangeRate)
    }

    private var outstanding: Decimal {
        orders.reduce(Decimal(0)) { $0 + $1.outstanding }
    }

    private var kindCount: Int {
        Set(entries.map(\.kind)).count
    }

    var body: some View {
        HStack(spacing: Token.Space.m) {
            StatCard(
                title: "待办",
                value: "\(entries.count) 项",
                systemImage: "checklist",
                tone: entries.isEmpty ? .ok : .warn,
                delta: entries.isEmpty ? "全部处理完了" : "\(kindCount) 类问题",
                deltaTone: entries.isEmpty ? .ok : .warn
            )
            StatCard(
                title: "涉及成本",
                value: TodoCenter.involvedCost(entries).mmk,
                systemImage: "banknote.fill",
                tone: .brand,
                delta: "\(TodoCenter.involvedCount(entries)) 台机器"
            )
            StatCard(
                title: "应收未收",
                value: outstanding.mmk,
                systemImage: "banknote.fill",
                tone: outstanding > 0 ? .danger : .ok,
                delta: outstanding > 0 ? "待收账款" : "全部收讫",
                deltaTone: outstanding > 0 ? .danger : .ok
            )
        }
    }
}

/// 待办清单。不新增任何存储：每一行都是从库存和批次现算出来的，
/// 处理掉之后自然消失，不会留下"已勾选但没修"的假完成。
struct TodosView: View {
    @Binding var selection: TodoEntry.Key?
    @Binding var searchPresented: Bool
    /// 跳到库存页并选中这台机器
    var onOpenItem: (Item) -> Void = { _ in }
    /// 跳到采购页并选中这个批次
    var onOpenBatch: (Batch) -> Void = { _ in }
    /// 跳到销售页并选中这张单据
    var onOpenOrder: (Order) -> Void = { _ in }
    /// 空状态里的「去入库」
    var onIntake: () -> Void = {}

    @Query private var items: [Item]
    @Query private var batches: [Batch]
    @Query private var orders: [Order]

    @State private var searchText = ""
    @State private var kindFilter: TodoKind?

    private var allEntries: [TodoEntry] {
        TodoCenter.build(items: items, batches: batches, orders: orders,
                                 currentRate: ShopSettings.load().defaultExchangeRate)
    }

    private var rows: [TodoEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        return allEntries.filter { entry in
            if let kindFilter, entry.kind != kindFilter { return false }
            guard !keyword.isEmpty else { return true }
            return entry.title.localizedCaseInsensitiveContains(keyword)
                || entry.subtitle.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar {
                SearchField(text: $searchText, prompt: "型号 / 序列号 / 批次", focusRequest: $searchPresented)
                Spacer(minLength: Token.Space.s)
                kindMenu
            }

            table

            TableFooter(leading: footerLeading, trailing: footerTrailing)
        }
    }

    /// 六种类型做成菜单而不是一排胶囊：中文类型名太长，一排会挤掉搜索框。
    /// 菜单里顺带报出每类的条数，比胶囊更能回答"哪类最多"。
    private var kindMenu: some View {
        Picker("类型", selection: $kindFilter) {
            Text("全部类型").tag(TodoKind?.none)
            Divider()
            ForEach(TodoKind.allCases) { kind in
                Text("\(kind.title)（\(TodoCenter.count(allEntries, of: kind))）")
                    .tag(TodoKind?.some(kind))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help("按待办类型筛选")
    }

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("类型") { entry in
                kindBadge(entry)
            }
            .width(min: 62, ideal: 72)

            TableColumn("机器 / 批次") { entry in
                CellTitle(title: entry.title, subtitle: entry.subtitle, monospacedSubtitle: entry.item != nil)
            }
            .width(min: 120, ideal: 156)

            TableColumn("待办说明") { entry in
                Text(entry.reason)
                    .font(Token.Typography.caption)
                    .foregroundStyle(isSelected(entry) ? Token.Ink.onAccent.opacity(0.85) : Token.Ink.secondary)
                    .lineLimit(1)
            }
            .width(min: 130, ideal: 190)

            TableColumn("金额") { entry in
                Text(entry.amount.mmk)
                    .font(Token.Typography.money)
                    .foregroundStyle(amountTone(entry))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 94)

            TableColumn("操作") { entry in
                Button(entry.kind.actionHint) {
                    open(entry)
                }
                .buttonStyle(.plain)
                .font(Token.Typography.caption)
                .foregroundStyle(isSelected(entry) ? Token.Ink.onAccent : Token.Accent.brand)
            }
            .width(min: 52, ideal: 60)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .overlay {
            if rows.isEmpty {
                emptyState
            }
        }
    }

    private func isSelected(_ entry: TodoEntry) -> Bool {
        selection == entry.id
    }

    /// 选中行是整行品牌色填充，语义色会直接糊在上面，
    /// 所以选中时统一退回反白色——这是全表唯一需要感知选中态的地方。
    private func amountTone(_ entry: TodoEntry) -> Color {
        if isSelected(entry) { return Token.Ink.onAccent }
        return entry.kind == .negativeMargin ? Token.Status.danger : Token.Ink.primary
    }

    /// 与 Badge 同一套视觉，但多一个"选中"分支
    private func kindBadge(_ entry: TodoEntry) -> some View {
        let selected = isSelected(entry)
        let tone = tone(for: entry.kind)
        return Text(entry.kind.title)
            .font(Token.Typography.caption.weight(.medium))
            .foregroundStyle(selected ? Token.Ink.onAccent : tone.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(selected ? Token.Ink.onAccent.opacity(0.18) : tone.fill, in: .capsule)
            .fixedSize()
    }

    @ViewBuilder
    private var emptyState: some View {
        if !allEntries.isEmpty {
            EmptyState(
                title: "没有匹配的待办",
                message: "换个关键词，或把类型切回「全部类型」",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        } else if items.filter({ $0.status == .inStock }).isEmpty {
            EmptyState(
                title: "还没有库存",
                message: "入库后，未标价、亏本、电池偏弱、库龄超期都会在这里提醒",
                systemImage: "shippingbox",
                actionTitle: "入库第一台",
                action: onIntake
            )
        } else {
            EmptyState(
                title: "今天没有待办",
                message: "在库机器都已定价、电池正常、库龄在 \(Item.overdueDays) 天以内，批次运费也都摊完了",
                systemImage: "checkmark.seal"
            )
        }
    }

    private func open(_ entry: TodoEntry) {
        if let item = entry.item {
            onOpenItem(item)
        } else if let batch = entry.batch {
            onOpenBatch(batch)
        } else if let order = entry.order {
            onOpenOrder(order)
        }
    }

    private func tone(for kind: TodoKind) -> Tone {
        switch kind {
        case .pendingAllocation: .brand
        case .outstanding: .warn
        case .unpriced: .warn
        case .negativeMargin: .danger
        case .currencyRisk: .danger
        case .weakBattery: .warn
        case .aged: .neutral
        }
    }

    private var footerLeading: String {
        guard !rows.isEmpty else { return "共 0 项" }
        return "共 \(rows.count) 项 · 涉及 \(TodoCenter.involvedCount(rows)) 台"
    }

    private var footerTrailing: String? {
        guard let selection, let entry = rows.first(where: { $0.id == selection }) else { return nil }
        return "\(entry.kind.title) · \(entry.title)"
    }
}
