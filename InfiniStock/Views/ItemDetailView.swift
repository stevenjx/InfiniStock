import SwiftUI
import SwiftData

struct ItemDetailView: View {
    let item: Item
    @State private var showingSale = false
    @State private var showingReceipt = false

    var body: some View {
        Form {
            Section("机器") {
                LabeledContent("型号", value: item.modelName)
                LabeledContent("序列号", value: item.serialNumber)
                LabeledContent("芯片", value: dash(item.chip))
                LabeledContent("内存", value: dash(item.memory))
                LabeledContent("存储", value: dash(item.storage))
                LabeledContent("颜色", value: dash(item.color))
                LabeledContent("成色", value: item.condition.rawValue)
                LabeledContent("入库时间", value: item.inboundAt.formatted(date: .numeric, time: .shortened))
            }

            Section("实物照片") {
                PhotoField(item: item)
            }

            Section("成本") {
                LabeledContent("进价", value: "\(Money.text(item.costAmount)) \(item.currency.rawValue)")
                LabeledContent("汇率", value: Money.text(item.exchangeRate))
                LabeledContent("运费", value: item.shippingCNY.cny)
                LabeledContent("落地成本", value: item.landedCostCNY.cny)
            }

            Section("价格") {
                LabeledContent("标价", value: item.listPriceCNY.cny)
                if item.status == .sold {
                    LabeledContent("成交价", value: item.soldPriceCNY.cny)
                    LabeledContent("毛利") {
                        Text(item.grossProfitCNY.cny)
                            .foregroundStyle(item.grossProfitCNY < 0 ? Color.orange : Color.primary)
                    }
                }
            }

            Section("状态") {
                LabeledContent("当前状态", value: item.status.label)
                if let order = item.order {
                    LabeledContent("单号", value: order.number)
                    LabeledContent("客户", value: dash(order.customerName))
                    LabeledContent("联系方式", value: dash(order.customerContact))
                    LabeledContent("出库时间", value: (item.soldAt ?? order.createdAt).formatted(date: .numeric, time: .shortened))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(item.modelName.isEmpty ? "机器详情" : item.modelName)
        .toolbar {
            if item.status == .inStock {
                ToolbarItem(placement: .primaryAction) {
                    Button("出库销售") { showingSale = true }
                }
            }
            if item.order != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("销售凭证") { showingReceipt = true }
                }
            }
        }
        .sheet(isPresented: $showingSale) {
            SaleSheet(items: [item])
        }
        .sheet(isPresented: $showingReceipt) {
            if let order = item.order {
                ReceiptSheet(order: order)
            }
        }
    }

    private func dash(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }
}
