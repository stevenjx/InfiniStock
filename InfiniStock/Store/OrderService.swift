import Foundation
import SwiftData

enum OrderError: LocalizedError {
    case alreadyVoided(String)
    case noItems(String)

    var errorDescription: String? {
        switch self {
        case .alreadyVoided(let number): "单据 \(number) 已作废"
        case .noItems(let number): "单据 \(number) 没有关联机器，无法作废"
        }
    }
}

@MainActor
enum OrderService {

    /// 撤销销售单：机器回到在库、清空成交信息，单据本身保留并标记作废以备审计。
    /// 统计完全由 item.status 派生，所以撤销后销售额与库存会自动回到正确值。
    static func void(_ order: Order, in context: ModelContext) throws {
        guard order.voidedAt == nil else { throw OrderError.alreadyVoided(order.number) }
        let items = order.itemList
        guard !items.isEmpty else { throw OrderError.noItems(order.number) }

        for item in items {
            item.status = .inStock
            item.soldAt = nil
            item.soldPriceCNY = 0
            item.order = nil
            SpotlightIndexer.index(item)
        }
        order.voidedAt = .now
        try context.save()
    }
}
