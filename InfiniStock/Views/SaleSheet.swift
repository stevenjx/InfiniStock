import SwiftUI
import SwiftData

/// 出库单。单台时可改成交价，多台时按各台标价合计，避免批量改价造成误操作。
struct SaleSheet: View {
    let items: [Item]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var priceText: String
    @State private var customerName = ""
    @State private var customerContact = ""
    @State private var errorMessage: String?

    init(items: [Item]) {
        self.items = items
        let initial = items.count == 1 ? Money.text(items[0].listPriceCNY) : ""
        _priceText = State(initialValue: items[0].listPriceCNY > 0 ? initial : "")
    }

    private var isBatch: Bool { items.count > 1 }

    private var revenue: Decimal {
        isBatch ? items.reduce(0) { $0 + $1.listPriceCNY } : (Money.parse(priceText) ?? 0)
    }

    private var landedTotal: Decimal {
        items.reduce(0) { $0 + $1.landedCostCNY }
    }

    private var profit: Decimal {
        revenue - landedTotal
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isBatch ? "待出库 \(items.count) 台" : "机器") {
                    if isBatch {
                        ForEach(items) { item in
                            HStack {
                                Text(item.modelName)
                                Text(item.serialNumber)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(item.listPriceCNY.cny).monospacedDigit()
                            }
                        }
                    } else if let item = items.first {
                        LabeledContent("型号", value: item.modelName)
                        LabeledContent("序列号", value: item.serialNumber)
                        LabeledContent("落地成本", value: item.landedCostCNY.cny)
                    }
                }

                Section("成交") {
                    if isBatch {
                        LabeledContent("合计（按标价）", value: revenue.cny)
                    } else {
                        TextField("成交价", text: $priceText)
                            .decimalKeyboard()
                    }
                    TextField("客户名称", text: $customerName)
                    TextField("联系方式（可选）", text: $customerContact)
                }

                Section("预估毛利") {
                    LabeledContent("毛利") {
                        Text(profit.cny)
                            .foregroundStyle(profit < 0 ? Color.orange : Color.primary)
                    }
                    if profit < 0 {
                        Text("低于总成本，确认前请复核成交价")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isBatch ? "批量出库" : "出库销售")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认出库") { confirm() }
                        .disabled(!isBatch && Money.parse(priceText) == nil)
                }
            }
            .alert("出库失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    private func confirm() {
        if !isBatch, Money.parse(priceText) == nil {
            errorMessage = "成交价格式不正确"
            return
        }
        do {
            try InventoryService.sell(
                items: items,
                unitPrice: isBatch ? nil : Money.parse(priceText),
                customerName: customerName,
                customerContact: customerContact,
                in: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
