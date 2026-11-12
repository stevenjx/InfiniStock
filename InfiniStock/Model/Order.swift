import Foundation
import SwiftData

/// 一张销售单。金额为出库时快照，不随后续改价变化。
@Model
final class Order {
    var number: String = ""
    var customerName: String = ""
    var customerContact: String = ""
    /// 商品小计（各台成交价之和，已含逐台改价）
    var subtotal: Decimal = 0
    /// 折扣 + 抹零合计，正数表示从应收中减去
    var discount: Decimal = 0
    /// 抹零部分，仅用于凭证展示
    var rounding: Decimal = 0
    /// 应收 = 小计 − 折扣
    var total: Decimal = 0
    var profit: Decimal = 0
    var paymentMethodRaw: String = PaymentMethod.cash.rawValue
    var createdAt: Date = Date()
    /// 作废时间；作废单保留以备审计，不会进入统计
    var voidedAt: Date?
    /// 出单设备标识，后续做离线冲突仲裁时按 (createdAt, originDeviceID) 定序
    var originDeviceID: String = ""

    /// 单号序号，与 number 冗余存储，用于取当年最大值而不必解析字符串
    var sequenceYear: Int = 0
    var sequenceNumber: Int = 0

    /// 累计退货金额与台数，仅用于凭证展示；应收与毛利已按净额重算
    var returnedAmount: Decimal = 0
    var returnedCount: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Item.order)
    var items: [Item]? = []

    init() {}

    var itemList: [Item] { items ?? [] }

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .cash }
        set { paymentMethodRaw = newValue.rawValue }
    }

    var isVoided: Bool { voidedAt != nil }

    var hasReturns: Bool { returnedCount > 0 }

    /// 全部机器都已退走（与"手工作废"区分开）
    var isFullyReturned: Bool { isVoided && hasReturns }

    var statusLabel: String {
        if isFullyReturned { return "已全退" }
        if isVoided { return "已作废" }
        if hasReturns { return "部分退货" }
        return "有效"
    }
}

enum OrderError: LocalizedError {
    case alreadyVoided(String)
    case noItems(String)
    case sequenceExhausted(Int)
    case notInOrder(String, String)

    var errorDescription: String? {
        switch self {
        case .alreadyVoided(let number): "单据 \(number) 已作废"
        case .noItems(let number): "单据 \(number) 没有关联机器，无法操作"
        case .sequenceExhausted(let year): "\(year) 年单号已用尽（9999），请检查数据"
        case .notInOrder(let serial, let number): "序列号 \(serial) 不属于单据 \(number)"
        }
    }
}