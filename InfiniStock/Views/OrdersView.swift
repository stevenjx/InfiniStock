import SwiftUI
import SwiftData

/// 单据列表。工具条与库存页同构，行内用双行单元格展示单号与客户。
struct OrdersView: View {
    @Binding var selection: PersistentIdentifier?
    @Binding var searchPresented: Bool

    @Query(sort: \Order.createdAt, order: .reverse) private var orders: [Order]

    @State private var searchText = ""
    @State private var statusFilter: OrderStatusFilter = .all

    enum OrderStatusFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "有效"
        case returned = "有退货"
        case voided = "已作废"

        var id: String { rawValue }

        func matches(_ order: Order) -> Bool {
            switch self {
            case .all: true
            case .active: !order.isVoided
            case .returned: order.hasReturns
            case .voided: order.isVoided
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar {
                SearchField(text: $searchText, prompt: "单号 / 客户 / 序列号", focusRequest: $searchPresented)

                FilterPillGroup(label: "状态", options: statusOptions, selection: statusFilter) { filter in
                    statusFilter = filter
                }

                Spacer(minLength: Token.Space.s)
                Text("按日期倒序")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
            }

            Table(filtered, selection: $selection) {
                TableColumn("单号") { order in
                    CellTitle(
                        title: order.number,
                        subtitle: (order.customerName.isEmpty ? "散客" : order.customerName)
                            + " · \(order.itemList.count) 台"
                    )
                    .padding(.vertical, 6)
                }
                .width(min: 130, ideal: 160)

                TableColumn("日期") { order in
                    Text(order.createdAt.compactStamp)
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
                .width(min: 92, ideal: 104)

                TableColumn("应收") { order in
                    Text(order.totalCNY.cny)
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.primary)
                }
                .width(min: 82, ideal: 92)

                TableColumn("毛利") { order in
                    Text(order.profitCNY.signedCNY)
                        .font(Token.Typography.money)
                        .foregroundStyle(order.profitCNY < 0 ? Token.Status.danger : Token.Status.ok)
                }
                .width(min: 76, ideal: 86)

                TableColumn("状态") { order in
                    Badge(
                        text: order.statusLabel,
                        tone: order.tone,
                        style: order.isVoided ? .filled : .outline
                    )
                }
                .width(min: 62, ideal: 70)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .overlay {
                if filtered.isEmpty {
                    EmptyState(
                        title: searchText.isEmpty ? "还没有单据" : "没有匹配结果",
                        message: searchText.isEmpty ? "出库销售后自动生成单据" : "换个单号或客户名试试",
                        systemImage: "doc.text"
                    )
                    .allowsHitTesting(false)
                }
            }

            TableFooter(leading: footerLeading, trailing: footerTrailing)
        }
    }

    private var statusOptions: [PillOption<OrderStatusFilter>] {
        OrderStatusFilter.allCases.map { PillOption(value: $0, title: $0.rawValue) }
    }

    private var footerLeading: String {
        "共 \(filtered.count) 张"
    }

    private var footerTrailing: String? {
        guard let selection, let order = orders.first(where: { $0.id == selection }) else { return nil }
        return "\(order.number) · 应收 \(order.totalCNY.cny)"
    }

    private var filtered: [Order] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        return orders.filter { order in
            guard statusFilter.matches(order) else { return false }
            guard !keyword.isEmpty else { return true }
            if order.number.localizedCaseInsensitiveContains(keyword) { return true }
            if order.customerName.localizedCaseInsensitiveContains(keyword) { return true }
            if order.customerContact.localizedCaseInsensitiveContains(keyword) { return true }
            return order.itemList.contains { $0.serialNumber.localizedCaseInsensitiveContains(keyword) }
        }
    }
}
