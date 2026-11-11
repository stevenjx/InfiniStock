import SwiftUI
import SwiftData

struct DashboardView: View {
    let cloudSyncEnabled: Bool
    @Query private var items: [Item]
    @Query private var orders: [Order]

    @State private var showingDataSafety = false

    private var stats: InventoryStatistics {
        InventoryStatistics(items: items, orders: orders)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SyncNotice(cloudSyncEnabled: cloudSyncEnabled)

                if BackupService.backupFolder() == nil {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("自动备份未启用，数据仅存本机。点右上角「数据安全」设置备份目录。")
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    StatCard(title: "在库台数", value: "\(stats.inStockCount)", unit: "台")
                    StatCard(title: "库存总值（成本）", value: stats.stockCostValue.cny, unit: nil)
                    StatCard(title: "今日销售额", value: stats.todayRevenue.cny, unit: nil)
                    StatCard(title: "今日毛利", value: stats.todayProfit.cny, unit: nil)
                }

                HStack(spacing: 16) {
                    Label(
                        stats.todayMarginRate.map { "今日毛利率 \(Money.text($0))%" } ?? "今日暂无成交",
                        systemImage: "percent"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Label("库存潜在毛利 \(stats.stockPotentialProfit.cny)", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                agingSection
                overdueSection
            }
            .padding(16)
        }
        .navigationTitle("统计")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingDataSafety = true
                } label: {
                    Label("数据安全", systemImage: "externaldrive.badge.checkmark")
                }
            }
        }
        .sheet(isPresented: $showingDataSafety) {
            NavigationStack { DataSafetyView() }
                .frame(minWidth: 560, minHeight: 600)
        }
    }

    private var agingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("库龄分布").font(.headline)
            let maximum = stats.agingBuckets.map(\.count).max() ?? 0
            ForEach(stats.agingBuckets) { bucket in
                HStack(spacing: 10) {
                    Text(bucket.label)
                        .font(.caption)
                        .frame(width: 70, alignment: .leading)
                    Capsule()
                        .fill(bucketColor(bucket.label))
                        .frame(width: maximum == 0 ? 2 : max(3, 200 * CGFloat(bucket.count) / CGFloat(maximum)), height: 8)
                    Text("\(bucket.count) 台")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(bucket.value.cny)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var overdueSection: some View {
        if !stats.overdueItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("呆滞品").font(.headline)
                    Text("超过 \(Item.overdueDays) 天 · 占用成本 \(stats.overdueValue.cny)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                ForEach(stats.overdueItems.prefix(8)) { item in
                    HStack {
                        Text(item.modelName)
                        Text(item.serialNumber)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(item.ageInDays) 天")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.red)
                        Text(item.landedCostCNY.cny)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                if stats.overdueItems.count > 8 {
                    Text("另有 \(stats.overdueItems.count - 8) 台未列出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func bucketColor(_ label: String) -> Color {
        switch label {
        case "0-30 天": .accentColor
        case "31-60 天": .blue.opacity(0.7)
        case "61-90 天": .orange
        default: .red
        }
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
