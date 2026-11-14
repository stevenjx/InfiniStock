import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 批量导入：选文件 → 预检报告 → 确认导入。预检不写库，确认后只写入合法行。
struct ImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var batches: [Batch]

    @State private var preview: CSVImporter.Preview?
    @State private var fileName = ""
    @State private var selectedBatch: Batch?
    @State private var showingPicker = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("选择文件") {
                    HStack {
                        Text(fileName.isEmpty ? "尚未选择" : fileName)
                            .foregroundStyle(fileName.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("选择 CSV…") { showingPicker = true }
                    }
                    Text("首行须为表头，至少包含「序列号」「型号」。可先导出一份 CSV 作为模板。「进价」为必填列；其余金额列留空按 0 处理，汇率留空按 1 处理。")
                        .font(.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }

                if let preview {
                    Section("预检结果") {
                        LabeledContent("可导入", value: String(localized: "\(preview.rows.count) 台"))
                        LabeledContent("有错误", value: String(localized: "\(preview.issues.count) 行"))
                        if !preview.issues.isEmpty {
                            LabeledContent("总数据行", value: String(localized: "\(preview.totalLines) 行"))
                        }
                    }

                    if !preview.issues.isEmpty {
                        Section("错误明细") {
                            ForEach(preview.issues.prefix(50)) { issue in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(String(localized: "第 \(issue.line) 行"))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(Token.Status.danger)
                                        .frame(width: 62, alignment: .leading)
                                    Text("\(issue.field)：\(issue.reason)")
                                        .font(.caption)
                                }
                            }
                            if preview.issues.count > 50 {
                                Text(String(localized: "另有 \(preview.issues.count - 50) 条未显示"))
                                    .font(.caption)
                                    .foregroundStyle(Token.Ink.secondary)
                            }
                            Button {
                                exportIssues(preview.issues)
                            } label: {
                                Label("导出错误清单（CSV）", systemImage: "square.and.arrow.up")
                            }
                        }
                    }

                    Section("入库设置") {
                        Picker("归属批次", selection: $selectedBatch) {
                            Text("不归属批次").tag(Batch?.none)
                            ForEach(batches) { batch in
                                Text(batch.name).tag(Optional(batch))
                            }
                        }
                        Text("导入的机器会按该批次的汇率与运费分摊规则重算总进价。")
                            .font(.caption)
                            .foregroundStyle(Token.Ink.secondary)
                    }

                    Section {
                        Button {
                            commit(preview)
                        } label: {
                            Label(String(localized: "导入 \(preview.rows.count) 台"), systemImage: "tray.and.arrow.down")
                        }
                        .disabled(preview.rows.isEmpty)
                        if let resultMessage {
                            Label(resultMessage, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(Token.Ink.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("批量导入")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                switch result {
                case .success(let url):
                    load(url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 620, minHeight: 640)
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "无法读取该文件"
            return
        }
        fileName = url.lastPathComponent
        resultMessage = nil
        preview = CSVImporter.preview(csv: data, in: modelContext)
    }

    private func commit(_ preview: CSVImporter.Preview) {
        do {
            let count = try CSVImporter.commit(preview, batch: selectedBatch, in: modelContext)
            resultMessage = String(localized: "已导入 \(count) 台")
            // 重新预检：已入库的序列号会自动变成「库中已存在」，避免重复点击
            self.preview = nil
            fileName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportIssues(_ issues: [CSVImporter.Issue]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "导入错误清单.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVImporter.issuesCSV(issues).write(to: url, options: .atomic)
            resultMessage = "错误清单已导出"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}