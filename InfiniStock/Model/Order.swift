import Foundation
import SwiftData

/// 一张销售单。金额为出库时快照，不随后续改价变化。
@Model
final class Order {
    var number: String = ""
    var customerName: String = ""
    var customerContact: String = ""
    /// 商品小计（各台成交价之和，已含逐台改价）
    var subtotalCNY: Decimal = 0
    /// 折扣 + 抹零合计，正数表示从应收中减去
    var discountCNY: Decimal = 0
    /// 抹零部分，仅用于凭证展示
    var roundingCNY: Decimal = 0
    /// 应收 = 小计 − 折扣
    var totalCNY: Decimal = 0
    var profitCNY: Decimal = 0
    var paymentMethodRaw: String = PaymentMethod.cash.rawValue
    var createdAt: Date = Date()
    /// 作废时间；作废单保留以备审计，不会进入统计
    var voidedAt: Date?
    /// 出单设备标识，后续做离线冲突仲裁时按 (createdAt, originDeviceID) 定序
    var originDeviceID: String = ""

    /// 单号序号，与 number 冗余存储，用于取当年最大值而不必解析字符串
    var sequenceYear: Int = 0
    var sequenceNumber: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Item.order)
    var items: [Item]? = []

    init() {}

    var itemList: [Item] { items ?? [] }

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .cash }
        set { paymentMethodRaw = newValue.rawValue }
    }

    var isVoided: Bool { voidedAt != nil }
}

enum OrderError: LocalizedError {
    case alreadyVoided(String)
    case noItems(String)
    case sequenceExhausted(Int)

    var errorDescription: String? {
        switch self {
        case .alreadyVoided(let number): "单据 \(number) 已作废"
        case .noItems(let number): "单据 \(number) 没有关联机器，无法操作"
        case .sequenceExhausted(let year): "\(year) 年单号已用尽（9999），请检查数据"
        }
    }
}