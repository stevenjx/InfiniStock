import SwiftUI
import SwiftData

struct IntakeSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var batches: [Batch]

    @State private var draft = IntakeDraft()
    @State private var selectedBatch: Batch?
    @State private var showingBatchSheet = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("机器") {
                    TextField("序列号", text: $draft.serialNumber)
                        .monospaced()
                    HStack(spacing: Token.Space.s) {
                        TextField("型号（如 MacBook Air M2 13\"）", text: $draft.modelName)
                        Menu("常用") {
                            ForEach(MacCatalog.presets) { preset in
                                Button(preset.label) {
                                    draft.modelName = preset.modelName
                                    draft.chip = preset.chip
                                    draft.memory = preset.memory
                                    draft.storage = preset.storage
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    TextField("芯片（可选）", text: $draft.chip)
                    TextField("内存（可选）", text: $draft.memory)
                    TextField("存储（可选）", text: $draft.storage)
                    TextField("颜色（可选）", text: $draft.color)
                    Picker("成色", selection: $draft.condition) {
                        ForEach(ItemCondition.allCases) { condition in
                            Text(condition.rawValue).tag(condition)
                        }
                    }
                    HStack(spacing: Token.Space.m) {
                        TextField("电池健康 %（可选）", text: $draft.batteryHealth)
                            .decimalKeyboard()
                        TextField("循环次数（可选）", text: $draft.batteryCycles)
                            .decimalKeyboard()
                    }
                }

                Section("批次") {
                    Picker("归属批次", selection: $selectedBatch) {
                        Text("不归属批次").tag(Batch?.none)
                        ForEach(batches) { batch in
                            Text(batch.name).tag(Optional(batch))
                        }
                    }
                    Button("新建批次…") { showingBatchSheet = true }
                }

                Section("成本") {
                    TextField("进价（人民币 ¥）", text: $draft.costCNY)
                        .decimalKeyboard()
                    TextField("汇率（1 元 = ? 缅币）", text: $draft.exchangeRate)
                        .decimalKeyboard()
                    TextField("运费（缅币 K）", text: $draft.shipping)
                        .decimalKeyboard()
                    LabeledContent("总进价（缅币）", value: draft.previewLandedCost.mmk)
                }

                Section("定价") {
                    TextField("标价（缅币 K）", text: $draft.listPrice)
                        .decimalKeyboard()
                }

                Section {
                    Text("序列号会按大写去空格后查重，重复录入将被拦截。")
                        .font(.caption)
                        .foregroundStyle(Token.Ink.secondary)
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
            .sheet(isPresented: $showingBatchSheet) {
                BatchSheet()
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
            let item = try InventoryService.intake(draft, batch: selectedBatch, in: context)
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
