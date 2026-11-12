import Foundation
import LocalAuthentication

/// 敏感操作的门禁。用 deviceOwnerAuthentication，没有 Touch ID 的机器自动退化为系统密码。
enum BiometricGate {

    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
