import Foundation
import SwiftUI

/// 店铺信息。存在 UserDefaults 里——它是配置而非业务数据，
/// 但仍会写进备份快照，避免换机后凭证抬头丢失。
///
/// 解码必须手写：合成的 Codable 在字段缺失时抛 keyNotFound，
/// 而 load() 用 try? 吞掉错误后返回全新默认值——每加一个字段都会
/// 让用户已存的店名/电话/地址静默清零。这里逐字段 decodeIfPresent 回落默认值。
struct ShopSettings: Codable, Equatable {
    var shopName: String = ""
    var phone: String = ""
    var address: String = ""
    var warrantyDays: Int = 7
    var footnote: String = ""
    /// 入库表单预填的汇率（1 元人民币 = N 缅币）。0 表示没设过，表单留空。
    var defaultExchangeRate: Decimal = 0

    /// 开单时默认选中的收款方式
    var defaultPaymentMethod: String = PaymentMethod.cash.rawValue
    /// 定价建议用的目标毛利率（毛利 ÷ 售价）。0 表示不启用建议。
    var targetMarginPercent: Int = 15
    /// 每天首次启动自动备份；关掉后只能手动备份
    var autoBackupEnabled: Bool = true
    /// 用户点过「以后再说」。只在启动提示里用，待办仍会继续提醒，
    /// 否则一次「稍后」就能让备份这件事永久消失。
    var backupPromptDismissed: Bool = false
    /// 备份目录里保留的份数
    var backupRetention: Int = 14
    /// 界面外观。存字符串而不是枚举，解码时无法识别的值回落「跟随系统」
    var appearance: String = AppearancePreference.auto.rawValue
    /// 界面语言。同上，无法识别的值回落「跟随系统」
    var language: String = AppLanguage.system.rawValue

    private static let key = "infinistock.shopSettings"

    init(
        shopName: String = "",
        phone: String = "",
        address: String = "",
        warrantyDays: Int = 7,
        footnote: String = "",
        defaultExchangeRate: Decimal = 0,
        defaultPaymentMethod: String = PaymentMethod.cash.rawValue,
        targetMarginPercent: Int = 15,
        autoBackupEnabled: Bool = true,
        backupPromptDismissed: Bool = false,
        backupRetention: Int = 14,
        appearance: String = AppearancePreference.auto.rawValue,
        language: String = AppLanguage.system.rawValue
    ) {
        self.shopName = shopName
        self.phone = phone
        self.address = address
        self.warrantyDays = warrantyDays
        self.footnote = footnote
        self.defaultExchangeRate = defaultExchangeRate
        self.defaultPaymentMethod = defaultPaymentMethod
        self.targetMarginPercent = targetMarginPercent
        self.autoBackupEnabled = autoBackupEnabled
        self.backupPromptDismissed = backupPromptDismissed
        self.backupRetention = backupRetention
        self.appearance = appearance
        self.language = language
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shopName = try container.decodeIfPresent(String.self, forKey: .shopName) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        warrantyDays = try container.decodeIfPresent(Int.self, forKey: .warrantyDays) ?? 7
        footnote = try container.decodeIfPresent(String.self, forKey: .footnote) ?? ""
        defaultExchangeRate = try container.decodeIfPresent(Decimal.self, forKey: .defaultExchangeRate) ?? 0
        defaultPaymentMethod = try container.decodeIfPresent(String.self, forKey: .defaultPaymentMethod)
            ?? PaymentMethod.cash.rawValue
        targetMarginPercent = try container.decodeIfPresent(Int.self, forKey: .targetMarginPercent) ?? 15
        autoBackupEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoBackupEnabled) ?? true
        backupPromptDismissed = try container.decodeIfPresent(Bool.self, forKey: .backupPromptDismissed) ?? false
        backupRetention = try container.decodeIfPresent(Int.self, forKey: .backupRetention) ?? 14
        appearance = try container.decodeIfPresent(String.self, forKey: .appearance)
            ?? AppearancePreference.auto.rawValue
        language = try container.decodeIfPresent(String.self, forKey: .language)
            ?? AppLanguage.system.rawValue
    }

    var paymentMethod: PaymentMethod {
        PaymentMethod(rawValue: defaultPaymentMethod) ?? .cash
    }

    var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearance) ?? .auto
    }

    var languagePreference: AppLanguage {
        AppLanguage(rawValue: language) ?? .system
    }

    static func load() -> ShopSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ShopSettings.self, from: data) else {
            return ShopSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case cash = "现金"
    case transfer = "转账"
    case card = "刷卡"
    case other = "其他"

    var id: String { rawValue }

    /// rawValue 是中文，写入单据作为记录值；显示走本地化
    var title: LocalizedStringResource {
        switch self {
        case .cash: "现金"
        case .transfer: "转账"
        case .card: "刷卡"
        case .other: "其他"
        }
    }
}

/// 界面外观。auto 交给系统，跟随 macOS 的浅色/深色切换。
enum AppearancePreference: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .auto: "自动"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    /// 传给 preferredColorScheme；自动时传 nil，让系统决定
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
