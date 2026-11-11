import Foundation

/// 统计口径集中在一处，纯函数、可验证。界面只负责画。
struct InventoryStatistics {
    struct AgingBucket: Identifiable {
        let id: String
        let label: String
        let count: Int
        let value: Decimal
    }

    let inStockCount: Int
    let stockCostValue: Decimal
    let stockListedValue: Decimal
    let todayCount: Int
    let todayRevenue: Decimal
    let todayProfit: Decimal
    let agingBuckets: [AgingBucket]
    let overdueItems: [Item]

    var overdueValue: Decimal {
        overdueItems.reduce(Decimal(0)) { $0 + $1.landedCostCNY }
    }

    var stockPotentialProfit: Decimal {
        stockListedValue - stockCostValue
    }

    /// 今日毛利率，无成交时返回 nil
    var todayMarginRate: Decimal? {
        guard todayRevenue > 0 else { return nil }
        return (todayProfit / todayRevenue * 100).rounded(1)
    }

    init(items: [Item], now: Date = .now, calendar: Calendar = .current) {
        let inStock = items.filter { $0.status == .inStock }
        inStockCount = inStock.count
        stockCostValue = inStock.reduce(Decimal(0)) { $0 + $1.landedCostCNY }
        stockListedValue = inStock.reduce(Decimal(0)) { $0 + $1.listPriceCNY }

        let soldToday = items.filter { item in
            guard item.status == .sold, let soldAt = item.soldAt else { return false }
            return calendar.isDate(soldAt, inSameDayAs: now)
        }
        todayCount = soldToday.count
        todayRevenue = soldToday.reduce(Decimal(0)) { $0 + $1.soldPriceCNY }
        todayProfit = soldToday.reduce(Decimal(0)) { $0 + $1.grossProfitCNY }

        let buckets: [(String, ClosedRange<Int>)] = [
            ("0-30 天", 0...30),
            ("31-60 天", 31...60),
            ("61-90 天", 61...90),
            ("90 天以上", 91...Int.max),
        ]
        agingBuckets = buckets.map { label, range in
            let matched = inStock.filter { range.contains($0.ageInDays) }
            return AgingBucket(
                id: label,
                label: label,
                count: matched.count,
                value: matched.reduce(Decimal(0)) { $0 + $1.landedCostCNY }
            )
        }

        overdueItems = inStock
            .filter { $0.ageInDays >= Item.overdueDays }
            .sorted { $0.ageInDays > $1.ageInDays }
    }
}
