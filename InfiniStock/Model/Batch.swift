import Foundation
import SwiftData

enum AllocationMethod: String, CaseIterable, Identifiable {
    case byValue = "按货值分摊"
    case byCount = "按台数均摊"

    var id: String { rawValue }
}

/// 一批进货。汇率与运费在批次上锁定，逐台成本由分摊算出。
@Model
final class Batch {
    var name: String = ""
    var supplier: String = ""
    var currencyRaw: String = CostCurrency.usd.rawValue
    var exchangeRate: Decimal = 1
    var totalShippingCNY: Decimal = 0
    var allocationRaw: String = AllocationMethod.byValue.rawValue
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Item.batch)
    var items: [Item]? = []

    init() {}

    var currency: CostCurrency {
        get { CostCurrency(rawValue: currencyRaw) ?? .usd }
        set { currencyRaw = newValue.rawValue }
    }

    var allocation: AllocationMethod {
        get { AllocationMethod(rawValue: allocationRaw) ?? .byValue }
        set { allocationRaw = newValue.rawValue }
    }

    var itemList: [Item] { items ?? [] }

    /// 批次内所有机器的落地成本合计（含运费）
    var totalLandedCostCNY: Decimal {
        itemList.reduce(Decimal(0)) { $0 + $1.landedCostCNY }
    }
}
