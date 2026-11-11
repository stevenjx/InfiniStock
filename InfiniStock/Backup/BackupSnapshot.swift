import Foundation

/// 备份快照。金额一律以字符串编码——JSONEncoder 走 Double 会丢精度，
/// 1234.56 存成 1234.5599999999999 这种事在成本账上不能接受。
struct BackupSnapshot: Codable {
    static let currentFormatVersion = 2

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
        var costAmount: String
        var costCurrency: String
        var exchangeRate: String
        var shippingCNY: String
        var landedCostCNY: String
        var listPriceCNY: String
        var soldPriceCNY: String
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
        var subtotalCNY: String
        var totalCNY: String
        var profitCNY: String
        var createdAt: Date
        var originDeviceID: String
        var voidedAt: Date?
        var itemSerials: [String]
        // 以下字段为格式版本 2 新增，可选以兼容早期备份
        var discountCNY: String?
        var roundingCNY: String?
        var paymentMethod: String?
        var sequenceYear: Int?
        var sequenceNumber: Int?
    }

    struct BatchDTO: Codable {
        var name: String
        var supplier: String
        var currency: String
        var exchangeRate: String
        var totalShippingCNY: String
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