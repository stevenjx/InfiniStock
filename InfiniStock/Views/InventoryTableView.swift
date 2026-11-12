import AppKit
import SwiftUI
import SwiftData

/// 库存主表。型号列合并序列号成双行单元格，状态走语义徽章，
/// 目标是 1080p 宽度下不出现横向滚动。
struct InventoryTableView: View {
    let statusFilter: ItemStatus?
    @Binding var selection: Set<PersistentIdentifier>
    @Binding var searchPresented: Bool
    /// Delete 键触发；由上层做身份验证与落库
    var onDeleteRequest: ([Item]) -> Void = { _ in }

    @Query(sort: \Item.inboundAt, order: .reverse) private var items: [Item]
    @State private var sortOrder: [KeyPathComparator<Item>] = [KeyPathComparator(\Item.inboundAt, order: .reverse)]
    @State private var searchText = ""

    var body: some View {
        Table(of: Item.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("型号", value: \.modelName) { item in
                CellTitle(title: item.modelName, subtitle: item.serialNumber)
            }
            .width(min: 150, ideal: 190)

            TableColumn("规格") { item in
                Text(specText(item))
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
            }
            .width(min: 62, ideal: 80)

            TableColumn("落地成本", value: \.landedCostCNY) { item in
                Text(item.landedCostCNY.cny)
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.primary)
            }
            .width(min: 84, ideal: 94)

            TableColumn("标价", value: \.listPriceCNY) { item in
                Text(item.listPriceCNY.cny)
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.secondary)
            }
            .width(min: 78, ideal: 88)

            TableColumn("库龄") { item in
                if item.isOverdue {
                    Badge(text: "\(item.ageInDays) 天", tone: .danger, style: .filled)
                } else {
                    Text("\(item.ageInDays) 天")
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.secondary)
                }
            }
            .width(min: 54, ideal: 64)

            if statusFilter == nil {
                TableColumn("状态", value: \.statusRaw) { item in
                    Badge(
                        text: item.status.label,
                        tone: item.status.tone,
                        style: item.status == .inStock ? .outline : .filled
                    )
                }
                .width(min: 58, ideal: 68)
            }
        } rows: {
            ForEach(rows) { item in
                TableRow(item)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .searchable(text: $searchText, isPresented: $searchPresented, prompt: "序列号 / 型号 / 客户")
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