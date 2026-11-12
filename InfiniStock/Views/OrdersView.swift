import SwiftUI
import SwiftData

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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Table(filtered, selection: $selection) {
                TableColumn("单号") { order in
                    Text(order.number)
                        .monospaced()
                        .foregroundStyle(order.isVoided ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                }
                .width(min: 120, ideal: 140)

                TableColumn("日期") { order in
                    Text(order.createdAt.formatted(date: .numeric, time: .shortened))
                        .font(.caption)
                }
                .width(min: 110, ideal: 130)

                TableColumn("客户") { order in
                    Text(order.customerName.isEmpty ? "—" : order.customerName)
                }
                .width(min: 80, ideal: 110)

                TableColumn("联系方式") { order in
                    Text(order.customerContact.isEmpty ? "—" : order.customerContact)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 120)

                TableColumn("台数") { order in
                    Text("\(order.itemList.count)")
                        .monospacedDigit()
                }
                .width(min: 44, ideal: 50)

                TableColumn("应收") { order in
                    Text(order.totalCNY.cny).monospacedDigit()
                }
                .width(min: 90, ideal: 110)

                TableColumn("毛利") { order in
                    Text(order.profitCNY.cny)
                        .monospacedDigit()
                        .foregroundStyle(order.profitCNY < 0 ? Color.orange : Color.secondary)
                }
                .width(min: 80, ideal: 100)

                TableColumn("收款") { order in
                    Text(order.paymentMethod.rawValue)
                        .font(.caption)
                }
                .width(min: 52, ideal: 60)

                TableColumn("状态") { order in
                    Text(order.statusLabel)
                        .font(.caption)
                        .foregroundStyle(statusColor(order))
                }
                .width(min: 70, ideal: 80)
            }
            .searchable(text: $searchText, prompt: "单号 / 客户 / 序列号")
            .contextMenu(forSelectionType: PersistentIdentifier.self) { selected in
                if let order = selectedOrder(selected), !order.isVoided {
                    Button("查看凭证…") { receiptOrder = order }
                }
            }
        }
        .navigationTitle("单据")
        .sheet(item: $receiptOrder) { order in
            ReceiptSheet(order: order)
        }
    }

    @State private var receiptOrder: Order?

    private func selectedOrder(_ ids: Set<PersistentIdentifier>) -> Order? {
        guard let id = ids.first else { return nil }
        return orders.first { $0.id == id }
    }

    private func statusColor(_ order: Order) -> Color {
        if order.isFullyReturned { return .red }
        if order.isVoided { return .secondary }
        if order.hasReturns { return .orange }
        return .primary
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