import Foundation
import SwiftData

enum InventoryError: LocalizedError {
    case emptySerial
    case emptyModel
    case duplicateSerial(String)
    case notInStock(String)
    case emptySelection
    case invalidAmount(String)
    case invalidDiscount
    case discountTooLarge(Decimal)
    case cannotDelete(String, String)

    var errorDescription: String? {
        switch self {
        case .emptySerial: "序列号不能为空"
        case .emptyModel: "型号不能为空"
        case .duplicateSerial(let serial): "序列号 \(serial) 已入库，本次录入被拦截"
        case .notInStock(let serial): "序列号 \(serial) 不在库，无法出库"
        case .emptySelection: "请先选择要出库的机器"
        case .invalidAmount(let field): "\(field) 不是有效数字"
        case .invalidDiscount: "折扣与抹零不能为负数"
        case .discountTooLarge(let subtotal): "折扣加抹零超过商品小计 \(subtotal.cny)"
        case .cannotDelete(let serial, let reason): "序列号 \(serial) 无法删除：\(reason)"
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
    static func intake(_ draft: IntakeDraft, batch: Batch? = nil, in context: ModelContext) throws -> Item {
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

        if let batch {
            item.batch = batch
            CostAllocation.reallocate(batch)
        }

        try context.save()
        SpotlightIndexer.index(item)
        return item
    }

    /// 出库的一行：一台机器 + 它的成交价（可逐台改价）
    struct SaleLine {
        let item: Item
        let price: Decimal
    }

    /// 兼容旧调用：统一单价。多台时传 nil 即按各台标价。
    @discardableResult
    static func sell(
        items: [Item],
        unitPrice: Decimal?,
        customerName: String,
        customerContact: String,
        in context: ModelContext
    ) throws -> Order {
        try sell(
            lines: items.map { SaleLine(item: $0, price: unitPrice ?? $0.listPriceCNY) },
            customerName: customerName,
            customerContact: customerContact,
            discountCNY: 0,
            roundingCNY: 0,
            paymentMethod: .cash,
            in: context
        )
    }

    /// 出库：校验在库 → 逐台写成交价 → 计算折扣与毛利 → 生成连续单号
    @discardableResult
    static func sell(
        lines: [SaleLine],
        customerName: String,
        customerContact: String,
        discountCNY: Decimal,
        roundingCNY: Decimal,
        paymentMethod: PaymentMethod,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Order {
        guard !lines.isEmpty else { throw InventoryError.emptySelection }
        for line in lines where line.item.status != .inStock {
            throw InventoryError.notInStock(line.item.serialNumber)
        }
        guard discountCNY >= 0, roundingCNY >= 0 else { throw InventoryError.invalidDiscount }

        let subtotal = lines.reduce(Decimal(0)) { $0 + $1.price }.rounded(2)
        guard discountCNY + roundingCNY <= subtotal else { throw InventoryError.discountTooLarge(subtotal) }

        let year = Calendar.current.component(.year, from: now)
        let sequence = try OrderNumberFactory.nextSequence(for: year, in: context)

        let order = Order()
        order.sequenceYear = year
        order.sequenceNumber = sequence
        order.number = OrderNumberFactory.make(year: year, sequence: sequence)
        order.customerName = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        order.customerContact = customerContact.trimmingCharacters(in: .whitespacesAndNewlines)
        order.createdAt = now
        order.originDeviceID = DeviceIdentity.current
        order.paymentMethod = paymentMethod
        order.subtotalCNY = subtotal
        order.discountCNY = discountCNY.rounded(2)
        order.roundingCNY = roundingCNY.rounded(2)
        context.insert(order)

        let payable = (subtotal - discountCNY - roundingCNY).rounded(2)
        var cost: Decimal = 0
        for line in lines {
            line.item.status = .sold
            line.item.soldAt = now
            line.item.soldPriceCNY = line.price
            line.item.order = order
            cost += line.item.landedCostCNY
        }

        // 毛利按「实收 − 总成本」算，折扣必须计入，否则毛利虚高
        order.totalCNY = payable
        order.profitCNY = (payable - cost).rounded(2)

        try context.save()
        lines.forEach { SpotlightIndexer.index($0.item) }
        return order
    }

    /// 删除误录入的机器。只允许删在库且无单据关联的整机，
    /// 已售出的必须先退货或作废单据，否则会留下"有单无机"的坏数据。
    static func delete(_ item: Item, in context: ModelContext) throws {
        guard item.status == .inStock else { throw InventoryError.cannotDelete(item.serialNumber, item.status.label) }
        guard item.order == nil else { throw InventoryError.cannotDelete(item.serialNumber, "仍挂在单据上") }

        let serial = item.serialNumber
        SpotlightIndexer.remove(serial: serial)
        // SwiftData 会在 delete 时按 inverse 自动摘除关系，直接改数组反而可能触发
        // 重复 insert/delete；批次若只剩它自己，分摊也无意义，交给 next reallocate 处理
        context.delete(item)
        try context.save()
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
