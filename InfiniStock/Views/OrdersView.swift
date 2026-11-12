import SwiftUI
import SwiftData

/// 单据列表。行内用双行单元格展示单号与客户，状态走语义徽章。
struct OrdersView: View {
    @Binding var selection: PersistentIdentifier?

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
            Picker("筛选", selection: $statusFilter) {
                ForEach(OrderStatusFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Token.Space.m)
            .padding(.vertical, Token.Space.s)

            Table(filtered, selection: $selection) {
                TableColumn("单号") { order in
                    CellTitle(
                        title: order.number,
                        subtitle: order.customerName.isEmpty ? "散客" : order.customerName
                    )
                }
                .width(min: 150, ideal: 180)

                TableColumn("日期") { order in
                    Text(order.createdAt.formatted(date: .numeric, time: .shortened))
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
                .width(min: 118, ideal: 138)

                TableColumn("台数") { order in
                    Text("\(order.itemList.count)")
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.primary)
                }
                .width(min: 44, ideal: 52)

                TableColumn("应收") { order in
                    Text(order.totalCNY.cny)
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.primary)
                }
                .width(min: 90, ideal: 104)

                TableColumn("毛利") { order in
                    Text(order.profitCNY.signedCNY)
                        .font(Token.Typography.money)
                        .foregroundStyle(order.profitCNY < 0 ? Token.Status.danger : Token.Status.ok)
                }
                .width(min: 86, ideal: 98)

                TableColumn("收款") { order in
                    Text(order.paymentMethod.rawValue)
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
                .width(min: 50, ideal: 58)

                TableColumn("状态") { order in
                    Badge(
                        text: order.statusLabel,
                        tone: order.tone,
                        style: order.isVoided ? .filled : .outline
                    )
                }
                .width(min: 74, ideal: 84)
            }
            .searchable(text: $searchText, prompt: "单号 / 客户 / 序列号")
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
        }
        .navigationTitle("单据")
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