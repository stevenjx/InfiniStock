import SwiftUI
import SwiftData

struct SaleSheet: View {
    let item: Item

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var priceText: String
    @State private var customerName = ""
    @State private var customerContact = ""
    @State private var errorMessage: String?

    init(item: Item) {
        self.item = item
        _priceText = State(initialValue: item.listPriceCNY > 0 ? Money.text(item.listPriceCNY) : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("机器") {
                    LabeledContent("型号", value: item.modelName)
                    LabeledContent("序列号", value: item.serialNumber)
                    LabeledContent("落地成本", value: item.landedCostCNY.cny)
                }

                Section("成交") {
                    TextField("成交价", text: $priceText)
                        .decimalKeyboard()
                    TextField("客户名称", text: $customerName)
                    TextField("联系方式（可选）", text: $customerContact)
                }

                Section("预估毛利") {
                    LabeledContent("毛利") {
                        Text(profit.cny)
                            .foregroundStyle(profit < 0 ? Color.orange : Color.primary)
                    }
                    if profit < 0 {
                        Text("低于落地成本，确认前请复核成交价")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("出库销售")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认出库") { confirm() }
                        .disabled(Money.parse(priceText) == nil)
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
    }

    private var profit: Decimal {
        (Money.parse(priceText) ?? 0) - item.landedCostCNY
    }

    private func confirm() {
        guard let price = Money.parse(priceText) else {
            errorMessage = "成交价格式不正确"
            return
        }
        do {
            try InventoryService.sell(
                items: [item],
                unitPrice: price,
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
