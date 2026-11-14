import Foundation
import SwiftData

enum AllocationMethod: String, CaseIterable, Identifiable {
    case byValue = "按货值分摊"
    case byCount = "按台数均摊"

    var id: String { rawValue }

    /// rawValue 是中文，存进批次作为记录值；显示走本地化
    var title: LocalizedStringResource {
        switch self {
        case .byValue: "按货值分摊"
        case .byCount: "按台数均摊"
        }
    }
}

/// 批次推进到哪一步。判定只看数据，不存状态字段，避免和实际分摊结果打架。
enum BatchStage: String {
    case empty = "待入库"
    case pending = "待分摊"
    case settled = "已入库"

    /// rawValue 是中文，用作匹配键；显示走本地化
    var title: LocalizedStringResource {
        switch self {
        case .empty: "待入库"
        case .pending: "待分摊"
        case .settled: "已入库"
        }
    }
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

    /// 已分摊到各台的运费合计
    var allocatedShipping: Decimal {
        itemList.reduce(Decimal(0)) { $0 + $1.shipping }
    }

    var stage: BatchStage {
        if itemList.isEmpty { return .empty }
        // 分摊算法保证尾差归最后一台，所以这里的差额只可能是"还没分摊"
        if (totalShipping - allocatedShipping).magnitude > Decimal(string: "0.01")! {
            return .pending
        }
        return .settled
    }
}
