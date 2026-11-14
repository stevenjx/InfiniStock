import SwiftUI
import SwiftData
import Charts
import AppKit

/// 期间报表。仪表盘回答"今天怎么样"，这一页回答"这个月赚了多少"——
/// 后者才是月底真正要交出去的数字。
struct ReportView: View {
    /// 范围由 RootView 持有，右栏的口径说明要跟着一起变
    @Binding var range: ReportRange
    @Query private var orders: [Order]
    @State private var exportMessage: String?

    private var bounds: (start: Date, end: Date) {
        range.bounds()
    }

    private var report: PeriodReport {
        PeriodReport(orders: orders, start: bounds.start, end: bounds.end)
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar {
                FilterPillGroup(
                    options: ReportRange.allCases.map { PillOption(value: $0, title: $0.title) },
                    selection: range
                ) { range = $0 }

                Spacer(minLength: Token.Space.s)

                Text(rangeText)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)

                Button {
                    exportCSV()
                } label: {
                    Label("导出 CSV", systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
                .disabled(report.orderCount == 0)
                .help("导出这段期间的单据明细，可直接给 Excel 打开")
            }

            ScrollView {
                VStack(spacing: Token.Space.m) {
                    kpiRow
                    trendCard
                    HStack(alignment: .top, spacing: Token.Space.m) {
                        modelCard
                        paymentCard
                    }
                }
                .padding(Token.Space.l)
            }
        }
        .background(Token.Surface.canvas)
        .overlay(alignment: .bottom) {
            if let exportMessage {
                Text(exportMessage)
                    .font(Token.Typography.caption)
                    .padding(8)
                    .background(.thinMaterial, in: .rect(cornerRadius: 8))
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - 分区

    private var kpiRow: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Token.Space.m)],
            spacing: Token.Space.m
        ) {
            StatCard(
                title: "销售额",
                value: report.revenue.mmk,
                systemImage: "cart.fill",
                tone: .brand,
                delta: "\(report.orderCount) 张单 · \(report.machineCount) 台"
            )
            StatCard(
                title: "毛利",
                value: report.profit.signedMMK,
                systemImage: "chart.line.uptrend.xyaxis",
                tone: report.profit < 0 ? .danger : .ok,
                delta: report.marginRate.map { String(localized: "毛利率 \(Money.text($0))%") } ?? "期间无成交",
                deltaTone: report.profit < 0 ? .danger : .ok
            )
            StatCard(
                title: "实收",
                value: report.collected.mmk,
                systemImage: "banknote.fill",
                tone: .neutral,
                delta: report.outstanding > 0 ? String(localized: "还欠 \(report.outstanding.mmk)") : "全部收讫",
                deltaTone: report.outstanding > 0 ? .warn : .ok
            )
            StatCard(
                title: "客单价",
                value: report.averageOrder.mmk,
                systemImage: "person.crop.circle",
                tone: .neutral,
                delta: "每台 \(report.averageTicket.mmk)"
            )
        }
    }

    private var trendCard: some View {
        SectionCard(title: "每日销售额与毛利") {
            if report.orderCount == 0 {
                EmptyState(
                    title: "这段期间没有成交",
                    message: "换个范围看看，或去库存页出库",
                    systemImage: "chart.bar"
                )
                .frame(height: 160)
            } else {
                VStack(alignment: .leading, spacing: Token.Space.s) {
                    // 两组柱子没有图例就只能靠猜，系统图例又跟这里的字号对不上，
                    // 干脆自己画一行
                    HStack(spacing: Token.Space.m) {
                        legendItem("销售额", Token.Accent.brand)
                        legendItem("毛利", Token.Status.ok)
                        Spacer(minLength: 0)
                    }
                    Chart(report.byDay) { point in
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
                    .chartForegroundStyleScale([
                        "销售额": Token.Accent.brand,
                        "毛利": Token.Status.ok,
                    ])
                    .chartLegend(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Token.Border.hairline)
                            AxisValueLabel {
                                // 缅币动辄百万，默认刻度会写成 7.5E6——对店主等于乱码
                                Text(axisAmount(value.as(Double.self) ?? 0))
                                    .font(Token.Typography.caption)
                                    .foregroundStyle(Token.Ink.tertiary)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 8)) { value in
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                                .foregroundStyle(Token.Ink.tertiary)
                        }
                    }
                    .frame(height: 168)
                }
            }
        }
    }

    private var modelCard: some View {
        SectionCard(title: report.byModel.isEmpty
                    ? "按型号"
                    : "按型号 · \(report.byModel.count) 款") {
            if report.byModel.isEmpty {
                EmptyState(title: "没有成交", message: "卖出机器后这里按毛利排序", systemImage: "laptopcomputer")
                    .frame(height: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(report.byModel.enumerated()), id: \.element.id) { index, slice in
                        if index > 0 { Hairline() }
                        HStack(spacing: Token.Space.s) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(slice.model)
                                    .font(Token.Typography.cellPrimary)
                                    .foregroundStyle(Token.Ink.primary)
                                    .lineLimit(1)
                                Text("\(slice.count) 台 · 收入 \(slice.revenue.mmk)")
                                    .font(Token.Typography.caption)
                                    .foregroundStyle(Token.Ink.tertiary)
                            }
                            Spacer(minLength: Token.Space.s)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(slice.profit.signedMMK)
                                    .font(Token.Typography.money)
                                    .foregroundStyle(slice.profit < 0 ? Token.Status.danger : Token.Ink.primary)
                                Text(slice.marginRate.map { "\(Money.text($0))%" } ?? "—")
                                    .font(Token.Typography.caption)
                                    .foregroundStyle(Token.Ink.tertiary)
                            }
                        }
                        .padding(.vertical, Token.Space.s)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var paymentCard: some View {
        // 标题点明口径：这里按成交额分摊，赊账那部分钱还没到账，
        // 写成"收款方式"会让人误以为卡里的钱就是到手的钱。
        SectionCard(title: "收款方式 · 按成交额") {
            if report.byPayment.isEmpty {
                EmptyState(title: "没有成交", message: "按收款方式统计金额", systemImage: "creditcard")
                    .frame(height: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(report.byPayment.enumerated()), id: \.element.id) { index, slice in
                        if index > 0 { Hairline() }
                        HStack(spacing: Token.Space.s) {
                            Circle()
                                .fill(color(for: slice.method))
                                .frame(width: 7, height: 7)
                            Text(slice.method.title)
                                .font(Token.Typography.body)
                                .foregroundStyle(Token.Ink.primary)
                            Spacer(minLength: Token.Space.s)
                            Text(String(localized: "\(slice.count) 笔"))
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.tertiary)
                            Text(slice.amount.mmk)
                                .font(Token.Typography.money)
                                .foregroundStyle(Token.Ink.primary)
                        }
                        .padding(.vertical, Token.Space.s)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 辅助

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.secondary)
        }
    }

    /// 坐标轴刻度用紧凑写法：750万 / 1.2亿。
    /// 刻度只是给人看个量级，不需要分位逗号，也不该出现科学计数法。
    private func axisAmount(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 100_000_000 {
            return trimmedUnit(value / 100_000_000) + "亿"
        }
        if magnitude >= 10_000 {
            return trimmedUnit(value / 10_000) + "万"
        }
        return trimmedUnit(value)
    }

    private func trimmedUnit(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    private var rangeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: bounds.end) ?? bounds.end
        return "\(formatter.string(from: bounds.start)) 至 \(formatter.string(from: lastDay))"
    }

    private func color(for method: PaymentMethod) -> Color {
        switch method {
        case .cash: Token.Status.ok
        case .transfer: Token.Accent.brand
        case .card: Token.Status.warn
        case .other: Token.Status.neutral
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "销售明细-\(range.rawValue).csv")
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text = PeriodReport.csv(report, orders: orders)
        do {
            try text.data(using: .utf8)?.write(to: url)
            exportMessage = "已导出 \(report.machineCount) 台到 \(url.lastPathComponent)"
        } catch {
            exportMessage = String(localized: "导出失败：\(error.localizedDescription)")
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            exportMessage = nil
        }
    }
}

/// 报表页右栏：把这些数字怎么算的说清楚。
/// 报表最怕"数字对不上但没人知道口径"，所以口径要写在旁边而不是藏进文档。
struct ReportScopePanel: View {
    let range: ReportRange

    private var bounds: (start: Date, end: Date) { range.bounds() }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "口径", subtitle: range.rawValue)

            ScrollView {
                VStack(spacing: 0) {
                    PanelSection(title: "期间") {
                        KeyValueRow(label: "开始", value: day(bounds.start))
                        KeyValueRow(label: "结束", value: day(Calendar.current.date(byAdding: .day, value: -1, to: bounds.end) ?? bounds.end))
                        KeyValueRow(label: "边界", value: "含开始日，不含结束日")
                    }

                    PanelSection(title: "计入规则") {
                        KeyValueRow(label: "作废单", value: "不计入")
                        KeyValueRow(label: "退货", value: "按净额计入")
                        KeyValueRow(label: "折扣", value: "已从销售额扣除")
                        KeyValueRow(label: "毛利", value: "实收 − 总进价")
                    }

                    PanelSection(title: "三个金额的区别") {
                        KeyValueRow(label: "销售额", value: "成交额，含未收款")
                        KeyValueRow(label: "实收", value: "实际到手的钱")
                        KeyValueRow(label: "应收未收", value: "还在客户手上")
                    }

                    PanelSection(title: "为什么按单据算") {
                        Text("金额以单据为准，不按机器累加——折扣和抹零只记在单据上，逐台累加会虚报收入。")
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .background(Token.Surface.card)
    }

    private func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
