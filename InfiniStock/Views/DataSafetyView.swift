import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 数据安全：导出、自动备份目录、恢复。恢复含破坏性操作，必须身份验证。
struct DataSafetyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var itemCount = 0
    @State private var orderCount = 0
    @State private var backupFolder: URL?
    @State private var lastBackupAt: Date?
    @State private var choosingFolder = false
    @State private var restoring = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("当前数据") {
                LabeledContent("机器", value: String(localized: "\(itemCount) 台"))
                LabeledContent("单据", value: String(localized: "\(orderCount) 张"))
            }

            Section("导出") {
                Button {
                    exportJSON()
                } label: {
                    Label("导出全量备份（JSON）", systemImage: "square.and.arrow.up")
                }
                Button {
                    exportCSV()
                } label: {
                    Label("导出表格（CSV，可用 Excel 打开）", systemImage: "tablecells")
                }
                Text("JSON 可回灌恢复，含照片；CSV 只用于查看与对账。")
                    .font(.caption)
                    .foregroundStyle(Token.Ink.secondary)
            }

            Section("自动备份") {
                LabeledContent("备份目录") {
                    Text(backupFolder?.path ?? "未设置")
                        .font(.caption)
                        .foregroundStyle(backupFolder == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                LabeledContent("最近备份") {
                    Text(lastBackupAt.map { $0.formatted(date: .numeric, time: .shortened) } ?? "尚无")
                        .font(.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
                Button("选择备份目录…") { choosingFolder = true }
                if backupFolder != nil {
                    Button("立即备份一次") { runBackup() }
                }
                Text(String(localized: "每天首次启动自动备份一次（可在设置里关闭），保留最近 \(ShopSettings.load().backupRetention) 份。目录由你在系统面板中授权，App 之后才能持续写入。"))
                    .font(.caption)
                    .foregroundStyle(Token.Ink.secondary)
            }

            Section("恢复") {
                Button(role: .destructive) {
                    restoring = true
                } label: {
                    Label("从备份文件恢复…", systemImage: "arrow.down.doc")
                }
                Text("恢复会清空当前全部数据再写入备份内容，需要系统身份验证。建议先导出一份当前数据。")
                    .font(.caption)
                    .foregroundStyle(Token.Status.warn)
            }

            if let message {
                Section {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(Token.Ink.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("数据安全")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .task { refresh() }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                BackupService.rememberFolder(url)
                refresh()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                Task { await performRestore(from: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refresh() {
        itemCount = (try? modelContext.fetchCount(FetchDescriptor<Item>())) ?? 0
        orderCount = (try? modelContext.fetchCount(FetchDescriptor<Order>())) ?? 0
        backupFolder = BackupService.backupFolder()
        lastBackupAt = BackupService.lastBackupAt
    }

    private func exportJSON() {
        guard let data = try? BackupService.jsonData(BackupService.makeSnapshot(from: modelContext)) else {
            errorMessage = "生成备份失败"
            return
        }
        save(data: data, name: BackupService.backupFileName(at: .now), type: .json)
    }

    private func exportCSV() {
        guard let data = try? BackupService.csvData(from: modelContext) else {
            errorMessage = "生成 CSV 失败"
            return
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        save(data: data, name: "infinistock-\(formatter.string(from: .now)).csv", type: .commaSeparatedText)
    }

    private func save(data: Data, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            message = String(localized: "已导出到 \(url.lastPathComponent)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runBackup() {
        guard let folder = BackupService.backupFolder() else {
            errorMessage = "尚未设置备份目录"
            return
        }
        do {
            let url = try BackupService.writeBackup(from: modelContext, into: folder)
            message = String(localized: "已备份 \(url.lastPathComponent)")
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRestore(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "无法读取该文件"
            return
        }
        guard let snapshot = try? BackupService.decode(data) else {
            errorMessage = "文件不是有效的 InfiniStock 备份"
            return
        }
        guard await BiometricGate.authenticate(reason: "恢复备份将覆盖当前全部数据") else {
            errorMessage = "身份验证未通过，恢复已取消"
            return
        }
        do {
            try BackupService.restore(snapshot, into: modelContext)
            message = "已恢复 \(snapshot.items.count) 台机器、\(snapshot.orders.count) 张单据"
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}