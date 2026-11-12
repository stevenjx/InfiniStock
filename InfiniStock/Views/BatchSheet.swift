import SwiftUI
import SwiftData

/// 新建进货批次：汇率与运费在此锁定，之后逐台入库都由批次分摊。
struct BatchSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var supplier = ""
    @State private var rateText = ""
    @State private var shippingText = "0"
    @State private var allocation: AllocationMethod = .byValue
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("批次") {
                    TextField("名称（如 2026-11 深圳批）", text: $name)
                    TextField("供应商（可选）", text: $supplier)
                }

                Section("成本口径") {
                    TextField("锁定汇率（1 元 = ? 缅币）", text: $rateText)
                        .decimalKeyboard()
                    TextField("本批总运费（缅币 K）", text: $shippingText)
                        .decimalKeyboard()
                    Picker("运费分摊", selection: $allocation) {
                        ForEach(AllocationMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                }

                Section {
                    Text("汇率锁定后，本批每台机器的总进价都按该汇率折算（人民币进价 × 汇率 + 分摊运费），不受后续汇率波动影响。运费分摊的尾差由最后一台吸收，保证合计精确。")
                        .font(.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("新建批次")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("创建失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 480, minHeight: 460)
    }

    private func save() {
        guard let rate = Money.parse(rateText), rate > 0 else {
            errorMessage = "汇率必须大于 0（1 元人民币 = N 缅币）"
            return
        }
        guard let shipping = Money.parse(shippingText), shipping >= 0 else {
            errorMessage = "运费不正确"
            return
        }

        let batch = Batch()
        batch.name = name.trimmingCharacters(in: .whitespaces)
        batch.supplier = supplier.trimmingCharacters(in: .whitespaces)
        batch.exchangeRate = rate
        batch.totalShipping = shipping
        batch.allocation = allocation
        batch.createdAt = .now
        context.insert(batch)

        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
