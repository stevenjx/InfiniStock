import Foundation
import SwiftData

/// 一台机器的库存单元。序列号是业务主键，由应用层校验唯一性。
///
/// CloudKit 镜像约束：所有属性必须有默认值或为 optional，关系必须 optional，
/// 且不能声明唯一约束——因此重复序列号拦截只能靠 InventoryService 的查库校验。
@Model
final class Item {
    var serialNumber: String = ""
    var modelName: String = ""
    var chip: String = ""
    var memory: String = ""
    var storage: String = ""
    var color: String = ""

    var conditionRaw: String = ItemCondition.p95.rawValue
    var statusRaw: String = ItemStatus.inStock.rawValue

    // 成本（入库时快照，之后不随汇率浮动）
    var costAmount: Decimal = 0
    var costCurrencyRaw: String = CostCurrency.cny.rawValue
    var exchangeRate: Decimal = 1
    var shippingCNY: Decimal = 0
    var landedCostCNY: Decimal = 0

    var listPriceCNY: Decimal = 0
    var soldPriceCNY: Decimal = 0

    @Attribute(.externalStorage) var photoData: Data?

    var inboundAt: Date = Date()
    var soldAt: Date?

    var order: Order?

    init(
        serialNumber: String,
        modelName: String,
        chip: String = "",
        memory: String = "",
        storage: String = "",
        color: String = "",
        condition: ItemCondition = .p95,
        costAmount: Decimal = 0,
        currency: CostCurrency = .cny,
        exchangeRate: Decimal = 1,
        shippingCNY: Decimal = 0,
        listPriceCNY: Decimal = 0
    ) {
        self.serialNumber = serialNumber
        self.modelName = modelName
        self.chip = chip
        self.memory = memory
        self.storage = storage
        self.color = color
        self.conditionRaw = condition.rawValue
        self.costAmount = costAmount
        self.costCurrencyRaw = currency.rawValue
        self.exchangeRate = exchangeRate
        self.shippingCNY = shippingCNY
        self.landedCostCNY = Money.landedCost(amount: costAmount, rate: exchangeRate, shippingCNY: shippingCNY)
        self.listPriceCNY = listPriceCNY
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .inStock }
        set { statusRaw = newValue.rawValue }
    }

    var condition: ItemCondition {
        get { ItemCondition(rawValue: conditionRaw) ?? .p95 }
        set { conditionRaw = newValue.rawValue }
    }

    var currency: CostCurrency {
        get { CostCurrency(rawValue: costCurrencyRaw) ?? .cny }
        set { costCurrencyRaw = newValue.rawValue }
    }

    /// 单台毛利，仅在已售出时有意义
    var grossProfitCNY: Decimal {
        soldPriceCNY - landedCostCNY
    }

    var specSummary: String {
        [memory, storage, color]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    /// 库龄：入库日到售出日（未售则到今天）的自然日差
    var ageInDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: inboundAt)
        let end = calendar.startOfDay(for: soldAt ?? .now)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    /// 超过该天数仍未售出即视为呆滞
    static let overdueDays = 60

    var isOverdue: Bool {
        status == .inStock && ageInDays >= Self.overdueDays
    }
}
