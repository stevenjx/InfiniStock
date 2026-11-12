import Foundation

/// 店铺信息。存在 UserDefaults 里——它是配置而非业务数据，
/// 但仍会写进备份快照，避免换机后凭证抬头丢失。
struct ShopSettings: Codable, Equatable {
    var shopName: String = ""
    var phone: String = ""
    var address: String = ""
    var warrantyDays: Int = 7
    var footnote: String = ""

    private static let key = "infinistock.shopSettings"

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
