import Foundation

/// 给客户看的销售凭证数据。刻意不包含进价与毛利——那是内部数据，不能出现在凭证上。
struct ReceiptDocument {
    struct Line: Identifiable {
        let id = UUID()
        let modelName: String
        let serialNumber: String
        let spec: String
        let condition: String
        let price: Decimal
    }

    let number: String
    let issuedAt: Date
    let customerName: String
    let customerContact: String
    let lines: [Line]

    var total: Decimal {
        lines.reduce(Decimal(0)) { $0 + $1.price }
    }

    init(order: Order) {
        number = order.number
        issuedAt = order.createdAt
        customerName = order.customerName
        customerContact = order.customerContact
        lines = order.itemList
            .sorted { $0.serialNumber < $1.serialNumber }
            .map { item in
                Line(
                    modelName: item.modelName,
                    serialNumber: item.serialNumber,
                    spec: [item.memory, item.storage].filter { !$0.isEmpty }.joined(separator: " "),
                    condition: item.condition.rawValue,
                    price: item.soldPriceCNY
                )
            }
    }

    /// 供验证与预览构造
    init(number: String, issuedAt: Date, customerName: String, customerContact: String, lines: [Line]) {
        self.number = number
        self.issuedAt = issuedAt
        self.customerName = customerName
        self.customerContact = customerContact
        self.lines = lines
    }
}
