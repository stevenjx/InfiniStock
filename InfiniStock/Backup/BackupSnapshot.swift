import Foundation

/// 备份快照。金额一律以字符串编码——JSONEncoder 走 Double 会丢精度，
/// 1234.56 存成 1234.5599999999999 这种事在成本账上不能接受。
///
/// 格式版本 4 起币种口径固定：进价人民币、汇率「1 元 = N 缅币」，
/// 运费 / 总进价 / 卖价 / 毛利全部是缅币。版本 3 及更早的备份用的是多币种口径，
/// 金额含义不同，静默恢复会把账算错，因此直接拒绝并要求重新导出。
struct BackupSnapshot: Codable {
    static let currentFormatVersion = 4
    static let minimumFormatVersion = 4

    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String
    var items: [ItemDTO]
    var orders: [OrderDTO]
    var batches: [BatchDTO]
    /// 店铺设置属于配置，但换机后凭证抬头不该丢，所以一并带走
    var shopSettings: ShopSettings?

    struct ItemDTO: Codable {
        var serialNumber: String
        var modelName: String
        var chip: String
        var memory: String
        var storage: String
        var color: String
        var condition: String
        var status: String
        /// 人民币进价
        var costCNY: String
        /// 1 元人民币 = N 缅币
        var exchangeRate: String
        /// 缅币运费
        var shipping: String
        /// 缅币总进价
        var landedCost: String
        var listPrice: String
        var soldPrice: String
        /// 电池健康与循环次数为格式版本 4 的可选补充字段，缺省按未检测处理
        var batteryHealth: Int?
        var batteryCycles: Int?
        var inboundAt: Date
        var soldAt: Date?
        var orderNumber: String?
        var batchName: String?
        var photoBase64: String?
    }

    struct OrderDTO: Codable {
        var number: String
        var customerName: String
        var customerContact: String
        var subtotal: String
        var total: String
        var profit: String
        var discount: String
        var rounding: String
        var paymentMethod: String
        var createdAt: Date
        var originDeviceID: String
        var voidedAt: Date?
        var itemSerials: [String]
        var sequenceYear: Int
        var sequenceNumber: Int
        var returnedAmount: String
        var returnedCount: Int
    }

    struct BatchDTO: Codable {
        var name: String
        var supplier: String
        var exchangeRate: String
        var totalShipping: String
        var allocation: String
        var createdAt: Date
    }
}

extension Decimal {
    /// 无损十进制字符串，用于持久化
    var plainString: String {
        NSDecimalNumber(decimal: self).stringValue
    }
}

extension String {
    var decimalValue: Decimal {
        Decimal(string: self, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}
