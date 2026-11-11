import SwiftUI
import SwiftData

struct IntakeSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var draft = IntakeDraft()
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("机器") {
                    TextField("序列号", text: $draft.serialNumber)
                        .monospaced()
                    TextField("型号（如 iPhone 17 Pro Max）", text: $draft.modelName)
                    TextField("芯片（可选）", text: $draft.chip)
                    TextField("内存（可选）", text: $draft.memory)
                    TextField("存储（可选）", text: $draft.storage)
                    TextField("颜色（可选）", text: $draft.color)
                    Picker("成色", selection: $draft.condition) {
                        ForEach(ItemCondition.allCases) { condition in
                            Text(condition.rawValue).tag(condition)
                        }
                    }
                }

                Section("成本") {
                    TextField("进价", text: $draft.costAmount)
                        .decimalKeyboard()
                    Picker("币种", selection: $draft.currency) {
                        ForEach(CostCurrency.allCases) { currency in
                            Text(currency.rawValue).tag(currency)
                        }
                    }
                    TextField("汇率（原币 → 人民币）", text: $draft.exchangeRate)
                        .decimalKeyboard()
                    TextField("运费（人民币）", text: $draft.shippingCNY)
                        .decimalKeyboard()
                    LabeledContent("落地成本", value: draft.previewLandedCost.cny)
                }

                Section("定价") {
                    TextField("标价", text: $draft.listPriceCNY)
                        .decimalKeyboard()
                }

                Section {
                    Text("序列号会按大写去空格后查重，重复录入将被拦截。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("入库")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .alert("入库失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if let savedMessage {
                    Text(savedMessage)
                        .font(.caption)
                        .padding(8)
                        .background(.thinMaterial, in: .rect(cornerRadius: 8))
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func save() {
        do {
            let item = try InventoryService.intake(draft, in: context)
            let savedSerial = item.serialNumber
            draft = IntakeDraft()
            savedMessage = "已入库 \(savedSerial)"
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                savedMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
