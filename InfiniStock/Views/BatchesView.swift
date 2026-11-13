import SwiftUI
import SwiftData

/// 采购页的结论层：本批进了多少、压了多少钱。
struct BatchesKpiStrip: View {
    @Query private var batches: [Batch]

    private var monthBatches: [Batch] {
        batches.filter { Calendar.current.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }
    }

    private var totalCost: Decimal {
        batches.reduce(Decimal(0)) { $0 + $1.totalCost }
    }

    private var totalShipping: Decimal {
        batches.reduce(Decimal(0)) { $0 + $1.totalShipping }
    }

    private var machineCount: Int {
        batches.reduce(0) { $0 + $1.itemList.count }
    }

    var body: some View {
        HStack(spacing: Token.Space.m) {
            StatCard(
                title: "本月批次",
                value: "\(monthBatches.count) 批",
                systemImage: "shippingbox.and.arrow.backward",
                tone: .brand,
                delta: "累计 \(batches.count) 批"
            )
            StatCard(
                title: "总进价合计",
                value: totalCost.mmk,
                systemImage: "banknote.fill",
                tone: .warn,
                delta: "\(machineCount) 台"
            )
            StatCard(
                title: "运费合计",
                value: totalShipping.mmk,
                systemImage: "truck.box.fill",
                tone: .neutral,
                delta: machineCount > 0 ? "均摊每台 \((totalShipping / Decimal(machineCount)).rounded(0).mmk)" : "暂无机器"
            )
        }
    }
}

/// 批次列表。模型一直存在，此前没有页面可看，现在补上。
struct BatchesView: View {
    @Binding var selection: PersistentIdentifier?
    @Binding var searchPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var showingNewBatch = false

    @Query(sort: \Batch.createdAt, order: .reverse) private var batches: [Batch]

    var body: some View {
        VStack(spacing: 0) {
            FilterBar {
                SearchField(text: $searchText, prompt: "批次 / 供应商", focusRequest: $searchPresented)
                Spacer(minLength: Token.Space.s)
                Button {
                    showingNewBatch = true
                } label: {
                    Label("新建批次", systemImage: "plus")
                        .font(Token.Typography.caption)
                }
                .buttonStyle(.borderless)
            }

            table

            TableFooter(leading: "共 \(filtered.count) 批", trailing: footerTrailing)
        }
        .sheet(isPresented: $showingNewBatch) {
            BatchSheet()
        }
    }

    private var table: some View {
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
                Text(batch.totalShipping.mmk)
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 74, ideal: 84)

            TableColumn("总进价合计") { batch in
                Text(batch.totalCost.mmk)
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 92, ideal: 104)

            TableColumn("状态") { batch in
                Badge(
                    text: batch.stage.rawValue,
                    tone: tone(for: batch.stage),
                    style: batch.stage == .settled ? .filled : .outline
                )
            }
            .width(min: 56, ideal: 64)

            // 末尾空列吸收多余宽度，避免最后一列被拉满整张卡
            TableColumn("") { _ in EmptyView() }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .overlay {
            if filtered.isEmpty {
                EmptyState(
                    title: searchText.isEmpty ? "还没有批次" : "没有匹配结果",
                    message: searchText.isEmpty ? "同一批货的汇率与运费只填一次，逐台自动分摊" : "换个批次名试试",
                    systemImage: "shippingbox.and.arrow.backward",
                    actionTitle: searchText.isEmpty ? "新建批次" : nil,
                    action: searchText.isEmpty ? { showingNewBatch = true } : nil
                )
            }
        }
    }

    private func tone(for stage: BatchStage) -> Tone {
        switch stage {
        case .empty: .neutral
        case .pending: .warn
        case .settled: .ok
        }
    }

    private var footerTrailing: String? {
        guard let selection, let batch = batches.first(where: { $0.id == selection }) else { return nil }
        let cost = batch.itemList.reduce(Decimal(0)) { $0 + $1.landedCost }
        return "\(batch.name) · 成本 \(cost.mmk)"
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
        VStack(spacing: 0) {
            PanelHeader(title: "批次详情", subtitle: batch.name)

            ScrollView {
                VStack(spacing: 0) {
                    PanelSection(title: "批次") {
                        KeyValueRow(label: "名称", value: batch.name)
                        KeyValueRow(label: "供应商", value: batch.supplier)
                        KeyValueRow(label: "创建", value: batch.createdAt.compactStamp)
                        KeyValueRow(label: "分摊方式", value: batch.allocation.rawValue)
                    }

                    PanelSection(title: "成本口径") {
                        KeyValueRow(label: "锁定汇率", value: "1 元 = \(Money.text(batch.exchangeRate)) 缅币")
                        KeyValueRow(label: "总运费", value: batch.totalShipping.mmk)
                        KeyValueRow(label: "已分摊", value: batch.allocatedShipping.mmk)
                        KeyValueRow(
                            label: "状态",
                            value: batch.stage.rawValue,
                            valueTone: batch.stage == .pending ? .warn : nil
                        )
                        KeyValueRow(
                            label: "成本合计",
                            value: items.reduce(Decimal(0)) { $0 + $1.landedCost }.mmk
                        )
                    }

                    PanelSection(title: "机器", trailing: "\(items.count) 台") {
                        if items.isEmpty {
                            Text("这一批还没有机器")
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.secondary)
                        }
                        ForEach(items) { item in
                            HStack(spacing: Token.Space.s) {
                                CellTitle(title: item.modelName, subtitle: item.serialNumber)
                                Spacer()
                                Text(item.landedCost.mmk)
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
            }
        }
        .background(Token.Surface.card)
    }
}
