import SwiftUI

/// 多选时的详情栏。
///
/// 这块内容原来在独立的「成本检查器」里：同一个窗口两块右栏，讲的却是同一件事。
/// 合并进详情栏后，单选取机器、多选取汇总，右栏只有一处。
struct SelectionSummaryView: View {
    let items: [Item]

    private var landed: Decimal {
        items.reduce(Decimal(0)) { $0 + $1.landedCost }
    }

    private var listed: Decimal {
        items.reduce(Decimal(0)) { $0 + $1.listPrice }
    }

    private var profit: Decimal { listed - landed }

    private var averageAge: Int {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.ageInDays } / items.count
    }

    private var overdueCount: Int {
        items.filter(\.isOverdue).count
    }

    /// 已售或锁定的机器不能出库，混选时要先说清楚能出几台
    private var sellableCount: Int {
        items.filter { $0.status == .inStock }.count
    }

    private var marginText: String {
        guard listed > 0 else { return "—" }
        return "\((profit / listed * 100).rounded(1))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "已选 \(items.count) 台", subtitle: "多选汇总")

            ScrollView {
                VStack(spacing: Token.Space.m) {
                    totals
                    PanelSection(title: "构成") {
                        MetricGrid {
                            MetricCell(label: "平均库龄", value: "\(averageAge) 天")
                            MetricCell(
                                label: "超期",
                                value: overdueCount > 0 ? "\(overdueCount) 台" : "无",
                                tone: overdueCount > 0 ? .danger : nil
                            )
                            MetricCell(label: "可出库", value: "\(sellableCount) 台")
                            MetricCell(label: "已售 / 锁定", value: "\(items.count - sellableCount) 台")
                        }
                    }
                    roster
                }
                .padding(Token.Space.m)
            }
        }
        .background(Token.Surface.card)
    }

    /// 汇总放在最上面：多选时唯一想立刻知道的就是这一批压了多少钱、能赚多少
    private var totals: some View {
        VStack(alignment: .leading, spacing: Token.Space.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("总成本")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Token.Ink.secondary)
                    Text(landed.mmk)
                        .font(Token.Typography.metric)
                        .foregroundStyle(Token.Ink.primary)
                }
                Spacer(minLength: Token.Space.s)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("预计毛利")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Token.Ink.secondary)
                    Text(profit.signedMMK)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(profit < 0 ? Token.Status.danger : Token.Status.ok)
                    Text("毛利率 \(marginText)")
                        .font(.system(size: 10))
                        .foregroundStyle(Token.Ink.tertiary)
                }
            }

            Hairline()

            HStack {
                Text("标价合计")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
                Spacer()
                Text(listed.mmk)
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.primary)
            }
        }
        .padding(Token.Space.m)
        .background(Token.Accent.fill, in: .rect(cornerRadius: Token.Radius.card))
    }

    private var roster: some View {
        PanelSection(title: "清单", trailing: "成本") {
            VStack(spacing: 0) {
                ForEach(Array(items.prefix(8).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Hairline() }
                    HStack(spacing: Token.Space.s) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.modelName)
                                .font(Token.Typography.cellPrimary)
                                .foregroundStyle(Token.Ink.primary)
                                .lineLimit(1)
                            Text(item.serialNumber)
                                .font(Token.Typography.caption)
                                .monospaced()
                                .foregroundStyle(Token.Ink.tertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: Token.Space.s)
                        Text(item.landedCost.mmk)
                            .font(Token.Typography.money)
                            .foregroundStyle(Token.Ink.secondary)
                    }
                    .padding(.vertical, 6)
                }
                if items.count > 8 {
                    Hairline()
                    Text("还有 \(items.count - 8) 台未列出")
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
            }
        }
    }
}
