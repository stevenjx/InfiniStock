import Foundation

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

    private static let key = "infinistock.shopSettings"

    init(
        shopName: String = "",
        phone: String = "",
        address: String = "",
        warrantyDays: Int = 7,
        footnote: String = "",
        defaultExchangeRate: Decimal = 0
    ) {
        self.shopName = shopName
        self.phone = phone
        self.address = address
        self.warrantyDays = warrantyDays
        self.footnote = footnote
        self.defaultExchangeRate = defaultExchangeRate
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shopName = try container.decodeIfPresent(String.self, forKey: .shopName) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        warrantyDays = try container.decodeIfPresent(Int.self, forKey: .warrantyDays) ?? 7
        footnote = try container.decodeIfPresent(String.self, forKey: .footnote) ?? ""
        defaultExchangeRate = try container.decodeIfPresent(Decimal.self, forKey: .defaultExchangeRate) ?? 0
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
}
