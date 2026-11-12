import Foundation

/// 报表的时间范围。边界一律是「左闭右开」，避免月末最后一单被算进下个月。
enum ReportRange: String, CaseIterable, Identifiable {
    case thisMonth = "本月"
    case lastMonth = "上月"
    case last30 = "近 30 天"
    case thisYear = "今年"

    var id: String { rawValue }

    func bounds(now: Date = .now, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)

        switch self {
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? today
            return (start, end)

        case .lastMonth:
            let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
            return (start, thisMonth)

        case .last30:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            return (start, end)

        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? today
            return (start, end)
        }
    }
}

/// 一个期间的经营结果。纯函数，不碰界面，可被 verify.sh 直接断言。
///
/// 口径与仪表盘同源：只统计有效单据（作废单排除），金额以单据为准，
/// 折扣与退货都已经体现在 order.total / order.profit 里，这里不再二次扣减。
struct PeriodReport {
    struct ModelSlice: Identifiable {
        let id: String
        let model: String
        let count: Int
        let revenue: Decimal
        let profit: Decimal

        var marginRate: Decimal? {
            guard revenue > 0 else { return nil }
            return (profit / revenue * 100).rounded(1)
        }
    }

    struct DayPoint: Identifiable {
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

    let start: Date
    let end: Date
    let orderCount: Int
    let machineCount: Int
    /// 成交额（已扣折扣与退货）
    let revenue: Decimal
    /// 实际收到的钱
    let collected: Decimal
    /// 还没收到的钱
    let outstanding: Decimal
    let cost: Decimal
    let profit: Decimal
    let byModel: [ModelSlice]
    let byPayment: [PaymentSlice]
    let byDay: [DayPoint]

    var marginRate: Decimal? {
        guard revenue > 0 else { return nil }
        return (profit / revenue * 100).rounded(1)
    }

    var averageOrder: Decimal {
        guard orderCount > 0 else { return 0 }
        return (revenue / Decimal(orderCount)).rounded(0)
    }

    var averageTicket: Decimal {
        guard machineCount > 0 else { return 0 }
        return (revenue / Decimal(machineCount)).rounded(0)
    }

    init(orders: [Order], start: Date, end: Date, calendar: Calendar = .current) {
        self.start = start
        self.end = end

        let inRange = orders.filter { order in
            guard !order.isVoided else { return false }
            return order.createdAt >= start && order.createdAt < end
        }

        orderCount = inRange.count
        revenue = inRange.reduce(Decimal(0)) { $0 + $1.total }
        collected = inRange.reduce(Decimal(0)) { $0 + $1.collected }
        outstanding = inRange.reduce(Decimal(0)) { $0 + $1.outstanding }
        cost = inRange.reduce(Decimal(0)) { total, order in
            total + order.itemList.reduce(Decimal(0)) { $0 + $1.landedCost }
        }
        profit = inRange.reduce(Decimal(0)) { $0 + $1.profit }
        machineCount = inRange.reduce(0) { $0 + $1.itemList.count }

        // 型号维度：按成交价归集，退货的机器已从 itemList 里摘掉
        var modelGroups: [String: (count: Int, revenue: Decimal, profit: Decimal)] = [:]
        for order in inRange {
            for item in order.itemList {
                let key = item.modelName.isEmpty ? "未命名型号" : item.modelName
                var entry = modelGroups[key] ?? (0, 0, 0)
                entry.count += 1
                entry.revenue += item.soldPrice
                entry.profit += item.grossProfit
                modelGroups[key] = entry
            }
        }
        byModel = modelGroups
            .map { ModelSlice(id: $0.key, model: $0.key, count: $0.value.count,
                              revenue: $0.value.revenue, profit: $0.value.profit) }
            .sorted { $0.profit > $1.profit }

        byPayment = PaymentMethod.allCases.compactMap { method in
            let matched = inRange.filter { $0.paymentMethod == method }
            guard !matched.isEmpty else { return nil }
            return PaymentSlice(
                id: method.rawValue,
                method: method,
                amount: matched.reduce(Decimal(0)) { $0 + $1.total },
                count: matched.count
            )
        }

        // 按自然日补零，图表 X 轴才不会跳
        var points: [DayPoint] = []
        var cursor = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        while cursor < lastDay {
            let dayOrders = inRange.filter { calendar.isDate($0.createdAt, inSameDayAs: cursor) }
            points.append(DayPoint(
                id: cursor,
                date: cursor,
                revenue: dayOrders.reduce(Decimal(0)) { $0 + $1.total },
                profit: dayOrders.reduce(Decimal(0)) { $0 + $1.profit },
                count: dayOrders.count
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        byDay = points
    }

    /// 导出给会计看的明细：一行一台机器，带单号与日期。
    static func csv(_ report: PeriodReport, orders: [Order], calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var rows: [String] = [
            "单号,日期,客户,型号,序列号,成交价(缅币),总进价(缅币),毛利(缅币),收款方式,应收,实收",
        ]

        let inRange = orders
            .filter { !$0.isVoided && $0.createdAt >= report.start && $0.createdAt < report.end }
            .sorted { $0.createdAt < $1.createdAt }

        for order in inRange {
            for item in order.itemList.sorted(by: { $0.serialNumber < $1.serialNumber }) {
                rows.append([
                    order.number,
                    formatter.string(from: order.createdAt),
                    escape(order.customerName),
                    escape(item.modelName),
                    item.serialNumber,
                    item.soldPrice.plainString,
                    item.landedCost.plainString,
                    item.grossProfit.plainString,
                    order.paymentMethod.rawValue,
                    order.total.plainString,
                    order.collected.plainString,
                ].joined(separator: ","))
            }
        }

        // 加 BOM，否则 Excel 打开中文是乱码
        return "\u{FEFF}" + rows.joined(separator: "\r\n")
    }

    private static func escape(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
