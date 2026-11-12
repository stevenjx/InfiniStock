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

    /// 电池健康百分比；0 表示未检测（老数据与快速录入都是 0）
    var batteryHealth: Int = 0
    /// 电池循环次数；0 表示未检测
    var batteryCycles: Int = 0

    // 成本（入库时快照，之后不随汇率浮动）
    /// 人民币进价——国内卖家的报价
    @Attribute(originalName: "costAmount") var costCNY: Decimal = 0
    /// 汇率：1 元人民币 = N 缅币。快照在机器上，之后改汇率不动老货
    var exchangeRate: Decimal = 1
    /// 缅币运费（批次分摊到单台）
    @Attribute(originalName: "shippingCNY") var shipping: Decimal = 0
    /// 缅币总进价 = 人民币进价 × 汇率 + 运费
    @Attribute(originalName: "landedCostCNY") var landedCost: Decimal = 0

    /// 缅币标价
    @Attribute(originalName: "listPriceCNY") var listPrice: Decimal = 0
    /// 缅币成交价
    @Attribute(originalName: "soldPriceCNY") var soldPrice: Decimal = 0

    @Attribute(.externalStorage) var photoData: Data?

    var inboundAt: Date = Date()
    var soldAt: Date?

    var order: Order?
    var batch: Batch?

    init(
        serialNumber: String,
        modelName: String,
        chip: String = "",
        memory: String = "",
        storage: String = "",
        color: String = "",
        condition: ItemCondition = .p95,
        costCNY: Decimal = 0,
        exchangeRate: Decimal = 1,
        shipping: Decimal = 0,
        listPrice: Decimal = 0,
        batteryHealth: Int = 0,
        batteryCycles: Int = 0
    ) {
        self.serialNumber = serialNumber
        self.modelName = modelName
        self.chip = chip
        self.memory = memory
        self.storage = storage
        self.color = color
        self.conditionRaw = condition.rawValue
        self.batteryHealth = batteryHealth
        self.batteryCycles = batteryCycles
        self.costCNY = costCNY
        self.exchangeRate = exchangeRate
        self.shipping = shipping
        self.landedCost = Money.landedCost(costCNY: costCNY, rate: exchangeRate, shipping: shipping)
        self.listPrice = listPrice
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .inStock }
        set { statusRaw = newValue.rawValue }
    }

    var condition: ItemCondition {
        get { ItemCondition(rawValue: conditionRaw) ?? .p95 }
        set { conditionRaw = newValue.rawValue }
    }

    /// 单台毛利（缅币），仅在已售出时有意义
    var grossProfit: Decimal {
        soldPrice - landedCost
    }

    /// 人民币进价折缅币（不含运费），用于成本构成展示
    var costMMK: Decimal {
        (costCNY * exchangeRate).rounded(2)
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

    // MARK: - 电池

    /// 低于该健康度视为议价点
    static let weakHealth = 80
    /// 超过该循环次数视为电池损耗明显
    static let highCycles = 800

    var hasBatteryData: Bool {
        batteryHealth > 0 || batteryCycles > 0
    }

    /// 健康度偏低或循环次数偏高——二手 MacBook 的主要压价理由
    var isBatteryWeak: Bool {
        (batteryHealth > 0 && batteryHealth < Self.weakHealth) || batteryCycles >= Self.highCycles
    }

    var batteryHealthText: String {
        batteryHealth > 0 ? "\(batteryHealth)%" : "—"
    }

    var batteryCyclesText: String {
        batteryCycles > 0 ? "\(batteryCycles) 次" : "—"
    }
}
