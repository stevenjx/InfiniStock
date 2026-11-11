import AppKit
import SwiftUI
import SwiftData

/// 库存主表。用 Table 而不是 List：macOS 用户预期列可排序、可拖宽。
struct InventoryTableView: View {
    let statusFilter: ItemStatus?
    @Binding var selection: Set<PersistentIdentifier>
    @Binding var searchPresented: Bool

    @Query(sort: \Item.inboundAt, order: .reverse) private var items: [Item]
    @State private var sortOrder: [KeyPathComparator<Item>] = [KeyPathComparator(\Item.inboundAt, order: .reverse)]
    @State private var searchText = ""

    var body: some View {
        Table(of: Item.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("型号", value: \.modelName) { item in
                Text(item.modelName).lineLimit(1)
            }
            .width(min: 130, ideal: 160)

            TableColumn("序列号", value: \.serialNumber) { item in
                Text(item.serialNumber).monospaced().lineLimit(1)
            }
            .width(min: 115, ideal: 140)

            TableColumn("规格") { item in
                Text(item.memory.isEmpty || item.storage.isEmpty ? "—" : "\(item.memory) \(item.storage)")
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 110)

            TableColumn("落地成本", value: \.landedCostCNY) { item in
                Text(item.landedCostCNY.cny).monospacedDigit()
            }
            .width(min: 90, ideal: 100)

            TableColumn("标价", value: \.listPriceCNY) { item in
                Text(item.listPriceCNY.cny).monospacedDigit()
            }
            .width(min: 90, ideal: 100)

            TableColumn("库龄") { item in
                Text("\(item.ageInDays) 天")
                    .monospacedDigit()
                    .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
            }
            .width(min: 60, ideal: 70)

            TableColumn("状态", value: \.statusRaw) { item in
                Text(item.status.label)
                    .foregroundStyle(item.status == .inStock ? Color.primary : Color.secondary)
            }
            .width(min: 50, ideal: 60)
        } rows: {
            ForEach(rows) { item in
                TableRow(item)
            }
        }
        .searchable(text: $searchText, isPresented: $searchPresented, prompt: "序列号 / 型号")
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
    }

    private var rows: [Item] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = items.filter { item in
            let statusOK = statusFilter == nil || item.status == statusFilter
            guard statusOK else { return false }
            guard !keyword.isEmpty else { return true }
            return item.serialNumber.localizedCaseInsensitiveContains(keyword)
                || item.modelName.localizedCaseInsensitiveContains(keyword)
        }
        return filtered.sorted(using: sortOrder)
    }
}
