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
                backupConfigured: BackupService.backupFolder() != nil,
                autoBackupEnabled: ShopSettings.load().autoBackupEnabled
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
    /// 设置里关掉自动备份时也要提示——有目录不等于会在后台备份
    var autoBackupEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.m) {
            if !autoBackupEnabled {
                AlertCard(
                    title: "自动备份已关闭",
                    message: "备份目录还在，但每天启动时不会自动写快照。点右上角「数据安全」可以手动备份，或在设置里重新打开。",
                    tone: .warn
                )
            } else if !backupConfigured {
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
            efficiencyCard
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
                delta: stats.todayMarginRate.map { String(localized: "毛利率 \(Money.text($0))%") } ?? "今日无成交",
                deltaTone: (stats.todayMarginRate ?? 0) < 0 ? .danger : .ok
            )
            StatCard(
                title: "在库台数",
                value: "\(stats.inStockCount) 台",
                systemImage: "shippingbox.fill",
                tone: .neutral,
                delta: stats.overdueItems.isEmpty ? "无呆滞" : String(localized: "\(stats.overdueItems.count) 台超期"),
                deltaTone: stats.overdueItems.isEmpty ? .neutral : .danger
            )
            StatCard(
                title: "库存总值",
                value: stats.stockCostValue.mmk,
                systemImage: "banknote.fill",
                tone: .warn,
                delta: "标价合计 \(stats.stockListedValue.mmk)"
            )
            StatCard(
                title: "应收未收",
                value: stats.outstandingAmount.mmk,
                systemImage: "exclamationmark.bubble.fill",
                tone: stats.outstandingAmount > 0 ? .danger : .ok,
                delta: stats.outstandingOrderCount > 0
                    ? String(localized: "\(stats.outstandingOrderCount) 张单未收讫")
                    : "全部收讫",
                deltaTone: stats.outstandingAmount > 0 ? .danger : .ok
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
                            Text(String(localized: "\(bucket.count) 台"))
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
                            Text(slice.method.title)
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.secondary)
                            Spacer()
                            Text(String(localized: "\(slice.count) 笔"))
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

    // MARK: - 库存效率

    /// 回答「这批货还能卖多久」。只看现有库存和近 30 天卖速，
    /// 不引入历史快照，所以每个数字都能从库里现有的记录推回去。
    private var efficiencyCard: some View {
        SectionCard(title: "库存效率 · 近 \(stats.windowDays) 天") {
            if stats.inStockCount == 0 && stats.soldInWindow == 0 {
                EmptyState(
                    title: "还没有数据",
                    message: "入库并卖出第一台后，这里给出可售天数与型号售速",
                    systemImage: "speedometer"
                )
                .frame(height: 120)
            } else {
                VStack(alignment: .leading, spacing: Token.Space.m) {
                    HStack(alignment: .top, spacing: Token.Space.l) {
                        efficiencyMetric(
                            title: "可售天数",
                            value: supplyText,
                            hint: "按近 \(stats.windowDays) 天卖速",
                            tone: supplyTone
                        )
                        metricDivider
                        efficiencyMetric(
                            title: "近 \(stats.windowDays) 天售出",
                            value: String(localized: "\(stats.soldInWindow) 台"),
                            hint: "在库 \(stats.inStockCount) 台"
                        )
                        metricDivider
                        efficiencyMetric(
                            title: "滞销占用",
                            value: stats.slowMovingValue.mmk,
                            hint: stats.slowMovingCount > 0
                                ? LocalizedStringResource(stringLiteral: String(localized: "\(stats.slowMovingCount) 台超 \(Item.overdueDays) 天"))
                                : "无超期库存",
                            tone: stats.slowMovingCount > 0 ? Token.Status.danger : Token.Ink.primary
                        )
                        Spacer(minLength: 0)
                    }

                    if !stats.velocity.isEmpty {
                        Hairline()
                        velocityTable
                        Text(String(localized: "可售天数 = 在库 ÷ 近 \(stats.windowDays) 天日均销量；窗口内没有售出的型号标为「无成交」"))
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Ink.tertiary)
                    }
                }
            }
        }
    }

    private var supplyText: String {
        guard stats.inStockCount > 0, let days = stats.daysOfSupply else { return "—" }
        if days >= 365 { return "一年以上" }
        return String(localized: "\(days) 天")
    }

    /// 60 天以内正常，60–120 天偏慢，再长就是积压
    private var supplyTone: Color {
        guard let days = stats.daysOfSupply else { return Token.Status.danger }
        if days > 120 { return Token.Status.danger }
        if days > Item.overdueDays { return Token.Status.warn }
        return Token.Status.ok
    }

    private func efficiencyMetric(
        title: LocalizedStringResource,
        value: String,
        hint: LocalizedStringResource,
        tone: Color = Token.Ink.primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.tertiary)
            Text(value)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(tone)
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(Token.Ink.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Token.Border.hairline)
            .frame(width: 1, height: 34)
    }

    private var velocityTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: Token.Space.s) {
                Text("型号").frame(maxWidth: .infinity, alignment: .leading)
                Text("售出").frame(width: 42, alignment: .trailing)
                Text("在库").frame(width: 42, alignment: .trailing)
                Text("可售").frame(width: 74, alignment: .trailing)
            }
            .font(Token.Typography.caption)
            .foregroundStyle(Token.Ink.tertiary)
            .padding(.bottom, 4)

            ForEach(Array(stats.velocity.prefix(4))) { row in
                Hairline()
                HStack(spacing: Token.Space.s) {
                    Text(row.model)
                        .font(Token.Typography.cellPrimary)
                        .foregroundStyle(Token.Ink.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(row.soldCount)")
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.secondary)
                        .frame(width: 42, alignment: .trailing)
                    Text("\(row.inStockCount)")
                        .font(Token.Typography.money)
                        .foregroundStyle(Token.Ink.secondary)
                        .frame(width: 42, alignment: .trailing)
                    Text(supplyLabel(row))
                        .font(Token.Typography.caption)
                        .foregroundStyle(supplyColor(row))
                        .frame(width: 74, alignment: .trailing)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func supplyLabel(_ row: InventoryStatistics.ModelVelocity) -> String {
        if row.inStockCount == 0 { return "已售罄" }
        guard let days = row.daysOfSupply else { return "无成交" }
        return days >= 365 ? "一年以上" : String(localized: "\(days) 天")
    }

    private func supplyColor(_ row: InventoryStatistics.ModelVelocity) -> Color {
        if row.inStockCount == 0 { return Token.Status.ok }
        guard let days = row.daysOfSupply else { return Token.Status.danger }
        if days > 120 { return Token.Status.danger }
        if days > Item.overdueDays { return Token.Status.warn }
        return Token.Ink.secondary
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

    private func legend(color: Color, label: LocalizedStringResource) -> some View {
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