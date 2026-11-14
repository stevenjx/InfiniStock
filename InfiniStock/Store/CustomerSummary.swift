import Foundation

/// 客户等级。规则必须可解释，不能拍脑袋：
/// 90 天没回头 → 沉睡；回头 5 次以上或累计消费过 2000 万缅币 → VIP；
/// 只买过 1 次 → 潜力；其余 → 活跃。
enum CustomerTier: String, CaseIterable {
    case vip = "VIP"
    case active = "活跃"
    case potential = "潜力"
    case dormant = "沉睡"

    /// rawValue 是中文，用作分组键；显示走本地化
    var title: LocalizedStringResource {
        switch self {
        case .vip: "VIP"
        case .active: "活跃"
        case .potential: "潜力"
        case .dormant: "沉睡"
        }
    }

    /// VIP 门槛：累计消费 2000 万缅币（约 4–5 台 MacBook）
    static let vipRevenue: Decimal = 20_000_000
    /// 沉睡门槛：超过 90 天没有新单
    static let dormantDays = 90
}

/// 客户视图的聚合口径。客户不是独立实体，而是从有效单据推导出来的：
/// 以「姓名 + 电话」为键，避免同名不同人被合并。
struct CustomerSummary: Identifiable {
    let id: String
    let name: String
    let contact: String
    let orderCount: Int
    let machineCount: Int
    let revenue: Decimal
    let profit: Decimal
    let lastPurchase: Date
    /// 最近一次购买里最靠前的一台型号，用来判断"他还需要什么"
    let lastModel: String
    /// 欠款合计。赊账客户的这一项不该被算进"累计消费"就完事
    let outstanding: Decimal

    var marginRate: Decimal? {
        guard revenue > 0 else { return nil }
        return (profit / revenue * 100).rounded(1)
    }

    var daysSinceLastPurchase: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: lastPurchase)
        let end = calendar.startOfDay(for: .now)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    var tier: CustomerTier {
        if daysSinceLastPurchase > CustomerTier.dormantDays { return .dormant }
        if orderCount >= 5 || revenue >= CustomerTier.vipRevenue { return .vip }
        if orderCount <= 1 { return .potential }
        return .active
    }

    static func build(from orders: [Order]) -> [CustomerSummary] {
        let valid = orders.filter { !$0.isVoided }
        var groups: [String: [Order]] = [:]

        for order in valid {
            let name = order.customerName.trimmingCharacters(in: .whitespaces)
            // 没有姓名的单据不构成客户，但仍计入销售统计
            guard !name.isEmpty else { continue }
            let contact = order.customerContact.trimmingCharacters(in: .whitespaces)
            let key = name + "|" + contact
            groups[key, default: []].append(order)
        }

        return groups.compactMap { key, group -> CustomerSummary? in
            guard let first = group.first else { return nil }
            let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let latest = group.max { $0.createdAt < $1.createdAt } ?? first
            return CustomerSummary(
                id: key,
                name: String(parts.first ?? ""),
                contact: parts.count > 1 ? String(parts[1]) : "",
                orderCount: group.count,
                machineCount: group.reduce(0) { $0 + $1.itemList.count },
                revenue: group.reduce(Decimal(0)) { $0 + $1.total },
                profit: group.reduce(Decimal(0)) { $0 + $1.profit },
                lastPurchase: latest.createdAt,
                lastModel: latest.itemList.first?.modelName ?? "",
                outstanding: group.reduce(Decimal(0)) { $0 + $1.outstanding }
            )
        }
        .sorted { $0.revenue > $1.revenue }
    }
}
