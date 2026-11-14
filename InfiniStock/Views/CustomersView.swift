import SwiftUI
import SwiftData

/// 客户页的结论层：多少人在买、买了多少。
struct CustomersKpiStrip: View {
    @Query private var orders: [Order]

    private var customers: [CustomerSummary] {
        CustomerSummary.build(from: orders)
    }

    private var revenue: Decimal {
        customers.reduce(Decimal(0)) { $0 + $1.revenue }
    }

    private var averageOrder: Decimal {
        let count = customers.reduce(0) { $0 + $1.orderCount }
        guard count > 0 else { return 0 }
        return (revenue / Decimal(count)).rounded(0)
    }

    private var repeatRate: String {
        guard !customers.isEmpty else { return "暂无客户" }
        let repeaters = customers.filter { $0.orderCount > 1 }.count
        return String(localized: "复购 \((Decimal(repeaters) / Decimal(customers.count) * 100).rounded(0))%")
    }

    var body: some View {
        HStack(spacing: Token.Space.m) {
            StatCard(
                title: "客户数",
                value: String(localized: "\(customers.count) 位"),
                systemImage: "person.2.fill",
                tone: .brand,
                delta: repeatRate
            )
            StatCard(
                title: "累计消费",
                value: revenue.mmk,
                systemImage: "creditcard.fill",
                tone: .ok,
                delta: String(localized: "\(customers.reduce(0) { $0 + $1.machineCount }) 台")
            )
            StatCard(
                title: "平均客单价",
                value: averageOrder.mmk,
                systemImage: "chart.bar.fill",
                tone: .neutral,
                delta: "按单据均摊"
            )
        }
    }
}

/// 客户列表。客户不是实体，由有效单据按「姓名 + 电话」聚合而来。
struct CustomersView: View {
    @Binding var selection: String?
    @Binding var searchPresented: Bool
    /// 空状态里的「去库存开单」
    var onOpenStock: () -> Void = {}
    @State private var searchText = ""

    @Query(sort: \Order.createdAt, order: .reverse) private var orders: [Order]

    private var customers: [CustomerSummary] {
        let all = CustomerSummary.build(from: orders)
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.contact.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar {
                SearchField(text: $searchText, prompt: "姓名 / 电话", focusRequest: $searchPresented)
                Spacer(minLength: Token.Space.s)
                Text("由有效单据汇总")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
            }

            table

            TableFooter(leading: String(localized: "共 \(customers.count) 位"), trailing: footerTrailing)
        }
    }

    private var table: some View {
        Table(customers, selection: $selection) {
            TableColumn("客户") { customer in
                CellTitle(
                    title: customer.name,
                    subtitle: customer.contact.isEmpty ? "未留联系方式" : customer.contact,
                    monospacedSubtitle: false
                )
            }
            .width(min: 118, ideal: 140)

            TableColumn("购买次数") { customer in
                Text(String(localized: "\(customer.orderCount) 次"))
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.secondary)
            }
            .width(min: 56, ideal: 62)

            TableColumn("累计消费") { customer in
                VStack(alignment: .leading, spacing: 1) {
                    Text(customer.revenue.mmk)
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.primary)
                    if customer.outstanding > 0 {
                        Text(String(localized: "欠 \(customer.outstanding.mmk)"))
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Status.warn)
                    }
                }
            }
            .width(min: 88, ideal: 100)

            TableColumn("最近购买型号") { customer in
                Text(customer.lastModel.isEmpty ? "—" : customer.lastModel)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
            }
            .width(min: 96, ideal: 116)

            TableColumn("上次购买") { customer in
                VStack(alignment: .leading, spacing: 1) {
                    Text(customer.lastPurchase.formatted(date: .numeric, time: .omitted))
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                    Text(customer.daysSinceLastPurchase == 0 ? "今天" : String(localized: "\(customer.daysSinceLastPurchase) 天前"))
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.tertiary)
                }
            }
            .width(min: 74, ideal: 84)

            TableColumn("等级") { customer in
                Badge(
                    text: customer.tier.rawValue,
                    tone: tone(for: customer.tier),
                    style: customer.tier == .dormant ? .outline : .filled
                )
            }
            .width(min: 50, ideal: 58)

            // 末尾空列吸收多余宽度，避免最后一列被拉满整张卡
            TableColumn("") { _ in EmptyView() }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .overlay {
            if customers.isEmpty {
                EmptyState(
                    title: searchText.isEmpty ? "还没有客户" : "没有匹配结果",
                    message: searchText.isEmpty ? "开单时填上客户姓名与电话，这里会自动汇总" : "换个姓名或电话试试",
                    systemImage: "person.2",
                    actionTitle: searchText.isEmpty ? "去库存开单" : nil,
                    action: searchText.isEmpty ? onOpenStock : nil
                )
            }
        }
    }

    private func tone(for tier: CustomerTier) -> Tone {
        switch tier {
        case .vip: .brand
        case .active: .ok
        case .potential: .warn
        case .dormant: .neutral
        }
    }

    private var footerTrailing: String? {
        guard let selection, let customer = customers.first(where: { $0.id == selection }) else { return nil }
        return "\(customer.name) · 累计 \(customer.revenue.mmk)"
    }
}

/// 客户详情：由该客户的单据聚合而来。
struct CustomerDetailView: View {
    let customer: CustomerSummary
    let orders: [Order]

    private var customerOrders: [Order] {
        orders.filter {
            !$0.isVoided
                && $0.customerName.trimmingCharacters(in: .whitespaces) == customer.name
                && $0.customerContact.trimmingCharacters(in: .whitespaces) == customer.contact
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "客户详情", subtitle: customer.contact.isEmpty ? customer.name : customer.contact)

            ScrollView {
                VStack(spacing: 0) {
                    PanelSection(title: "客户") {
                        KeyValueRow(label: "姓名", value: customer.name)
                        KeyValueRow(label: "电话", value: customer.contact)
                        KeyValueRow(label: "等级", value: customer.tier.rawValue)
                        KeyValueRow(label: "最近型号", value: customer.lastModel)
                        KeyValueRow(label: "最近购买", value: customer.lastPurchase.compactStamp)
                    }

                    PanelSection(title: "消费统计") {
                        KeyValueRow(label: "累计消费", value: customer.revenue.mmk)
                        if customer.outstanding > 0 {
                            KeyValueRow(label: "欠款", value: customer.outstanding.mmk, valueTone: .warn)
                        }
                        KeyValueRow(
                            label: "累计毛利",
                            value: customer.profit.signedMMK,
                            valueTone: customer.profit < 0 ? .danger : .ok
                        )
                        KeyValueRow(label: "毛利率", value: customer.marginRate.map { "\(Money.text($0))%" } ?? "—")
                        KeyValueRow(label: "单据数", value: String(localized: "\(customer.orderCount) 张"))
                        KeyValueRow(label: "台数", value: String(localized: "\(customer.machineCount) 台"))
                    }

                    PanelSection(title: "历史单据", trailing: String(localized: "\(customerOrders.count) 张")) {
                        ForEach(customerOrders) { order in
                            HStack(spacing: Token.Space.s) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(order.number)
                                        .font(Token.Typography.cellPrimary)
                                        .foregroundStyle(Token.Ink.primary)
                                        .monospaced()
                                    Text(order.createdAt.compactStamp)
                                        .font(Token.Typography.caption)
                                        .foregroundStyle(Token.Ink.tertiary)
                                }
                                Spacer()
                                Text(order.total.mmk)
                                    .font(Token.Typography.money)
                                    .foregroundStyle(Token.Ink.primary)
                                Badge(text: order.statusLabel, tone: order.tone, style: .filled)
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