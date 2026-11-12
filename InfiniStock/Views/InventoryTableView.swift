import AppKit
import SwiftUI
import SwiftData

/// 库存主表。工具条 + 表格 + 统计条组成一张完整卡片，
/// 型号列合并序列号成双行单元格，状态走语义徽章。
struct InventoryTableView: View {
    let statusFilter: ItemStatus?
    @Binding var selection: Set<PersistentIdentifier>
    @Binding var searchPresented: Bool
    /// 顶部胶囊切换状态；由上层映射到侧栏分区
    var onStatusChange: (ItemStatus?) -> Void = { _ in }
    /// Delete 键触发；由上层做身份验证与落库
    var onDeleteRequest: ([Item]) -> Void = { _ in }

    @Query(sort: \Item.inboundAt, order: .reverse) private var items: [Item]
    @State private var sortOrder: [KeyPathComparator<Item>] = [KeyPathComparator(\Item.inboundAt, order: .reverse)]
    @State private var searchText = ""
    @State private var sortChoice: SortChoice = .newest

    enum SortChoice: String, CaseIterable, Identifiable {
        case newest = "入库时间"
        case cost = "落地成本"
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

            TableFooter(leading: footerLeading, trailing: footerTrailing)
        }
    }

    private var table: some View {
        Table(of: Item.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("型号", value: \.modelName) { item in
                CellTitle(title: item.modelName, subtitle: item.serialNumber)
                    .padding(.vertical, 6)
            }
            .width(min: 138, ideal: 170)

            TableColumn("规格") { item in
                Text(specText(item))
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
            }
            .width(min: 56, ideal: 72)

            TableColumn("落地成本", value: \.landedCostCNY) { item in
                Text(item.landedCostCNY.cny)
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.primary)
            }
            .width(min: 88, ideal: 100)

            TableColumn("标价 / 毛利", value: \.listPriceCNY) { item in
                let profit = item.listPriceCNY - item.landedCostCNY
                VStack(alignment: .trailing, spacing: 1) {
                    Text(item.listPriceCNY.cny)
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.primary)
                    if item.listPriceCNY > 0 {
                        Text(profit.signedCNY)
                            .font(Token.Typography.caption)
                            .foregroundStyle(profit < 0 ? Token.Status.danger : Token.Status.ok)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 88, ideal: 100)

            TableColumn("库龄") { item in
                if item.isOverdue {
                    Badge(text: "\(item.ageInDays) 天", tone: .danger, style: .filled)
                } else {
                    Text("\(item.ageInDays) 天")
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.secondary)
                }
            }
            .width(min: 50, ideal: 58)

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
            if !selected.isEmpty {
                Button("选择并出库") { selection = Set(selected.map(\.id)) }
                Divider()
                Button("复制序列号") {
                    let text = selected.map(\.serialNumber).sorted().joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                EmptyState(
                    title: searchText.isEmpty ? "没有机器" : "没有匹配结果",
                    message: searchText.isEmpty ? "点工具栏「入库」或按 ⌘N 录入第一台" : "换个序列号或型号关键词试试",
                    systemImage: searchText.isEmpty ? "shippingbox" : "magnifyingglass"
                )
                .allowsHitTesting(false)
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
                    Text(choice.rawValue).tag(choice)
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
        case .cost: KeyPathComparator(\Item.landedCostCNY, order: .reverse)
        case .price: KeyPathComparator(\Item.listPriceCNY, order: .reverse)
        case .age: KeyPathComparator(\Item.inboundAt, order: .forward)
        }
    }

    private var footerLeading: String {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if keyword.isEmpty {
            return "共 \(rows.count) 台"
        }
        return "共 \(rows.count) 台 · 筛选「\(keyword)」"
    }

    private var footerTrailing: String? {
        let chosen = rows.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return nil }
        let cost = chosen.reduce(Decimal(0)) { $0 + $1.landedCostCNY }
        return "已选中 \(chosen.count) 台 · 成本 \(cost.cny)"
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
