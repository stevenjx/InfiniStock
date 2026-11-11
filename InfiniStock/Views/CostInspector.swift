import SwiftUI
import SwiftData

/// 右侧检查器：成本结构一目了然，不必打开详情页。
struct CostInspector: View {
    let items: [Item]

    var body: some View {
        Form {
            if items.isEmpty {
                ContentUnavailableView("未选中机器", systemImage: "sidebar.right")
            } else if let item = items.first, items.count == 1 {
                single(item)
            } else {
                aggregate
            }
        }
        .formStyle(.grouped)
        .navigationTitle("检查器")
    }

    @ViewBuilder
    private func single(_ item: Item) -> some View {
        Section("成本结构") {
            LabeledContent("进价", value: "\(Money.text(item.costAmount)) \(item.currency.rawValue)")
            LabeledContent("汇率", value: Money.text(item.exchangeRate))
            LabeledContent("运费", value: item.shippingCNY.cny)
            LabeledContent("落地成本", value: item.landedCostCNY.cny)
        }

        Section("毛利预估") {
            LabeledContent("标价", value: item.listPriceCNY.cny)
            LabeledContent("预计毛利", value: (item.listPriceCNY - item.landedCostCNY).cny)
            LabeledContent("毛利率", value: marginText(item.listPriceCNY - item.landedCostCNY, base: item.listPriceCNY))
        }

        if let batch = item.batch {
            Section("批次") {
                LabeledContent("批次", value: batch.name)
                LabeledContent("锁定汇率", value: Money.text(batch.exchangeRate))
                LabeledContent("批次总运费", value: batch.totalShippingCNY.cny)
                LabeledContent("已分摊运费", value: item.shippingCNY.cny)
            }
        }

        Section("持有") {
            LabeledContent("库龄", value: "\(item.ageInDays) 天")
            if item.isOverdue {
                Text("已超过 \(Item.overdueDays) 天，建议评估降价")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var aggregate: some View {
        let landed = items.reduce(Decimal(0)) { $0 + $1.landedCostCNY }
        let listed = items.reduce(Decimal(0)) { $0 + $1.listPriceCNY }
        let averageAge = items.isEmpty ? 0 : items.reduce(0) { $0 + $1.ageInDays } / items.count

        Section("已选 \(items.count) 台") {
            LabeledContent("总成本", value: landed.cny)
            LabeledContent("总标价", value: listed.cny)
            LabeledContent("预计毛利", value: (listed - landed).cny)
            LabeledContent("平均库龄", value: "\(averageAge) 天")
        }
    }

    private func marginText(_ profit: Decimal, base: Decimal) -> String {
        guard base > 0 else { return "—" }
        let percent = (profit / base * 100).rounded(1)
        return "\(Money.text(percent))%"
    }
}
