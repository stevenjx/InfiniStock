import Foundation
import SwiftData

enum InventoryError: LocalizedError {
    case emptySerial
    case emptyModel
    case duplicateSerial(String)
    case notInStock(String)
    case emptySelection
    case invalidAmount(String)
    case invalidRate
    case batteryOutOfRange
    case invalidDiscount
    case discountTooLarge(Decimal)
    case cannotDelete(String, String)

    var errorDescription: String? {
        switch self {
        case .emptySerial: "序列号不能为空"
        case .emptyModel: "型号不能为空"
        case .duplicateSerial(let serial): String(localized: "序列号 \(serial) 已入库，本次录入被拦截")
        case .notInStock(let serial): String(localized: "序列号 \(serial) 不在库，无法出库")
        case .emptySelection: "请先选择要出库的机器"
        case .invalidAmount(let field): String(localized: "\(field) 不是有效数字")
        case .invalidRate: "汇率必须大于 0（1 元人民币 = N 缅币）"
        case .batteryOutOfRange: "电池健康需在 0–100 之间，循环次数不能为负数"
        case .invalidDiscount: "折扣与抹零不能为负数"
        case .discountTooLarge(let subtotal): String(localized: "折扣加抹零超过商品小计 \(subtotal.mmk)")
        case .cannotDelete(let serial, let reason): "序列号 \(serial) 无法删除：\(reason)"
        }
    }
}

/// 入库表单的原始输入，数字保持字符串以便逐字段报错。
struct IntakeDraft {
    var serialNumber = ""
    /// 选中的标准机型。型号是所有统计的分组键，所以不从自由文本收。
    var model: MacModel?
    /// 由 model 派生，保证写进库的一定是标准写法。
    /// 不叫 modelName：那会和 Item.modelName 在调用处混看，容易误写。
    var resolvedModelName: String { model?.displayName ?? "" }
    var chip = ""
    var memory = ""
    var storage = ""
    var color = ""
    var condition: ItemCondition = .p95
    /// 人民币进价
    var costCNY = ""
    /// 1 元人民币 = N 缅币
    var exchangeRate = ""
    /// 缅币运费
    var shipping = "0"
    /// 缅币标价
    var listPrice = ""
    /// 电池健康百分比，留空表示未检测
    var batteryHealth = ""
    /// 电池循环次数，留空表示未检测
    var batteryCycles = ""

    var previewLandedCost: Decimal {
        Money.landedCost(
            costCNY: Money.parse(costCNY) ?? 0,
            rate: Money.parse(exchangeRate) ?? 0,
            shipping: Money.parse(shipping) ?? 0
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
        guard !normalize(draft.resolvedModelName).isEmpty else { throw InventoryError.emptyModel }
        guard !serialExists(serial, in: context) else { throw InventoryError.duplicateSerial(serial) }

        let cost = try amount(draft.costCNY, field: "进价", fallback: 0)
        let rate = try amount(draft.exchangeRate, field: "汇率", fallback: 0)
        guard rate > 0 else { throw InventoryError.invalidRate }
        let shipping = try amount(draft.shipping, field: "运费", fallback: 0)
        let listPrice = try amount(draft.listPrice, field: "标价", fallback: 0)
        let health = try intAmount(draft.batteryHealth, field: "电池健康", fallback: 0)
        let cycles = try intAmount(draft.batteryCycles, field: "循环次数", fallback: 0)
        guard (0...100).contains(health), cycles >= 0 else { throw InventoryError.batteryOutOfRange }

        let item = Item(
            serialNumber: serial,
            modelName: draft.resolvedModelName,
            chip: draft.chip,
            memory: draft.memory,
            storage: draft.storage,
            color: draft.color,
            condition: draft.condition,
            costCNY: cost,
            exchangeRate: rate,
            shipping: shipping,
            listPrice: listPrice,
            batteryHealth: health,
            batteryCycles: cycles
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
            lines: items.map { SaleLine(item: $0, price: unitPrice ?? $0.listPrice) },
            customerName: customerName,
            customerContact: customerContact,
            discount: 0,
            rounding: 0,
            paymentMethod: .cash,
            in: context
        )
    }

    /// 出库：校验在库 → 逐台写成交价 → 计算折扣与毛利 → 生成连续单号
    /// - Parameter paid: 实收金额。nil 表示当场全额收讫；小于应收即记为欠款。
    @discardableResult
    static func sell(
        lines: [SaleLine],
        customerName: String,
        customerContact: String,
        discount: Decimal,
        rounding: Decimal,
        paymentMethod: PaymentMethod,
        paid: Decimal? = nil,
        in context: ModelContext,
        now: Date = .now
    ) throws -> Order {
        guard !lines.isEmpty else { throw InventoryError.emptySelection }
        for line in lines where line.item.status != .inStock {
            throw InventoryError.notInStock(line.item.serialNumber)
        }
        // 0 元成交会让"台数 +1、销售额 +0"，统计口径直接歪掉。
        // 赠送要走折扣（可追溯），不能靠把单价填成 0。
        if let bad = lines.first(where: { $0.price <= 0 }) {
            throw InventoryError.invalidAmount(String(localized: "\(bad.item.serialNumber) 的成交价（必须大于 0）"))
        }
        guard discount >= 0, rounding >= 0 else { throw InventoryError.invalidDiscount }
        if let paid, paid < 0 { throw InventoryError.invalidAmount("实收金额") }

        let subtotal = lines.reduce(Decimal(0)) { $0 + $1.price }.rounded(2)
        guard discount + rounding <= subtotal else { throw InventoryError.discountTooLarge(subtotal) }

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
        order.subtotal = subtotal
        order.discount = discount.rounded(2)
        order.rounding = rounding.rounded(2)
        context.insert(order)

        let payable = (subtotal - discount - rounding).rounded(2)
        var cost: Decimal = 0
        for line in lines {
            line.item.status = .sold
            line.item.soldAt = now
            line.item.soldPrice = line.price
            line.item.order = order
            cost += line.item.landedCost
        }

        // 毛利按「实收 − 总成本」算，折扣必须计入，否则毛利虚高
        order.total = payable
        order.profit = (payable - cost).rounded(2)

        // 实收只记到应收为止：多给的是找零，不该进账
        let received = min(max(paid ?? payable, 0), payable).rounded(2)
        order.paidAmount = received
        order.paidAt = now

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

    private static func intAmount(_ text: String, field: String, fallback: Int) throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return fallback }
        guard let value = Int(trimmed) else { throw InventoryError.invalidAmount(field) }
        return value
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
