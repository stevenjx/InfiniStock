import SwiftUI
import SwiftData

/// 右侧检查器容器。内容在 InspectorContent，便于单独渲染验收。
struct CostInspector: View {
    let items: [Item]

    var body: some View {
        ScrollView {
            InspectorContent(items: items)
                .padding(Token.Space.m)
        }
        .background(Token.Surface.canvas)
    }
}

/// 检查器内容：成本结构、毛利、持有情况；多选时聚合。
struct InspectorContent: View {
    let items: [Item]

    var body: some View {
        VStack(spacing: Token.Space.s) {
            if items.isEmpty {
                EmptyState(
                    title: "未选中机器",
                    message: "在列表里选一台，这里显示成本结构",
                    systemImage: "sidebar.right"
                )
                .frame(minHeight: 220)
            } else if let item = items.first, items.count == 1 {
                single(item)
            } else {
                aggregate
            }
        }
    }

    @ViewBuilder
    private func single(_ item: Item) -> some View {
        SectionCard(title: "成本结构") {
            KeyValueRow(label: "进价", value: item.costCNY.cny)
            KeyValueRow(label: "汇率", value: "1 元 = \(Money.text(item.exchangeRate)) 缅币")
            KeyValueRow(label: "进价折缅币", value: item.costMMK.mmk)
            KeyValueRow(label: "运费", value: item.shipping.mmk)
            KeyValueRow(label: "总进价", value: item.landedCost.mmk)
        }

        SectionCard(title: "毛利预估") {
            KeyValueRow(label: "标价", value: item.listPrice.mmk)
            let profit = item.listPrice - item.landedCost
            KeyValueRow(label: "预计毛利", value: profit.signedMMK, valueTone: profit < 0 ? .danger : .ok)
            KeyValueRow(label: "毛利率", value: marginText(profit, base: item.listPrice))
        }

        SectionCard(title: "持有") {
            KeyValueRow(label: "库龄", value: "\(item.ageInDays) 天")
            if item.isOverdue {
                KeyValueRow(label: "提示", value: "超过 \(Item.overdueDays) 天，建议评估降价", valueTone: .danger)
            }
            if let batch = item.batch {
                KeyValueRow(label: "批次", value: batch.name)
                KeyValueRow(label: "批次汇率", value: Money.text(batch.exchangeRate))
                KeyValueRow(label: "已分摊运费", value: item.shipping.mmk)
            }
        }
    }

    @ViewBuilder
    private var aggregate: some View {
        let landed = items.reduce(Decimal(0)) { $0 + $1.landedCost }
        let listed = items.reduce(Decimal(0)) { $0 + $1.listPrice }
        let averageAge = items.isEmpty ? 0 : items.reduce(0) { $0 + $1.ageInDays } / items.count
        let overdue = items.filter(\.isOverdue).count

        SectionCard(title: "已选 \(items.count) 台") {
            KeyValueRow(label: "总成本", value: landed.mmk)
            KeyValueRow(label: "总标价", value: listed.mmk)
            KeyValueRow(
                label: "预计毛利",
                value: (listed - landed).signedMMK,
                valueTone: (listed - landed) < 0 ? .danger : .ok
            )
            KeyValueRow(label: "平均库龄", value: "\(averageAge) 天")
            if overdue > 0 {
                KeyValueRow(label: "呆滞", value: "\(overdue) 台超 \(Item.overdueDays) 天", valueTone: .danger)
            }
        }
    }

    private func marginText(_ profit: Decimal, base: Decimal) -> String {
        guard base > 0 else { return "—" }
        let percent = (profit / base * 100).rounded(1)
        return "\(Money.text(percent))%"
    }
}