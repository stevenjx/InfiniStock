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
