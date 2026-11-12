import Foundation

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

    var marginRate: Decimal? {
        guard revenue > 0 else { return nil }
        return (profit / revenue * 100).rounded(1)
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
            return CustomerSummary(
                id: key,
                name: String(parts.first ?? ""),
                contact: parts.count > 1 ? String(parts[1]) : "",
                orderCount: group.count,
                machineCount: group.reduce(0) { $0 + $1.itemList.count },
                revenue: group.reduce(Decimal(0)) { $0 + $1.totalCNY },
                profit: group.reduce(Decimal(0)) { $0 + $1.profitCNY },
                lastPurchase: group.map(\.createdAt).max() ?? first.createdAt
            )
        }
        .sorted { $0.revenue > $1.revenue }
    }
}