import Foundation

/// 统计口径集中在一处，纯函数、可验证。界面只负责画。
struct InventoryStatistics {
    struct AgingBucket: Identifiable {
        let id: String
        let label: String
        let count: Int
        let value: Decimal
    }

    /// 每日成交（用于柱状图）。date 已归一到当天零点。
    struct DailyPoint: Identifiable {
        let id: Date
        let date: Date
        let revenue: Decimal
        let profit: Decimal
        let count: Int
    }

    struct PaymentSlice: Identifiable {
        let id: String
        let method: PaymentMethod
        let amount: Decimal
        let count: Int
    }

    /// 单个型号的售速。用来回答「哪一款压住了钱」。
    struct ModelVelocity: Identifiable {
        let id: String
        let model: String
        /// 窗口内售出台数
        let soldCount: Int
        let inStockCount: Int
        let stockValue: Decimal
        /// 按窗口内卖速，现有库存还能卖几天。
        /// nil 表示窗口内一台没卖出去——那不是 0 天，是卖不动。
        let daysOfSupply: Int?
    }

    let inStockCount: Int
    let stockCostValue: Decimal
    let stockListedValue: Decimal
    let todayCount: Int
    let todayRevenue: Decimal
    let todayProfit: Decimal
    let agingBuckets: [AgingBucket]
    let overdueItems: [Item]
    let dailyPoints: [DailyPoint]
    let paymentSlices: [PaymentSlice]
    let lowMarginItems: [Item]
    /// 在库且电池偏弱（健康 < 80% 或循环 ≥ 800）
    let weakBatteryItems: [Item]
    /// 有效单据里还没收回来的钱
    let outstandingAmount: Decimal
    let outstandingOrderCount: Int

    // MARK: - 周转

    /// 售速统计窗口（天）。固定 30 天：够长到能看出趋势，够短到跟得上行情
    let windowDays: Int
    /// 窗口内售出台数
    let soldInWindow: Int
    /// 现有库存按窗口内售速还能卖几天；窗口内无成交时为 nil
    let daysOfSupply: Int?
    /// 库龄超期机器的占用成本
    let slowMovingValue: Decimal
    let slowMovingCount: Int
    /// 按风险排序的型号售速（卖不动的排前面）
    let velocity: [ModelVelocity]

    var overdueValue: Decimal {
        overdueItems.reduce(Decimal(0)) { $0 + $1.landedCost }
    }

    var stockPotentialProfit: Decimal {
        stockListedValue - stockCostValue
    }

    /// 今日毛利率，无成交时返回 nil
    var todayMarginRate: Decimal? {
        guard todayRevenue > 0 else { return nil }
        return (todayProfit / todayRevenue * 100).rounded(1)
    }

    /// 昨日销售额，用于 KPI 卡片的环比
    var yesterdayRevenue: Decimal {
        dailyPoints.count >= 2 ? dailyPoints[dailyPoints.count - 2].revenue : 0
    }

    /// 近 N 天合计，用于图表下方摘要
    func summary(days: Int) -> (revenue: Decimal, profit: Decimal) {
        let slice = dailyPoints.suffix(days)
        return (
            slice.reduce(Decimal(0)) { $0 + $1.revenue },
            slice.reduce(Decimal(0)) { $0 + $1.profit }
        )
    }

    init(
        items: [Item],
        orders: [Order] = [],
        now: Date = .now,
        calendar: Calendar = .current,
        dayCount: Int = 7,
        windowDays: Int = 30
    ) {
        let inStock = items.filter { $0.status == .inStock }
        inStockCount = inStock.count
        stockCostValue = inStock.reduce(Decimal(0)) { $0 + $1.landedCost }
        stockListedValue = inStock.reduce(Decimal(0)) { $0 + $1.listPrice }

        let soldToday = items.filter { item in
            guard item.status == .sold, let soldAt = item.soldAt else { return false }
            return calendar.isDate(soldAt, inSameDayAs: now)
        }
        todayCount = soldToday.count

        // 金额以单据为准：折扣与抹零只记在单据上，按机器累加会虚报收入。
        // 没有单据的历史数据（早期版本）才退回按机器累加。
        let validOrders = orders.filter { !$0.isVoided }
        let validOrdersToday = validOrders.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
        if validOrdersToday.isEmpty {
            todayRevenue = soldToday.reduce(Decimal(0)) { $0 + $1.soldPrice }
            todayProfit = soldToday.reduce(Decimal(0)) { $0 + $1.grossProfit }
        } else {
            todayRevenue = validOrdersToday.reduce(Decimal(0)) { $0 + $1.total }
            todayProfit = validOrdersToday.reduce(Decimal(0)) { $0 + $1.profit }
        }

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
                value: matched.reduce(Decimal(0)) { $0 + $1.landedCost }
            )
        }

        overdueItems = inStock
            .filter { $0.ageInDays >= Item.overdueDays }
            .sorted { $0.ageInDays > $1.ageInDays }

        // 近 N 天：按自然日补零，保证柱状图 X 轴连续
        var points: [DailyPoint] = []
        for offset in stride(from: dayCount - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(
                byAdding: .day, value: -offset,
                to: calendar.startOfDay(for: now)
            ) else { continue }
            let dayOrders = validOrders.filter { calendar.isDate($0.createdAt, inSameDayAs: dayStart) }
            points.append(DailyPoint(
                id: dayStart,
                date: dayStart,
                revenue: dayOrders.reduce(Decimal(0)) { $0 + $1.total },
                profit: dayOrders.reduce(Decimal(0)) { $0 + $1.profit },
                count: dayOrders.count
            ))
        }
        dailyPoints = points

        paymentSlices = PaymentMethod.allCases.compactMap { method in
            let matched = validOrders.filter { $0.paymentMethod == method }
            guard !matched.isEmpty else { return nil }
            return PaymentSlice(
                id: method.rawValue,
                method: method,
                amount: matched.reduce(Decimal(0)) { $0 + $1.total },
                count: matched.count
            )
        }

        // 电池偏弱：在库且健康度低于阈值或循环次数偏高
        weakBatteryItems = inStock
            .filter(\.isBatteryWeak)
            .sorted { $0.batteryHealth < $1.batteryHealth }

        // 应收未收：只算有效单据，作废单的欠款没有意义
        let owing = validOrders.filter(\.isOutstanding)
        outstandingAmount = owing.reduce(Decimal(0)) { $0 + $1.outstanding }
        outstandingOrderCount = owing.count

        // 低于成本：在库且标价低于总进价
        lowMarginItems = inStock
            .filter { $0.listPrice > 0 && $0.listPrice < $0.landedCost }
            .sorted { ($0.listPrice - $0.landedCost) < ($1.listPrice - $1.landedCost) }

        // MARK: 周转

        self.windowDays = windowDays
        let windowStart = calendar.date(
            byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: now)
        ) ?? now

        // 用 soldAt 而不是单据日期：部分退货后机器回到在库，soldAt 会被清空，
        // 它算不算「卖过」应该由当前状态决定，而不是由历史单据决定。
        let soldInWindowItems = items.filter { item in
            guard item.status == .sold, let soldAt = item.soldAt else { return false }
            return soldAt >= windowStart
        }
        soldInWindow = soldInWindowItems.count

        daysOfSupply = soldInWindow > 0
            ? Int((Double(inStockCount) * Double(windowDays) / Double(soldInWindow)).rounded())
            : nil

        slowMovingValue = overdueItems.reduce(Decimal(0)) { $0 + $1.landedCost }
        slowMovingCount = overdueItems.count

        // 按型号：窗口内卖出多少、还压着多少台、这些货还能卖几天。
        // 排序把「卖不动」的型号顶到最前面——那是最该降价或清仓的。
        let models = Set(items.map(\.modelName)).filter { !$0.isEmpty }
        velocity = models.compactMap { model in
            let stock = inStock.filter { $0.modelName == model }
            let sold = soldInWindowItems.filter { $0.modelName == model }
            guard !stock.isEmpty || !sold.isEmpty else { return nil }
            let days: Int? = sold.isEmpty
                ? nil
                : Int((Double(stock.count) * Double(windowDays) / Double(sold.count)).rounded())
            return ModelVelocity(
                id: model,
                model: model,
                soldCount: sold.count,
                inStockCount: stock.count,
                stockValue: stock.reduce(Decimal(0)) { $0 + $1.landedCost },
                daysOfSupply: days
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.daysOfSupply, rhs.daysOfSupply) {
            case (nil, nil): break
            case (nil, _): return true
            case (_, nil): return false
            case let (l?, r?): if l != r { return l > r }
            }
            // 同档时占用资金多的排前面，最后用型号名兜底保证顺序稳定
            if lhs.stockValue != rhs.stockValue { return lhs.stockValue > rhs.stockValue }
            return lhs.model < rhs.model
        }
    }
}