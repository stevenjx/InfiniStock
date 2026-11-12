import SwiftUI
import Charts
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
            DashboardContent(
                stats: stats,
                cloudSyncEnabled: cloudSyncEnabled,
                backupConfigured: BackupService.backupFolder() != nil
            )
            .padding(Token.Space.l)
        }
        .background(Token.Surface.canvas)
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
}

/// 仪表盘内容，独立出来便于渲染验收。
struct DashboardContent: View {
    let stats: InventoryStatistics
    let cloudSyncEnabled: Bool
    let backupConfigured: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.m) {
            if !backupConfigured {
                AlertCard(
                    title: "自动备份未启用",
                    message: "数据仅存本机。点右上角「数据安全」选一个备份目录，之后每天首次启动会自动备份。",
                    tone: .warn
                )
            }

            kpiRow
            trendCard
            HStack(alignment: .top, spacing: Token.Space.m) {
                agingCard
                paymentCard
            }
            alertSection

            if !cloudSyncEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                    Text("本地模式：数据仅存本机，未启用云同步")
                        .font(Token.Typography.caption)
                    Spacer()
                }
                .foregroundStyle(Token.Ink.tertiary)
            }
        }
    }

    private var kpiRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 138), spacing: Token.Space.m)],
            spacing: Token.Space.m
        ) {
            StatCard(
                title: "今日销售额",
                value: stats.todayRevenue.mmk,
                systemImage: "cart.fill",
                tone: .brand,
                delta: dayOverDay(stats.todayRevenue, stats.yesterdayRevenue),
                deltaTone: stats.todayRevenue >= stats.yesterdayRevenue ? .ok : .danger
            )
            StatCard(
                title: "今日毛利",
                value: stats.todayProfit.signedMMK,
                systemImage: "chart.line.uptrend.xyaxis",
                tone: stats.todayProfit < 0 ? .danger : .ok,
                delta: stats.todayMarginRate.map { "毛利率 \(Money.text($0))%" } ?? "今日无成交",
                deltaTone: (stats.todayMarginRate ?? 0) < 0 ? .danger : .ok
            )
            StatCard(
                title: "在库台数",
                value: "\(stats.inStockCount) 台",
                systemImage: "shippingbox.fill",
                tone: .neutral,
                delta: stats.overdueItems.isEmpty ? "无呆滞" : "\(stats.overdueItems.count) 台超期",
                deltaTone: stats.overdueItems.isEmpty ? .neutral : .danger
            )
            StatCard(
                title: "库存总值",
                value: stats.stockCostValue.mmk,
                systemImage: "banknote.fill",
                tone: .warn,
                delta: "标价合计 \(stats.stockListedValue.mmk)"
            )
        }
    }

    private var trendCard: some View {
        let summary = stats.summary(days: 7)
        return SectionCard(title: "近 7 天销售额与毛利") {
            VStack(alignment: .leading, spacing: Token.Space.s) {
                HStack(spacing: Token.Space.l) {
                    Text("本周累计 销售额 \(summary.revenue.mmk) · 毛利 \(summary.profit.signedMMK)")
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                    Spacer()
                    legend(color: Token.Accent.brand, label: "销售额")
                    legend(color: Token.Status.ok, label: "毛利")
                }

                if stats.dailyPoints.allSatisfy({ $0.count == 0 }) {
                    EmptyState(
                        title: "还没有成交记录",
                        message: "卖出第一台后这里会出现趋势",
                        systemImage: "chart.bar"
                    )
                    .frame(height: 180)
                } else {
                    Chart {
                        ForEach(stats.dailyPoints) { point in
                            BarMark(
                                x: .value("日期", point.date, unit: .day),
                                y: .value("销售额", NSDecimalNumber(decimal: point.revenue).doubleValue)
                            )
                            .foregroundStyle(by: .value("类型", "销售额"))
                            .position(by: .value("类型", "销售额"))

                            BarMark(
                                x: .value("日期", point.date, unit: .day),
                                y: .value("毛利", NSDecimalNumber(decimal: point.profit).doubleValue)
                            )
                            .foregroundStyle(by: .value("类型", "毛利"))
                            .position(by: .value("类型", "毛利"))
                        }
                    }
                    .chartForegroundStyleScale([
                        "销售额": Token.Accent.brand,
                        "毛利": Token.Status.ok,
                    ])
                    .chartLegend(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Token.Border.hairline)
                            AxisValueLabel().foregroundStyle(Token.Ink.tertiary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { value in
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                                .foregroundStyle(Token.Ink.tertiary)
                        }
                    }
                    .frame(height: 190)
                }
            }
        }
    }

    private var agingCard: some View {
        SectionCard(title: "库龄分布") {
            if stats.inStockCount == 0 {
                EmptyState(title: "库存为空", message: "入库后显示库龄构成", systemImage: "clock")
                    .frame(height: 150)
            } else {
                VStack(alignment: .leading, spacing: Token.Space.s) {
                    Chart(stats.agingBuckets.filter { $0.count > 0 }) { bucket in
                        SectorMark(
                            angle: .value("台数", bucket.count),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("库龄", bucket.label))
                    }
                    .chartForegroundStyleScale([
                        "0-30 天": Token.Status.ok,
                        "31-60 天": Token.Accent.brand,
                        "61-90 天": Token.Status.warn,
                        "90 天以上": Token.Status.danger,
                    ])
                    .chartLegend(.hidden)
                    .frame(height: 132)

                    ForEach(stats.agingBuckets) { bucket in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(bucketColor(bucket.label))
                                .frame(width: 7, height: 7)
                            Text(bucket.label)
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.secondary)
                            Spacer()
                            Text("\(bucket.count) 台")
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.primary)
                            Text(bucket.value.mmk)
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.tertiary)
                                .frame(width: 76, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var paymentCard: some View {
        SectionCard(title: "收款方式分布") {
            if stats.paymentSlices.isEmpty {
                EmptyState(title: "暂无成交", message: "按收款方式统计成交额", systemImage: "creditcard")
                    .frame(height: 150)
            } else {
                VStack(alignment: .leading, spacing: Token.Space.s) {
                    Chart(stats.paymentSlices) { slice in
                        SectorMark(
                            angle: .value("金额", NSDecimalNumber(decimal: slice.amount).doubleValue),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("收款方式", slice.method.rawValue))
                    }
                    .chartForegroundStyleScale([
                        PaymentMethod.cash.rawValue: Token.Status.ok,
                        PaymentMethod.transfer.rawValue: Token.Accent.brand,
                        PaymentMethod.card.rawValue: Token.Status.warn,
                        PaymentMethod.other.rawValue: Token.Status.neutral,
                    ])
                    .chartLegend(.hidden)
                    .frame(height: 132)

                    ForEach(stats.paymentSlices) { slice in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(paymentColor(slice.method))
                                .frame(width: 7, height: 7)
                            Text(slice.method.rawValue)
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.secondary)
                            Spacer()
                            Text("\(slice.count) 笔")
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.primary)
                            Text(slice.amount.mmk)
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.tertiary)
                                .frame(width: 76, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var alertSection: some View {
        if stats.lowMarginItems.isEmpty && stats.overdueItems.isEmpty && stats.weakBatteryItems.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Token.Space.s) {
                Text("待办提醒")
                    .font(Token.Typography.cardTitle)
                    .foregroundStyle(Token.Ink.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: Token.Space.m)],
                    spacing: Token.Space.m
                ) {
                    ForEach(stats.lowMarginItems.prefix(3)) { item in
                        AlertCard(
                            title: "低于成本 · \(item.modelName)",
                            message: "标价 \(item.listPrice.mmk) 低于总进价 \(item.landedCost.mmk)，每台亏 \((item.landedCost - item.listPrice).mmk)，建议调价",
                            tone: .danger
                        )
                    }
                    ForEach(stats.weakBatteryItems.prefix(3)) { item in
                        AlertCard(
                            title: "电池偏弱 · \(item.modelName)",
                            message: "健康 \(item.batteryHealthText) · 循环 \(item.batteryCyclesText)，建议检测或作为议价点说明",
                            tone: .warn
                        )
                    }
                    ForEach(stats.overdueItems.prefix(3)) { item in
                        AlertCard(
                            title: "库存超期 · \(item.modelName)",
                            message: "在库 \(item.ageInDays) 天，占用成本 \(item.landedCost.mmk)，建议促销或调价",
                            tone: .warn
                        )
                    }
                }
            }
        }
    }

    /// 环比：昨日无成交时不编造百分比，直接说明没有对比基数
    private func dayOverDay(_ today: Decimal, _ yesterday: Decimal) -> String {
        guard yesterday > 0 else {
            return today > 0 ? "昨日无成交" : "暂无成交"
        }
        let change = ((today - yesterday) / yesterday * 100).rounded(1)
        let sign = change > 0 ? "+" : ""
        return "较昨日 \(sign)\(Money.text(change))%"
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.secondary)
        }
    }

    private func bucketColor(_ label: String) -> Color {
        switch label {
        case "0-30 天": Token.Status.ok
        case "31-60 天": Token.Accent.brand
        case "61-90 天": Token.Status.warn
        default: Token.Status.danger
        }
    }

    private func paymentColor(_ method: PaymentMethod) -> Color {
        switch method {
        case .cash: Token.Status.ok
        case .transfer: Token.Accent.brand
        case .card: Token.Status.warn
        case .other: Token.Status.neutral
        }
    }
}