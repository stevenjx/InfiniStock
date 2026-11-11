import Foundation
import PDFKit
import SwiftData

/// 业务层自检。不依赖界面，直接对 Model + Store 跑断言。
/// 由 scripts/verify.sh 编译运行，每个里程碑都要保持全绿。
@main
struct Verify {
    @MainActor
    static func main() throws {
        var failures = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("PASS  \(name)")
            } else {
                failures += 1
                print("FAIL  \(name) \(detail)")
            }
        }

        let schema = Schema([Item.self, Order.self, Batch.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // MARK: 入库

        var draft = IntakeDraft()
        draft.serialNumber = "  c02abc123  "
        draft.modelName = "iPhone 17 Pro Max"
        draft.storage = "256GB"
        draft.costAmount = "1000"
        draft.currency = .usd
        draft.exchangeRate = "7.1"
        draft.shippingCNY = "120"
        draft.listPriceCNY = "8999"

        let item = try InventoryService.intake(draft, in: context)
        check("入库规范化序列号", item.serialNumber == "C02ABC123", item.serialNumber)
        check("落地成本 = 1000×7.1+120", item.landedCostCNY == 7220, "\(item.landedCostCNY)")
        check("默认状态为在库", item.status == .inStock)

        var duplicate = draft
        duplicate.serialNumber = "C02ABC123"
        do {
            _ = try InventoryService.intake(duplicate, in: context)
            check("重复序列号被拦截", false, "未抛错")
        } catch {
            check("重复序列号被拦截", true)
        }

        // MARK: 出库

        let order = try InventoryService.sell(
            items: [item],
            unitPrice: 8999,
            customerName: "张三",
            customerContact: "13800000000",
            in: context
        )
        check("出库后状态为已售", item.status == .sold)
        check("成交价写入", item.soldPriceCNY == 8999)
        check("订单金额", order.totalCNY == 8999, "\(order.totalCNY)")
        check("订单毛利 = 8999-7220", order.profitCNY == 1779, "\(order.profitCNY)")
        check("单台毛利一致", item.grossProfitCNY == 1779)
        check("订单挂上机器", order.itemList.count == 1)
        check("机器反向关联订单", item.order?.number == order.number)

        do {
            _ = try InventoryService.sell(items: [item], unitPrice: 100, customerName: "", customerContact: "", in: context)
            check("重复出库被拦截", false, "未抛错")
        } catch {
            check("重复出库被拦截", true)
        }

        // MARK: 派生库存

        var second = draft
        second.serialNumber = "C02XYZ999"
        second.listPriceCNY = "7999"
        let inStockItem = try InventoryService.intake(second, in: context)

        let all = try context.fetch(FetchDescriptor<Item>())
        let inStock = all.filter { $0.status == .inStock }
        check("在库台数 = 1", inStock.count == 1, "\(inStock.count)")

        // MARK: 库龄

        let calendar = Calendar.current
        inStockItem.inboundAt = calendar.date(byAdding: .day, value: -75, to: .now)!
        check("库龄按自然日 = 75", inStockItem.ageInDays == 75, "\(inStockItem.ageInDays)")
        check("在库超 60 天标为呆滞", inStockItem.isOverdue)

        inStockItem.inboundAt = calendar.date(byAdding: .day, value: -5, to: .now)!
        check("在库 5 天不算呆滞", !inStockItem.isOverdue)

        let soldInbound = calendar.date(byAdding: .day, value: -40, to: .now)!
        item.inboundAt = soldInbound
        item.soldAt = calendar.date(byAdding: .day, value: -10, to: .now)!
        check("已售库龄 = 卖出日 - 入库日 = 30", item.ageInDays == 30, "\(item.ageInDays)")
        check("已售不计入呆滞", !item.isOverdue)


        // MARK: 批次分摊

        let countBatch = Batch()
        countBatch.name = "按台均摊"
        countBatch.currency = .usd
        countBatch.exchangeRate = 7.1
        countBatch.totalShippingCNY = 100
        countBatch.allocation = .byCount
        context.insert(countBatch)

        var countDrafts: [IntakeDraft] = []
        for index in 1...3 {
            var d = IntakeDraft()
            d.serialNumber = "CNT00\(index)"
            d.modelName = "iPhone 17"
            d.costAmount = "100"
            d.exchangeRate = "7.1"
            countDrafts.append(d)
            _ = try InventoryService.intake(d, batch: countBatch, in: context)
        }

        let countShares = countBatch.itemList.map(\.shippingCNY).sorted()
        check("按台均摊 3 台", countShares.count == 3, "\(countShares)")
        check("按台均摊合计精确 = 100",
              countBatch.itemList.reduce(Decimal(0)) { $0 + $1.shippingCNY } == 100,
              "\(countBatch.itemList.reduce(Decimal(0)) { $0 + $1.shippingCNY })")
        check("尾差落在最后一台", countShares.last == Decimal(string: "33.34"), "\(String(describing: countShares.last))")
        check("汇率锁定到每台",
              countBatch.itemList.allSatisfy { $0.exchangeRate == 7.1 })

        let valueBatch = Batch()
        valueBatch.name = "按货值分摊"
        valueBatch.currency = .cny
        valueBatch.exchangeRate = 1
        valueBatch.totalShippingCNY = 120
        valueBatch.allocation = .byValue
        context.insert(valueBatch)

        for (index, cost) in [100, 200, 300].enumerated() {
            var d = IntakeDraft()
            d.serialNumber = "VAL00\(index)"
            d.modelName = "iPhone 16"
            d.costAmount = "\(cost)"
            d.exchangeRate = "1"
            _ = try InventoryService.intake(d, batch: valueBatch, in: context)
        }

        let valueShares = valueBatch.itemList.sorted { $0.serialNumber < $1.serialNumber }.map(\.shippingCNY)
        check("按货值分摊 100/200/300 → 20/40/60",
              valueShares == [20, 40, 60],
              "\(valueShares)")
        check("按货值分摊合计精确 = 120",
              valueBatch.itemList.reduce(Decimal(0)) { $0 + $1.shippingCNY } == 120)

        let baseSum = valueBatch.itemList.reduce(Decimal(0)) { $0 + $1.costAmount * $1.exchangeRate }
        let landedSum = valueBatch.itemList.reduce(Decimal(0)) { $0 + $1.landedCostCNY }
        check("落地成本合计 = 货值 + 运费", landedSum == baseSum + 120, "\(landedSum) vs \(baseSum + 120)")


        // MARK: 统计口径

        let statsSchema = Schema([Item.self, Order.self, Batch.self])
        let statsConfig = ModelConfiguration(schema: statsSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let statsContainer = try ModelContainer(for: statsSchema, configurations: [statsConfig])
        let statsContext = statsContainer.mainContext

        func makeItem(_ serial: String, cost: Decimal, list: Decimal, days: Int, sold: Bool = false) -> Item {
            let item = Item(
                serialNumber: serial, modelName: "iPhone 17",
                costAmount: cost, currency: .cny, exchangeRate: 1,
                shippingCNY: 0, listPriceCNY: list
            )
            item.inboundAt = calendar.date(byAdding: .day, value: -days, to: .now)!
            if sold {
                item.status = .sold
                item.soldAt = .now
                item.soldPriceCNY = list
            }
            statsContext.insert(item)
            return item
        }

        _ = makeItem("ST001", cost: 7000, list: 8999, days: 5)
        _ = makeItem("ST002", cost: 5000, list: 5999, days: 45)
        _ = makeItem("ST003", cost: 4000, list: 4999, days: 120)
        _ = makeItem("ST004", cost: 7220, list: 8999, days: 20, sold: true)
        _ = makeItem("ST005", cost: 3000, list: 3599, days: 10, sold: true)
        try statsContext.save()

        let allStatsItems = try statsContext.fetch(FetchDescriptor<Item>())
        let stats = InventoryStatistics(items: allStatsItems)

        check("在库台数 = 3", stats.inStockCount == 3, "\(stats.inStockCount)")
        check("库存成本合计 = 16000", stats.stockCostValue == 16000, "\(stats.stockCostValue)")
        check("库存标价合计 = 19997", stats.stockListedValue == 19997, "\(stats.stockListedValue)")
        check("今日成交 2 台", stats.todayCount == 2, "\(stats.todayCount)")
        check("今日销售额 = 12598", stats.todayRevenue == 12598, "\(stats.todayRevenue)")
        check("今日毛利 = 2378", stats.todayProfit == 2378, "\(stats.todayProfit)")

        let counts = stats.agingBuckets.map(\.count)
        check("库龄分档 1/1/0/1", counts == [1, 1, 0, 1], "\(counts)")
        check("呆滞品 1 台", stats.overdueItems.count == 1, "\(stats.overdueItems.count)")
        check("呆滞品为 ST003", stats.overdueItems.first?.serialNumber == "ST003")
        check("呆滞占用成本 = 4000", stats.overdueValue == 4000, "\(stats.overdueValue)")
        check("库存潜在毛利 = 3997", stats.stockPotentialProfit == 3997, "\(stats.stockPotentialProfit)")

        // MARK: 非法输入

        var bad = IntakeDraft()
        bad.serialNumber = "BADSERIAL"
        bad.modelName = "iPhone 17"
        bad.costAmount = "abc"
        do {
            _ = try InventoryService.intake(bad, in: context)
            check("非法进价被拦截", false)
        } catch {
            check("非法进价被拦截", true)
        }


        // MARK: 金额大写

        check("8999 大写", ChineseAmount.uppercase(8999) == "捌仟玖佰玖拾玖元整", ChineseAmount.uppercase(8999))
        check("10001 大写补零", ChineseAmount.uppercase(10001) == "壹万零壹元整", ChineseAmount.uppercase(10001))
        check("100.5 大写", ChineseAmount.uppercase(100.5) == "壹佰元伍角", ChineseAmount.uppercase(100.5))
        check("0.05 大写", ChineseAmount.uppercase(0.05) == "伍分", ChineseAmount.uppercase(0.05))
        check("1234567.89 大写",
              ChineseAmount.uppercase(1234567.89) == "壹佰贰拾叁万肆仟伍佰陆拾柒元捌角玖分",
              ChineseAmount.uppercase(1234567.89))

        // MARK: 凭证 PDF

        let document = ReceiptDocument(order: order)
        check("凭证不含进价与毛利", document.lines.allSatisfy { $0.price > 0 })

        guard let pdf = ReceiptPDFRenderer.render(document) else {
            check("PDF 生成", false, "render 返回 nil")
            print("\n\(failures) CHECK(S) FAILED")
            exit(1)
        }
        check("PDF 有内容", pdf.count > 2_000, "\(pdf.count) bytes")
        check("PDF 文件头正确", String(data: pdf.prefix(5), encoding: .ascii) == "%PDF-")

        guard let parsed = PDFDocument(data: pdf), let page = parsed.page(at: 0) else {
            check("PDF 可被解析", false)
            print("\n\(failures) CHECK(S) FAILED")
            exit(1)
        }
        check("PDF 单页", parsed.pageCount == 1, "\(parsed.pageCount)")
        check("页面为 A4 宽度", abs(page.bounds(for: .mediaBox).width - 595.28) < 1, "\(page.bounds(for: .mediaBox))")

        let content = page.string ?? ""
        check("PDF 含标题", content.contains("销售凭证"))
        check("PDF 含序列号", content.contains("C02ABC123"), content.prefix(80).description)
        check("PDF 含客户", content.contains("张三"))
        check("PDF 含合计金额", content.contains("8,999"))
        check("PDF 含大写金额", content.contains("捌仟玖佰玖拾玖元整"))
        check("PDF 不含成本字样", !content.contains("进价") && !content.contains("毛利"))

        // MARK: 照片压缩

        let bigImage = NSImage(size: NSSize(width: 3000, height: 2000))
        bigImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 3000, height: 2000).fill()
        bigImage.unlockFocus()
        if let tiff = bigImage.tiffRepresentation,
           let jpeg = ImageScaler.downscaledJPEG(tiff),
           let scaled = NSImage(data: jpeg) {
            check("照片长边压到 1600", scaled.size.width == 1600, "\(scaled.size.width)")
            check("照片体积可控", jpeg.count < 1_200_000, "\(jpeg.count) bytes")
        } else {
            check("照片压缩", false)
        }

        print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
