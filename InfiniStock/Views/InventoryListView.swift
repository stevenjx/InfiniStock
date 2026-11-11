import SwiftUI
import SwiftData

struct InventoryListView: View {
    @Binding var selection: Item?
    @Query(sort: \Item.inboundAt, order: .reverse) private var items: [Item]

    @State private var statusFilter: ItemStatus? = .inStock
    @State private var searchText = ""
    @State private var showingIntake = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("筛选", selection: $statusFilter) {
                Text("在库").tag(ItemStatus.inStock as ItemStatus?)
                Text("已售").tag(ItemStatus.sold as ItemStatus?)
                Text("全部").tag(nil as ItemStatus?)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            listContent
        }
        .navigationTitle("库存")
        .searchable(text: $searchText, prompt: "序列号 / 型号")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingIntake = true
                } label: {
                    Label("入库", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingIntake) {
            IntakeSheet()
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView(
                "没有机器",
                systemImage: "shippingbox",
                description: Text("点右上角 + 录入第一台")
            )
        } else {
            #if os(macOS)
            List(selection: $selection) {
                ForEach(filteredItems) { item in
                    ItemRow(item: item)
                        .tag(Optional(item))
                }
            }
            #else
            List {
                ForEach(filteredItems) { item in
                    NavigationLink {
                        ItemDetailView(item: item)
                    } label: {
                        ItemRow(item: item)
                    }
                }
            }
            #endif
        }
    }

    private var filteredItems: [Item] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        return items.filter { item in
            let statusOK = statusFilter == nil || item.status == statusFilter
            guard statusOK else { return false }
            guard !keyword.isEmpty else { return true }
            return item.serialNumber.localizedCaseInsensitiveContains(keyword)
                || item.modelName.localizedCaseInsensitiveContains(keyword)
        }
    }
}

struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.modelName.isEmpty ? "未命名型号" : item.modelName)
                Text(item.serialNumber)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
                if !item.specSummary.isEmpty {
                    Text(item.specSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.status == .sold ? item.soldPriceCNY.cny : item.listPriceCNY.cny)
                    .font(.callout)
                Text(item.status.label)
                    .font(.caption2)
                    .foregroundStyle(item.status == .sold ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            }
        }
        .padding(.vertical, 2)
    }
}
