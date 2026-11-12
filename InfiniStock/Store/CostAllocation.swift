import Foundation
import SwiftData

/// 批次运费分摊。核心约束：分摊后各台运费之和必须精确等于批次总运费，
/// 分位误差全部由最后一台吸收，不允许出现"合计对不上"的情况。
@MainActor
enum CostAllocation {

    /// 按批次设定重新分配运费，并锁定汇率到每台机器。
    static func reallocate(_ batch: Batch) {
        let items = batch.itemList.sorted { $0.serialNumber < $1.serialNumber }
        guard !items.isEmpty else { return }

        for item in items {
            item.exchangeRate = batch.exchangeRate
        }

        let total = batch.totalShipping
        var shares: [Decimal]

        switch batch.allocation {
        case .byCount:
            let each = (total / Decimal(items.count)).rounded(2)
            shares = Array(repeating: each, count: items.count)

        case .byValue:
            let bases = items.map { baseCost($0) }
            let sum = bases.reduce(Decimal(0), +)
            if sum > 0 {
                shares = bases.map { (($0 / sum) * total).rounded(2) }
            } else {
                let each = (total / Decimal(items.count)).rounded(2)
                shares = Array(repeating: each, count: items.count)
            }
        }

        apply(shares, to: items, total: total)
    }

    /// 把差额压到最后一台，保证合计精确
    private static func apply(_ shares: [Decimal], to items: [Item], total: Decimal) {
        guard !items.isEmpty else { return }
        let head = shares.dropLast()
        let headSum = head.reduce(Decimal(0), +)
        let tail = total - headSum

        var finalShares = Array(head)
        finalShares.append(tail)

        for (item, shipping) in zip(items, finalShares) {
            item.shipping = shipping
            item.landedCost = Money.landedCost(
                costCNY: item.costCNY,
                rate: item.exchangeRate,
                shipping: shipping
            )
        }
    }

    /// 进价折缅币（不含运费）
    static func baseCost(_ item: Item) -> Decimal {
        (item.costCNY * item.exchangeRate).rounded(2)
    }
}
