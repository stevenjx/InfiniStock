import Foundation
import SwiftData

/// 一张销售单。金额为出库时快照，不随后续改价变化。
@Model
final class Order {
    var number: String = ""
    var customerName: String = ""
    var customerContact: String = ""
    var totalCNY: Decimal = 0
    var profitCNY: Decimal = 0
    var createdAt: Date = Date()
    /// 出单设备标识，后续做离线冲突仲裁时按 (createdAt, originDeviceID) 定序
    var originDeviceID: String = ""

    @Relationship(deleteRule: .nullify, inverse: \Item.order)
    var items: [Item]? = []

    init() {}

    var itemList: [Item] { items ?? [] }
}

enum OrderNumberFactory {
    static func next() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = String(format: "%03d", Int.random(in: 0...999))
        return "SO-\(formatter.string(from: .now))-\(suffix)"
    }
}
