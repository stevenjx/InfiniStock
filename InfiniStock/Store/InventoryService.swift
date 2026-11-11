import Foundation
import SwiftData

enum InventoryError: LocalizedError {
    case emptySerial
    case emptyModel
    case duplicateSerial(String)
    case notInStock(String)
    case emptySelection
    case invalidAmount(String)

    var errorDescription: String? {
        switch self {
        case .emptySerial: "序列号不能为空"
        case .emptyModel: "型号不能为空"
        case .duplicateSerial(let serial): "序列号 \(serial) 已入库，本次录入被拦截"
        case .notInStock(let serial): "序列号 \(serial) 不在库，无法出库"
        case .emptySelection: "请先选择要出库的机器"
        case .invalidAmount(let field): "\(field) 不是有效数字"
        }
    }
}

/// 入库表单的原始输入，数字保持字符串以便逐字段报错。
struct IntakeDraft {
    var serialNumber = ""
    var modelName = ""
    var chip = ""
    var memory = ""
    var storage = ""
    var color = ""
    var condition: ItemCondition = .p95
    var costAmount = ""
    var currency: CostCurrency = .cny
    var exchangeRate = "1"
    var shippingCNY = "0"
    var listPriceCNY = ""

    var previewLandedCost: Decimal {
        Money.landedCost(
            amount: Money.parse(costAmount) ?? 0,
            rate: Money.parse(exchangeRate) ?? 1,
            shippingCNY: Money.parse(shippingCNY) ?? 0
        )
    }
}

@MainActor
enum InventoryService {

    static func normalize(_ serial: String) -> String {
        serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func serialExists(_ serial: String, in context: ModelContext) -> Bool {
        let key = normalize(serial)
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.serialNumber == key })
        descriptor.fetchLimit = 1
        return !((try? context.fetch(descriptor)) ?? []).isEmpty
    }

    @discardableResult
    static func intake(_ draft: IntakeDraft, in context: ModelContext) throws -> Item {
        let serial = normalize(draft.serialNumber)
        guard !serial.isEmpty else { throw InventoryError.emptySerial }
        guard !normalize(draft.modelName).isEmpty else { throw InventoryError.emptyModel }
        guard !serialExists(serial, in: context) else { throw InventoryError.duplicateSerial(serial) }

        let cost = try amount(draft.costAmount, field: "进价", fallback: 0)
        let rate = try amount(draft.exchangeRate, field: "汇率", fallback: 1)
        let shipping = try amount(draft.shippingCNY, field: "运费", fallback: 0)
        let listPrice = try amount(draft.listPriceCNY, field: "标价", fallback: 0)

        let item = Item(
            serialNumber: serial,
            modelName: draft.modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            chip: draft.chip,
            memory: draft.memory,
            storage: draft.storage,
            color: draft.color,
            condition: draft.condition,
            costAmount: cost,
            currency: draft.currency,
            exchangeRate: rate,
            shippingCNY: shipping,
            listPriceCNY: listPrice
        )
        context.insert(item)
        try context.save()
        return item
    }

    /// 出库：校验在库 → 写成交价与时间 → 生成订单。单价缺省时用各机标价。
    @discardableResult
    static func sell(
        items: [Item],
        unitPrice: Decimal?,
        customerName: String,
        customerContact: String,
        in context: ModelContext
    ) throws -> Order {
        guard !items.isEmpty else { throw InventoryError.emptySelection }
        for item in items where item.status != .inStock {
            throw InventoryError.notInStock(item.serialNumber)
        }

        let order = Order()
        order.number = OrderNumberFactory.next()
        order.customerName = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        order.customerContact = customerContact.trimmingCharacters(in: .whitespacesAndNewlines)
        order.createdAt = .now
        order.originDeviceID = DeviceIdentity.current
        context.insert(order)

        var total: Decimal = 0
        var profit: Decimal = 0
        for item in items {
            item.status = .sold
            item.soldAt = .now
            item.soldPriceCNY = unitPrice ?? item.listPriceCNY
            item.order = order
            total += item.soldPriceCNY
            profit += item.soldPriceCNY - item.landedCostCNY
        }

        order.totalCNY = total.rounded(2)
        order.profitCNY = profit.rounded(2)

        try context.save()
        return order
    }

    private static func amount(_ text: String, field: String, fallback: Decimal) throws -> Decimal {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return fallback }
        guard let value = Money.parse(trimmed) else { throw InventoryError.invalidAmount(field) }
        return value
    }
}

enum DeviceIdentity {
    private static let key = "infinistock.deviceID"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}
