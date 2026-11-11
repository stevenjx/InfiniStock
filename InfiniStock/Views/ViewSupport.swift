import SwiftUI

extension View {
    /// 金额输入框的键盘类型（仅 iOS 有意义）
    func decimalKeyboard() -> some View {
        #if os(iOS)
        return keyboardType(.decimalPad)
        #else
        return self
        #endif
    }
}

/// 同步状态提示条。未启用云同步时必须显式告知，否则会误以为数据已上云。
struct SyncNotice: View {
    let cloudSyncEnabled: Bool

    var body: some View {
        if !cloudSyncEnabled {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                Text("本地模式：数据仅存本机，未启用云同步")
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.25))
        }
    }
}
