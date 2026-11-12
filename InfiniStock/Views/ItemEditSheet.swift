import SwiftUI
import SwiftData

/// 改标价与机况。二手 MacBook 的价格和电池数据是谈出来的，
/// 入库后必须能改，否则只能删了重录。
struct ItemEditSheet: View {
    let item: Item

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var priceText = ""
    @State private var healthText = ""
    @State private var cyclesText = ""
    @State private var condition: ItemCondition = .p95
    @State private var errorMessage: String?

    private var price: Decimal {
        Money.parse(priceText) ?? 0
    }

    private var expectedProfit: Decimal {
        price - item.landedCost
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("定价") {
                    TextField("标价（缅币 K）", text: $priceText)
                        .decimalKeyboard()
                    LabeledContent("总进价", value: item.landedCost.mmk)
                    LabeledContent("预计毛利") {
                        Text(expectedProfit.signedMMK)
                            .foregroundStyle(expectedProfit < 0 ? Token.Status.danger : Token.Status.ok)
                    }
                }

                Section("机况") {
                    Picker("成色", selection: $condition) {
                        ForEach(ItemCondition.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    TextField("电池健康 %（留空为未检测）", text: $healthText)
                        .decimalKeyboard()
                    TextField("循环次数（留空为未检测）", text: $cyclesText)
                        .decimalKeyboard()
                }

                Section {
                    Text("标价只影响列表与预估毛利；已售机器的成交价记录在单据上，不随这里改动。")
                        .font(.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑 \(item.modelName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(priceText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 440, minHeight: 420)
        .onAppear(perform: load)
    }

    private func load() {
        priceText = item.listPrice > 0 ? Money.text(item.listPrice) : ""
        healthText = item.batteryHealth > 0 ? String(item.batteryHealth) : ""
        cyclesText = item.batteryCycles > 0 ? String(item.batteryCycles) : ""
        condition = item.condition
    }

    private func save() {
        guard let listPrice = Money.parse(priceText), listPrice >= 0 else {
            errorMessage = "标价不是有效数字"
            return
        }
        let health = Int(healthText.trimmingCharacters(in: .whitespaces)) ?? 0
        let cycles = Int(cyclesText.trimmingCharacters(in: .whitespaces)) ?? 0
        guard (0...100).contains(health), cycles >= 0 else {
            errorMessage = "电池健康需在 0–100 之间，循环次数不能为负数"
            return
        }

        item.listPrice = listPrice
        item.condition = condition
        item.batteryHealth = health
        item.batteryCycles = cycles

        do {
            try context.save()
            SpotlightIndexer.index(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
