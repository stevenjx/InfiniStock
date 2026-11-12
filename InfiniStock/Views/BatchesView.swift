import SwiftUI
import SwiftData

/// 批次列表。模型一直存在，此前没有页面可看，现在补上。
struct BatchesView: View {
    @Binding var selection: PersistentIdentifier?
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var showingNewBatch = false

    @Query(sort: \Batch.createdAt, order: .reverse) private var batches: [Batch]

    var body: some View {
        Table(filtered, selection: $selection) {
            TableColumn("批次") { batch in
                CellTitle(
                    title: batch.name.isEmpty ? "未命名批次" : batch.name,
                    subtitle: batch.supplier.isEmpty ? "无供应商" : batch.supplier
                )
            }
            .width(min: 130, ideal: 160)

            TableColumn("台数") { batch in
                Text("\(batch.itemList.count)")
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.primary)
            }
            .width(min: 38, ideal: 44)

            TableColumn("锁定汇率") { batch in
                Text(Money.text(batch.exchangeRate))
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.secondary)
            }
            .width(min: 66, ideal: 76)

            TableColumn("总运费") { batch in
                Text(batch.totalShippingCNY.cny)
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.secondary)
            }
            .width(min: 74, ideal: 84)

            TableColumn("落地成本合计") { batch in
                Text(batch.itemList.reduce(Decimal(0)) { $0 + $1.landedCostCNY }.cny)
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.primary)
            }
            .width(min: 92, ideal: 104)

        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
            .searchable(text: $searchText, prompt: "批次 / 供应商")
        .navigationTitle("批次")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewBatch = true
                } label: {
                    Label("新建批次", systemImage: "plus")
                }
            }
        }
        .overlay {
            if filtered.isEmpty {
                EmptyState(
                    title: searchText.isEmpty ? "还没有批次" : "没有匹配结果",
                    message: searchText.isEmpty ? "进货时建一个批次，汇率与运费一次锁定" : "换个批次名试试",
                    systemImage: "shippingbox.and.arrow.backward"
                )
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showingNewBatch) {
            BatchSheet()
        }
    }

    private var filtered: [Batch] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return batches }
        return batches.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.supplier.localizedCaseInsensitiveContains(keyword)
        }
    }
}
/// 批次详情：批次本身的信息 + 该批机器清单。
struct BatchDetailView: View {
    let batch: Batch

    private var items: [Item] {
        batch.itemList.sorted { $0.serialNumber < $1.serialNumber }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Token.Space.m) {
                SectionCard(title: "批次") {
                    KeyValueRow(label: "名称", value: batch.name)
                    KeyValueRow(label: "供应商", value: batch.supplier)
                    KeyValueRow(label: "创建", value: batch.createdAt.formatted(date: .numeric, time: .shortened))
                    KeyValueRow(label: "分摊方式", value: batch.allocation.rawValue)
                }

                SectionCard(title: "成本口径") {
                    KeyValueRow(label: "币种", value: batch.currency.rawValue)
                    KeyValueRow(label: "锁定汇率", value: Money.text(batch.exchangeRate))
                    KeyValueRow(label: "总运费", value: batch.totalShippingCNY.cny)
                    KeyValueRow(label: "已分摊", value: items.reduce(Decimal(0)) { $0 + $1.shippingCNY }.cny)
                    KeyValueRow(
                        label: "成本合计",
                        value: items.reduce(Decimal(0)) { $0 + $1.landedCostCNY }.cny
                    )
                }

                SectionCard(title: "机器（\(items.count) 台）") {
                    if items.isEmpty {
                        Text("这一批还没有机器")
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Ink.secondary)
                    }
                    ForEach(items) { item in
                        HStack(spacing: Token.Space.s) {
                            CellTitle(title: item.modelName, subtitle: item.serialNumber)
                            Spacer()
                            Text(item.landedCostCNY.cny)
                                .font(Token.Typography.money)
                                .foregroundStyle(Token.Ink.primary)
                            Badge(
                                text: item.status.label,
                                tone: item.status.tone,
                                style: item.status == .inStock ? .outline : .filled
                            )
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(Token.Space.l)
        }
        .background(Token.Surface.canvas)
    }
}
