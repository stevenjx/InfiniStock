import Foundation

// MARK: - 状态

enum ItemStatus: String, CaseIterable, Identifiable {
    case inStock
    case sold
    case locked

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .inStock: "在库"
        case .sold: "已售"
        case .locked: "锁定"
        }
    }
}

// MARK: - 成色

enum ItemCondition: String, CaseIterable, Identifiable {
    case brandNew = "全新"
    case p99 = "99新"
    case p95 = "95新"
    case p90 = "9成新"
    case p80 = "8成新"
    case below = "7成新以下"
    var id: String { rawValue }

    /// rawValue 是中文，存进机器作为记录值；显示走本地化
    var label: LocalizedStringResource {
        switch self {
        case .brandNew: "全新"
        case .p99: "99新"
        case .p95: "95新"
        case .p90: "9成新"
        case .p80: "8成新"
        case .below: "7成新以下"
        }
    }
}
