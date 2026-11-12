import SwiftUI
import SwiftData

/// 客户列表。客户不是实体，由有效单据按「姓名 + 电话」聚合而来。
struct CustomersView: View {
    @Binding var selection: String?
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
        VStack(alignment: .leading, spacing: 0) {
            Table(customers, selection: $selection) {
                TableColumn("客户") { customer in
                    CellTitle(
                        title: customer.name,
                        subtitle: customer.contact.isEmpty ? "未留联系方式" : customer.contact,
                        monospacedSubtitle: false
                    )
                }
                .width(min: 128, ideal: 156)

                TableColumn("单据") { customer in
                    Text("\(customer.orderCount) 张")
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.secondary)
                }
                .width(min: 50, ideal: 56)

                TableColumn("台数") { customer in
                    Text("\(customer.machineCount)")
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.primary)
                }
                .width(min: 36, ideal: 40)

                TableColumn("累计消费") { customer in
                    Text(customer.revenue.cny)
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.primary)
                }
                .width(min: 84, ideal: 94)

                TableColumn("累计毛利") { customer in
                    Text(customer.profit.signedCNY)
                        .font(Token.Typography.money)
                        .foregroundStyle(customer.profit < 0 ? Token.Status.danger : Token.Status.ok)
                }
                .width(min: 78, ideal: 88)

                TableColumn("最近购买") { customer in
                    Text(customer.lastPurchase.formatted(date: .numeric, time: .omitted))
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
                .width(min: 78, ideal: 88)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .searchable(text: $searchText, prompt: "姓名 / 电话")
        }
        .navigationTitle("客户")
        .overlay {
            if customers.isEmpty {
                EmptyState(
                    title: searchText.isEmpty ? "还没有客户" : "没有匹配结果",
                    message: searchText.isEmpty ? "开单时填上客户姓名，这里会自动汇总" : "换个姓名或电话试试",
                    systemImage: "person.2"
                )
                .allowsHitTesting(false)
            }
        }
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
        ScrollView {
            VStack(spacing: Token.Space.m) {
                SectionCard(title: "客户") {
                    KeyValueRow(label: "姓名", value: customer.name)
                    KeyValueRow(label: "电话", value: customer.contact)
                    KeyValueRow(label: "最近购买", value: customer.lastPurchase.formatted(date: .numeric, time: .shortened))
                }

                SectionCard(title: "消费统计") {
                    KeyValueRow(label: "累计消费", value: customer.revenue.cny)
                    KeyValueRow(
                        label: "累计毛利",
                        value: customer.profit.signedCNY,
                        valueTone: customer.profit < 0 ? .danger : .ok
                    )
                    KeyValueRow(label: "毛利率", value: customer.marginRate.map { "\(Money.text($0))%" } ?? "—")
                    KeyValueRow(label: "单据数", value: "\(customer.orderCount) 张")
                    KeyValueRow(label: "台数", value: "\(customer.machineCount) 台")
                }

                SectionCard(title: "历史单据") {
                    ForEach(customerOrders) { order in
                        HStack(spacing: Token.Space.s) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(order.number)
                                    .font(Token.Typography.cellPrimary)
                                    .foregroundStyle(Token.Ink.primary)
                                    .monospaced()
                                Text(order.createdAt.formatted(date: .numeric, time: .shortened))
                                    .font(Token.Typography.caption)
                                    .foregroundStyle(Token.Ink.tertiary)
                            }
                            Spacer()
                            Text(order.totalCNY.cny)
                                .font(Token.Typography.money)
                                .foregroundStyle(Token.Ink.primary)
                            Badge(text: order.statusLabel, tone: order.tone, style: .filled)
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