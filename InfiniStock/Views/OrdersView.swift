import SwiftUI
import SwiftData

/// 销售页顶部的结论层：先回答"今天卖了多少"，再给明细。
/// 口径与仪表盘同源（都以有效单据为准），避免两个页面报不同数字。
struct OrdersKpiStrip: View {
    @Query private var orders: [Order]
    @Query private var items: [Item]

    private var todayOrders: [Order] {
        orders.filter { !$0.isVoided && Calendar.current.isDateInToday($0.createdAt) }
    }

    private var revenue: Decimal {
        todayOrders.reduce(Decimal(0)) { $0 + $1.total }
    }

    private var profit: Decimal {
        todayOrders.reduce(Decimal(0)) { $0 + $1.profit }
    }

    private var soldCount: Int {
        todayOrders.reduce(0) { $0 + $1.itemList.count }
    }

    private var marginText: String {
        guard revenue > 0 else { return "暂无成交" }
        return String(localized: "毛利率 \((profit / revenue * 100).rounded(1))%")
    }

    var body: some View {
        HStack(spacing: Token.Space.m) {
            StatCard(
                title: "今日销售额",
                value: revenue.mmk,
                systemImage: "cart.fill",
                tone: .brand,
                delta: String(localized: "\(todayOrders.count) 张单")
            )
            StatCard(
                title: "今日毛利",
                value: profit.signedMMK,
                systemImage: "chart.line.uptrend.xyaxis",
                tone: profit < 0 ? .danger : .ok,
                delta: marginText,
                deltaTone: profit < 0 ? .danger : .ok
            )
            StatCard(
                title: "今日已售",
                value: String(localized: "\(soldCount) 台"),
                systemImage: "shippingbox.fill",
                tone: .neutral,
                delta: String(localized: "在库 \(items.filter { $0.status == .inStock }.count) 台")
            )
        }
    }
}

/// 单据列表。工具条与库存页同构，行内用双行单元格展示单号与客户。
struct OrdersView: View {
    @Binding var selection: PersistentIdentifier?
    @Binding var searchPresented: Bool
    /// 空状态里的「去库存开单」
    var onOpenStock: () -> Void = {}

    @Query(sort: \Order.createdAt, order: .reverse) private var orders: [Order]

    @State private var searchText = ""
    @State private var statusFilter: OrderStatusFilter = .all

    enum OrderStatusFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "有效"
        case returned = "有退货"
        case voided = "已作废"

        var id: String { rawValue }

        /// rawValue 是中文枚举值，用作匹配键；显示走本地化
        var title: LocalizedStringResource {
            switch self {
            case .all: "全部"
            case .active: "有效"
            case .returned: "有退货"
            case .voided: "已作废"
            }
        }

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
                            + String(localized: " · \(order.itemList.count) 台")
                    )
                    .padding(.vertical, 8)
                }
                .width(min: 130, ideal: 160)

                TableColumn("日期") { order in
                    Text(order.createdAt.compactStamp)
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
                .width(min: 92, ideal: 104)

                TableColumn("应收") { order in
                    Text(order.total.mmk)
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 82, ideal: 92)

                TableColumn("毛利") { order in
                    Text(order.profit.signedMMK)
                        .font(Token.Typography.money)
                        .foregroundStyle(order.profit < 0 ? Token.Status.danger : Token.Status.ok)
                        .frame(maxWidth: .infinity, alignment: .trailing)
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

                // 末尾空列吸收多余宽度，避免最后一列被拉满整张卡
                TableColumn("") { _ in EmptyView() }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .overlay {
                if filtered.isEmpty {
                    EmptyState(
                        title: searchText.isEmpty ? "还没有单据" : "没有匹配结果",
                        message: searchText.isEmpty ? "在库存页选中机器点「出库销售」，单据自动生成" : "换个单号或客户名试试",
                        systemImage: "doc.text",
                        actionTitle: searchText.isEmpty ? "去库存开单" : nil,
                        action: searchText.isEmpty ? onOpenStock : nil
                    )
                }
            }

            TableFooter(leading: footerLeading, trailing: footerTrailing)
        }
    }

    private var statusOptions: [PillOption<OrderStatusFilter>] {
        OrderStatusFilter.allCases.map { PillOption(value: $0, title: $0.title) }
    }

    private var footerLeading: String {
        String(localized: "共 \(filtered.count) 张")
    }

    private var footerTrailing: String? {
        guard let selection, let order = orders.first(where: { $0.id == selection }) else { return nil }
        return "\(order.number) · 应收 \(order.total.mmk)"
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
