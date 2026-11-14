import SwiftUI
import SwiftData

/// 首次提示：库里有货、却还没选备份目录时弹一次。
///
/// 不选也能继续用（「以后再说」），但待办里那条备份提醒会一直在——
/// 关掉弹窗只是把唠叨挪到看不见的地方，不是把风险消掉。
struct BackupPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ShopSettings.load()
    @State private var choosingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.m) {
            HStack(spacing: Token.Space.s) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Token.Status.warn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("这台 Mac 上没有第二份数据")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Token.Ink.primary)
                    Text("现在是 \(itemCount) 台机器、\(orderCount) 张单据")
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.tertiary)
                }
            }

            Text("所有记录只存在这台电脑的沙盒里。选一个文件夹，App 每天首次启动时自动写一份快照过去，误删或换机时才有得恢复。")
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Token.Space.s) {
                Spacer(minLength: 0)
                Button("以后再说") {
                    settings.backupPromptDismissed = true
                    settings.save()
                    dismiss()
                }
                .controlSize(.regular)

                Button("选择备份目录…") { choosingFolder = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(Token.Space.l)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            BackupService.rememberFolder(url)
            dismiss()
        }
        .onAppear { refreshCounts() }
    }

    @State private var itemCount = 0
    @State private var orderCount = 0

    private func refreshCounts() {
        // 这里只用来把话说具体，读不到就当 0，不影响主流程
        let container = AppStore.shared.container
        let context = ModelContext(container)
        itemCount = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        orderCount = (try? context.fetchCount(FetchDescriptor<Order>())) ?? 0
    }
}
