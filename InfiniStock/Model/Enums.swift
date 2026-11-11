import Foundation

// MARK: - 状态

enum ItemStatus: String, CaseIterable, Identifiable {
    case inStock
    case sold
    case locked

    var id: String { rawValue }

    var label: String {
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
}

// MARK: - 进价币种

enum CostCurrency: String, CaseIterable, Identifiable {
    case cny = "CNY"
    case usd = "USD"
    case hkd = "HKD"
    case jpy = "JPY"
    case eur = "EUR"

    var id: String { rawValue }

    /// 默认汇率（原币 → 人民币），仅作为录入时的初始值，需人工确认
    var defaultRate: Decimal {
        switch self {
        case .cny: 1
        case .usd: 7.1
        case .hkd: 0.92
        case .jpy: 0.048
        case .eur: 7.8
        }
    }
}
