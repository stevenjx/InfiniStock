import Foundation
import SwiftData

@MainActor
enum OrderService {

    /// 撤销整张单：所有机器回到在库，单据标记作废以备审计。
    /// 条件：这张单没有任何退货记录，否则应使用逐台退货。
    static func void(_ order: Order, in context: ModelContext) throws {
        guard order.voidedAt == nil else { throw OrderError.alreadyVoided(order.number) }
        let items = order.itemList
        guard !items.isEmpty else { throw OrderError.noItems(order.number) }

        for item in items {
            restore(item)
        }
        order.voidedAt = .now
        try context.save()
    }

    /// 部分退货：把指定机器退回库存，单据金额按剩余机器重算。
    ///
    /// 金额规则（必须可解释，否则账对不上）：
    /// - 折扣与抹零按原单比例分摊到每台，退货时连同该台折扣一起退回
    /// - 全部退完时，单据总应收精确归零，不残留分位
    /// - 毛利按剩余机器的实际成本重算，退货不会虚增或虚减毛利
    @discardableResult
    static func returnItems(_ items: [Item], from order: Order, in context: ModelContext) throws -> Decimal {
        guard order.voidedAt == nil else { throw OrderError.alreadyVoided(order.number) }
        guard !items.isEmpty else { throw OrderError.noItems(order.number) }

        let owned = Set(order.itemList.map(\.serialNumber))
        for item in items where !owned.contains(item.serialNumber) {
            throw OrderError.notInOrder(item.serialNumber, order.number)
        }

        let priceBefore = order.itemList.reduce(Decimal(0)) { $0 + $1.soldPriceCNY }
        var refund: Decimal = 0

        for item in items {
            refund += item.soldPriceCNY
            restore(item)
        }

        let remaining = order.itemList
        order.returnedCount += items.count
        order.subtotalCNY = remaining.reduce(Decimal(0)) { $0 + $1.soldPriceCNY }.rounded(2)
        order.returnedAmountCNY += refund.rounded(2)

        // 折扣按剩余货值比例保留；全退时折扣归零
        let discountBase = priceBefore
        if remaining.isEmpty || discountBase == 0 {
            order.discountCNY = 0
            order.roundingCNY = 0
            order.totalCNY = 0
            order.profitCNY = 0
        } else {
            let ratio = (order.subtotalCNY / discountBase).rounded(6)
            order.discountCNY = (order.discountCNY * ratio).rounded(2)
            order.roundingCNY = (order.roundingCNY * ratio).rounded(2)
            let total = (order.subtotalCNY - order.discountCNY - order.roundingCNY).rounded(2)
            let cost = remaining.reduce(Decimal(0)) { $0 + $1.landedCostCNY }
            order.totalCNY = total
            order.profitCNY = (total - cost).rounded(2)
        }

        if remaining.isEmpty {
            order.voidedAt = .now   // 全退等价作废，但保留 returnedCount 以区分
        }

        try context.save()
        return refund.rounded(2)
    }

    /// 机器退回库存并清空成交信息。
    /// 注意：soldAt 保留为退货时间，库龄从入库日重新开始算。
    private static func restore(_ item: Item) {
        item.status = .inStock
        item.soldAt = nil
        item.soldPriceCNY = 0
        item.order = nil
        SpotlightIndexer.index(item)
    }
}