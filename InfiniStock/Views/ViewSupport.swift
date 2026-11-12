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

extension Date {
    /// 表格里用的紧凑时间戳：固定为 yyyy-MM-dd HH:mm，
    /// 系统本地化格式（"2026/11/12 中午12:58"）在窄列里会被截断。
    var compactStamp: String {
        Date.compactFormatter.string(from: self)
    }

    private static let compactFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
