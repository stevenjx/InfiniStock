import Foundation
import SwiftUI
import Observation

/// 界面语言。
///
/// 为什么不用系统的「跟随 macOS 语言」就够了：店主可能系统是英文、但想用中文界面，
/// 或者反过来。所以这里给出显式选择，默认仍然是跟随系统。
///
/// 切换方式：改的是 `AppleLanguages` 这一项 UserDefaults，并让 SwiftUI 的整个树
/// 用新的 locale 重新渲染。不重启应用，因为设置页本身就是验证语言的最直接位置。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    /// 语言菜单里的名称，两种语言下都写成自己那一套——
    /// 中文界面里英文选项就叫 English，英文界面里中文选项就叫「简体中文」。
    /// 这是各家系统设置的通行做法：语言名不翻译成当前界面语言。
    var label: LocalizedStringResource {
        switch self {
        case .system: "跟随系统"
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    /// 实际生效的语言。`.system` 时看系统首选语言
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .chinese : .english
    }

    var locale: Locale {
        switch resolved {
        case .chinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        case .system: Locale.current
        }
    }

    var isChinese: Bool { resolved == .chinese }

    /// 缅币前缀。中文习惯 K，英文用 ISO 代码 MMK
    var kyatPrefix: String { isChinese ? "K " : "MMK " }

    // MARK: - 全局当前语言

    private static let key = "infinistock.language"

    /// 当前界面语言。读一次 UserDefaults，值很小，不做缓存——
    /// 缓存就得负责失效，而这里调用的成本远低于一次 O(1) 的 plist 读取。
    static var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let value = AppLanguage(rawValue: raw) else { return .system }
        return value
    }

    static var currentLocale: Locale { current.locale }

    /// 写入选择，并让 SwiftUI 立刻用新语言重绘。
    ///
    /// 只改自己的 key 不够：`Text("...")` 里的 `LocalizedStringKey` 查的是
    /// `AppleLanguages`，所以要同时写那一项。`.system` 时把这一项删掉，
    /// 回到由系统决定的状态。
    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: key)
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }
}

/// 让整棵树跟着语言重绘。
///
/// `environment(\.locale,...)` 只影响格式化，不影响 `LocalizedStringKey` 的查找；
/// 所以除了 locale，还要用 `.id(语言)` 强制重建一次视图树。这一步代价很小
/// （切换语言是低频操作），换来的是不需要重启。
struct LocalizedRoot<Content: View>: View {
    let language: AppLanguage
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environment(\.locale, language.resolved.locale)
            .id(language.resolved.rawValue)
    }
}
