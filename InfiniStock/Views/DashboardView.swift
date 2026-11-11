import SwiftUI
import SwiftData

struct DashboardView: View {
    let cloudSyncEnabled: Bool
    @Query(sort: \Item.soldAt, order: .reverse) private var items: [Item]

    private var inStockItems: [Item] {
        items.filter { $0.status == .inStock }
    }

    private var soldToday: [Item] {
        items.filter { item in
            guard item.status == .sold, let soldAt = item.soldAt else { return false }
            return Calendar.current.isDateInToday(soldAt)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SyncNotice(cloudSyncEnabled: cloudSyncEnabled)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    StatCard(title: "在库台数", value: "\(inStockItems.count)", unit: "台")
                    StatCard(title: "库存总值", value: inStockTotal.cny, unit: nil)
                    StatCard(title: "今日销售额", value: todayRevenue.cny, unit: nil)
                    StatCard(title: "今日毛利", value: todayProfit.cny, unit: nil)
                }

                if !soldToday.isEmpty {
                    Text("今日成交")
                        .font(.headline)
                    VStack(spacing: 0) {
                        ForEach(soldToday) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.modelName)
                                    Text(item.serialNumber)
                                        .font(.caption)
                                        .monospaced()
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(item.soldPriceCNY.cny)
                                    Text(item.grossProfitCNY.cny)
                                        .font(.caption)
                                        .foregroundStyle(item.grossProfitCNY < 0 ? Color.orange : Color.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                            if item.id != soldToday.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("统计")
    }

    private var inStockTotal: Decimal {
        inStockItems.reduce(0) { $0 + $1.landedCostCNY }
    }

    private var todayRevenue: Decimal {
        soldToday.reduce(0) { $0 + $1.soldPriceCNY }
    }

    private var todayProfit: Decimal {
        soldToday.reduce(0) { $0 + $1.grossProfitCNY }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
    }
}
