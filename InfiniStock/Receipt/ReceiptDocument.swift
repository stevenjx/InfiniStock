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

    let shopName: String
    let shopPhone: String
    let shopAddress: String
    let subtotal: Decimal
    let discount: Decimal
    let rounding: Decimal
    let total: Decimal
    let paymentMethod: String
    let warrantyDays: Int
    let footnote: String

    init(order: Order, settings: ShopSettings = .load()) {
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
        shopName = settings.shopName
        shopPhone = settings.phone
        shopAddress = settings.address
        subtotal = order.subtotalCNY
        discount = order.discountCNY
        rounding = order.roundingCNY
        total = order.totalCNY
        paymentMethod = order.paymentMethod.rawValue
        warrantyDays = settings.warrantyDays
        footnote = settings.footnote
    }

    /// 供验证与预览构造
    init(
        number: String, issuedAt: Date, customerName: String, customerContact: String,
        lines: [Line], shopName: String = "", shopPhone: String = "", shopAddress: String = "",
        subtotal: Decimal? = nil, discount: Decimal = 0, rounding: Decimal = 0,
        total: Decimal? = nil, paymentMethod: String = PaymentMethod.cash.rawValue,
        warrantyDays: Int = 7, footnote: String = ""
    ) {
        self.number = number
        self.issuedAt = issuedAt
        self.customerName = customerName
        self.customerContact = customerContact
        self.lines = lines
        self.shopName = shopName
        self.shopPhone = shopPhone
        self.shopAddress = shopAddress
        let computed = lines.reduce(Decimal(0)) { $0 + $1.price }
        self.subtotal = subtotal ?? computed
        self.discount = discount
        self.rounding = rounding
        self.total = total ?? (self.subtotal - discount - rounding)
        self.paymentMethod = paymentMethod
        self.warrantyDays = warrantyDays
        self.footnote = footnote
    }
}