import Foundation
import SwiftData

enum AllocationMethod: String, CaseIterable, Identifiable {
    case byValue = "按货值分摊"
    case byCount = "按台数均摊"

    var id: String { rawValue }
}

/// 一批进货。汇率与缅币运费在批次上锁定，逐台成本由分摊算出。
@Model
final class Batch {
    var name: String = ""
    var supplier: String = ""
    /// 汇率：1 元人民币 = N 缅币
    var exchangeRate: Decimal = 1
    /// 本批缅币总运费
    @Attribute(originalName: "totalShippingCNY") var totalShipping: Decimal = 0
    var allocationRaw: String = AllocationMethod.byValue.rawValue
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Item.batch)
    var items: [Item]? = []

    init() {}

    var allocation: AllocationMethod {
        get { AllocationMethod(rawValue: allocationRaw) ?? .byValue }
        set { allocationRaw = newValue.rawValue }
    }

    var itemList: [Item] { items ?? [] }

    /// 本批缅币总进价
    var totalCost: Decimal {
        itemList.reduce(Decimal(0)) { $0 + $1.landedCost }
    }
}
