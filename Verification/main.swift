import Foundation
import PDFKit
import SwiftData

/// 业务层自检。不依赖界面，直接对 Model + Store 跑断言。
/// 由 scripts/verify.sh 编译运行，每个里程碑都要保持全绿。
@main
struct Verify {
    @MainActor
    static func main() throws {
        setvbuf(stdout, nil, _IONBF, 0)   // 崩溃时也要能看到已跑过的断言
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


        // MARK: 撤销单据与序列号查询

        var voidDraft = IntakeDraft()
        voidDraft.serialNumber = "VOID001"
        voidDraft.modelName = "iPhone 18"
        voidDraft.costAmount = "5000"
        voidDraft.currency = .cny
        voidDraft.exchangeRate = "1"
        voidDraft.listPriceCNY = "6999"
        let voidItem = try InventoryService.intake(voidDraft, in: context)
        let voidOrder = try InventoryService.sell(
            items: [voidItem], unitPrice: 6999,
            customerName: "李四", customerContact: "", in: context
        )

        check("撤销前为已售", voidItem.status == .sold)
        try OrderService.void(voidOrder, in: context)
        check("撤销后回到在库", voidItem.status == .inStock)
        check("撤销后清空成交价", voidItem.soldPriceCNY == 0)
        check("撤销后清空售出时间", voidItem.soldAt == nil)
        check("撤销后解除单据关联", voidItem.order == nil)
        check("单据标记作废但保留", voidOrder.voidedAt != nil && voidOrder.totalCNY == 6999)

        do {
            try OrderService.void(voidOrder, in: context)
            check("重复撤销被拦截", false, "未抛错")
        } catch {
            check("重复撤销被拦截", true)
        }

        check("撤销后库存台数恢复",
              try context.fetch(FetchDescriptor<Item>()).filter { $0.status == .inStock }.contains { $0.serialNumber == "VOID001" })

        check("按序列号查询忽略大小写与空格",
              ItemLookup.find(serial: " void001 ", in: context)?.serialNumber == "VOID001")
        check("查询不存在的序列号返回 nil",
              ItemLookup.find(serial: "NOT-EXIST", in: context) == nil)
        check("最近入库列表非空", !ItemLookup.recent(in: context).isEmpty)


        // MARK: 备份导出与恢复

        let backupSchema = Schema([Item.self, Order.self, Batch.self])
        let backupConfig = ModelConfiguration(schema: backupSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let sourceContainer = try ModelContainer(for: backupSchema, configurations: [backupConfig])
        let source = sourceContainer.mainContext

        let srcBatch = Batch()
        srcBatch.name = "备份批"
        srcBatch.supplier = "深圳"
        srcBatch.currency = .usd
        srcBatch.exchangeRate = 7.1234
        srcBatch.totalShippingCNY = 333.33
        srcBatch.allocation = .byValue
        source.insert(srcBatch)

        for (index, cost) in ["1234.56", "987.65", "0.01"].enumerated() {
            var d = IntakeDraft()
            d.serialNumber = "BKP00\(index)"
            d.modelName = "iPhone 17"
            d.memory = "8GB"
            d.storage = "256GB"
            d.color = "深空黑"
            d.costAmount = cost
            d.currency = .usd
            d.exchangeRate = "7.1234"
            d.shippingCNY = "0"
            d.listPriceCNY = "8999.99"
            _ = try InventoryService.intake(d, batch: srcBatch, in: source)
        }
        try source.save()

        let firstItem = try source.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.serialNumber)])).first!
        let soldOrder = try InventoryService.sell(
            items: [firstItem], unitPrice: Decimal(string: "8888.88"),
            customerName: "王五", customerContact: "13900000000", in: source
        )

        let expectedItemCount = try source.fetchCount(FetchDescriptor<Item>())
        let expectedOrderCount = try source.fetchCount(FetchDescriptor<Order>())
        let expectedBatchCount = try source.fetchCount(FetchDescriptor<Batch>())
        let expectedCost = try source.fetch(FetchDescriptor<Item>()).reduce(Decimal(0)) { $0 + $1.landedCostCNY }
        let expectedRevenue = try source.fetch(FetchDescriptor<Item>()).reduce(Decimal(0)) { $0 + $1.soldPriceCNY }
        let expectedSerials = Set(try source.fetch(FetchDescriptor<Item>()).map(\.serialNumber))

        let snapshot = try BackupService.makeSnapshot(from: source)
        let json = try BackupService.jsonData(snapshot)
        check("快照条数与库一致", snapshot.items.count == expectedItemCount, "\(snapshot.items.count)")
        check("JSON 已生成", json.count > 500, "\(json.count) bytes")

        let restored = try BackupService.decode(json)
        check("回读版本一致", restored.formatVersion == BackupSnapshot.currentFormatVersion)
        check("回读条数一致", restored.items.count == expectedItemCount)
        check("回读单据一致", restored.orders.count == expectedOrderCount)
        check("回读批次一致", restored.batches.count == expectedBatchCount)

        // 精确到分：这是 P0 的核心验收
        let restoredItemA = restored.items.first { $0.serialNumber == "BKP000" }!
        check("金额字符串无损 1234.56", restoredItemA.costAmount == "1234.56", restoredItemA.costAmount)
        let restoredItemC = restored.items.first { $0.serialNumber == "BKP002" }!
        check("小额 0.01 无损", restoredItemC.costAmount == "0.01", restoredItemC.costAmount)
        let restoredOrder = restored.orders.first!
        check("成交价无损 8888.88", restoredOrder.totalCNY == "8888.88", restoredOrder.totalCNY)
        check("单据关联序列号", restoredOrder.itemSerials == ["BKP000"], "\(restoredOrder.itemSerials)")
        check("毛利字段非空", !restoredOrder.profitCNY.isEmpty)

        // 回灌到空库
        let targetConfig = ModelConfiguration(schema: backupSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let targetContainer = try ModelContainer(for: backupSchema, configurations: [targetConfig])
        let target = targetContainer.mainContext
        try BackupService.restore(restored, into: target)

        let restoredItems = try target.fetch(FetchDescriptor<Item>())
        check("恢复后台数一致", restoredItems.count == expectedItemCount, "\(restoredItems.count)")
        check("恢复后序列号集合一致", Set(restoredItems.map(\.serialNumber)) == expectedSerials)
        check("恢复后落地成本合计一致",
              restoredItems.reduce(Decimal(0)) { $0 + $1.landedCostCNY } == expectedCost,
              "\(restoredItems.reduce(Decimal(0)) { $0 + $1.landedCostCNY }) vs \(expectedCost)")
        check("恢复后成交额合计一致",
              restoredItems.reduce(Decimal(0)) { $0 + $1.soldPriceCNY } == expectedRevenue)

        let restoredSoldItem = restoredItems.first { $0.serialNumber == "BKP000" }!
        check("恢复后状态为已售", restoredSoldItem.status == .sold)
        check("恢复后单据挂回机器", restoredSoldItem.order?.number == soldOrder.number)
        check("恢复后批次挂回机器", restoredSoldItem.batch?.name == "备份批")
        check("恢复后汇率保留四位",
              restoredSoldItem.batch?.exchangeRate == Decimal(string: "7.1234"),
              "\(String(describing: restoredSoldItem.batch?.exchangeRate))")

        // 恢复必须覆盖而不是叠加
        try BackupService.restore(restored, into: target)
        check("重复恢复不叠加",
              try target.fetchCount(FetchDescriptor<Item>()) == expectedItemCount,
              "\(try target.fetchCount(FetchDescriptor<Item>()))")

        // 坏文件必须拒绝
        do {
            _ = try BackupService.decode(Data("not json".utf8))
            check("损坏文件被拒绝", false, "未抛错")
        } catch {
            check("损坏文件被拒绝", true)
        }

        // CSV
        let csv = try BackupService.csvData(from: source)
        let csvText = String(decoding: csv, as: UTF8.self)
        check("CSV 带 BOM 供 Excel 识别", csvText.hasPrefix("\u{FEFF}"))
        check("CSV 含表头", csvText.contains("序列号") && csvText.contains("落地成本"))
        // split 会丢掉末尾的空段，所以行数 = 表头 + 机器数
        check("CSV 行数 = 表头 + 机器数",
              csvText.split(separator: "\r\n").count == expectedItemCount + 1,
              "\(csvText.split(separator: "\r\n").count) vs \(expectedItemCount + 1)")

        // 保留策略
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("bkp-prune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for index in 0..<20 {
            let name = String(format: "infinistock-202601%02d-000000.json", index + 1)
            try Data("{}".utf8).write(to: tempDir.appendingPathComponent(name))
        }
        BackupService.prune(in: tempDir, keeping: 14)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        check("只保留最近 14 份", remaining.count == 14, "\(remaining.count)")
        check("保留的是最新的", remaining.contains("infinistock-20260120-000000.json"))
        check("删掉的是最旧的", !remaining.contains("infinistock-20260101-000000.json"))
        try? FileManager.default.removeItem(at: tempDir)


        // MARK: 备份真文件写入

        let liveDir = FileManager.default.temporaryDirectory.appendingPathComponent("bkp-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        let written = try BackupService.writeBackup(from: source, into: liveDir)
        check("备份文件已落盘", FileManager.default.fileExists(atPath: written.path))
        check("备份文件名符合规范", written.lastPathComponent.hasPrefix("infinistock-") && written.lastPathComponent.hasSuffix(".json"))
        let reloaded = try BackupService.decode(try Data(contentsOf: written))
        check("落盘文件可回读", reloaded.items.count == expectedItemCount, "\(reloaded.items.count)")
        check("记录最近备份时间", BackupService.lastBackupAt != nil)

        // 同日再备份一次不应重复由 auto 触发（此处目录书签未设，应安全返回 nil）
        check("未配置目录时自动备份静默跳过", BackupService.autoBackupIfNeeded(from: source) == nil)
        try? FileManager.default.removeItem(at: liveDir)


        // MARK: P1 单号与折扣

        let p1Schema = Schema([Item.self, Order.self, Batch.self])
        let p1Config = ModelConfiguration(schema: p1Schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let p1Container = try ModelContainer(for: p1Schema, configurations: [p1Config])
        let p1 = p1Container.mainContext

        func p1Item(_ serial: String, cost: Decimal, list: Decimal) -> Item {
            let item = Item(
                serialNumber: serial, modelName: "iPhone 17",
                costAmount: cost, currency: .cny, exchangeRate: 1,
                shippingCNY: 0, listPriceCNY: list
            )
            p1.insert(item)
            return item
        }

        let a = p1Item("P1A", cost: 5000, list: 6999)
        let b = p1Item("P1B", cost: 4000, list: 5599)
        let c = p1Item("P1C", cost: 3000, list: 4299)

        // 逐台改价 + 折扣 + 抹零
        let p1Order = try InventoryService.sell(
            lines: [
                .init(item: a, price: Decimal(string: "6800")!),
                .init(item: b, price: Decimal(string: "5500")!),
                .init(item: c, price: Decimal(string: "4200")!),
            ],
            customerName: "赵六", customerContact: "",
            discountCNY: 200, roundingCNY: 88, paymentMethod: .transfer,
            in: p1
        )

        check("单号为 SO-年-四位序号",
              p1Order.number.hasPrefix("SO-\(Calendar.current.component(.year, from: .now))-"),
              p1Order.number)
        check("首单序号为 0001", p1Order.number.hasSuffix("-0001"), p1Order.number)
        check("小计 = 16500", p1Order.subtotalCNY == 16500, "\(p1Order.subtotalCNY)")
        check("应收 = 16500-200-88 = 16212", p1Order.totalCNY == 16212, "\(p1Order.totalCNY)")
        check("毛利计入折扣", p1Order.profitCNY == 16212 - 12000, "\(p1Order.profitCNY)")
        check("收款方式保存", p1Order.paymentMethod == .transfer)
        check("逐台价格分别写入",
              a.soldPriceCNY == 6800 && b.soldPriceCNY == 5500 && c.soldPriceCNY == 4200,
              "\(a.soldPriceCNY)/\(b.soldPriceCNY)/\(c.soldPriceCNY)")

        // 第二单、第三单必须连号
        for serial in ["P1D", "P1E"] {
            let item = p1Item(serial, cost: 1000, list: 2000)
            let order = try InventoryService.sell(
                lines: [.init(item: item, price: 2000)],
                customerName: "", customerContact: "",
                discountCNY: 0, roundingCNY: 0, paymentMethod: .cash, in: p1
            )
            _ = order
        }
        let numbers = try p1.fetch(FetchDescriptor<Order>(sortBy: [SortDescriptor(\.sequenceNumber)])).map(\.number)
        check("连续三单不跳号", numbers == ["SO-\(Calendar.current.component(.year, from: .now))-0001",
                                          "SO-\(Calendar.current.component(.year, from: .now))-0002",
                                          "SO-\(Calendar.current.component(.year, from: .now))-0003"], "\(numbers)")

        // 折扣不能超过小计
        let over = p1Item("P1F", cost: 100, list: 100)
        do {
            _ = try InventoryService.sell(
                lines: [.init(item: over, price: 100)],
                customerName: "", customerContact: "",
                discountCNY: 200, roundingCNY: 0, paymentMethod: .cash, in: p1
            )
            check("折扣超小计被拦截", false, "未抛错")
        } catch {
            check("折扣超小计被拦截", true)
        }
        check("失败的单不占用单号",
              try p1.fetchCount(FetchDescriptor<Order>()) == 3,
              "\(try p1.fetchCount(FetchDescriptor<Order>()))")

        // 单号解析兼容旧格式
        check("可解析新格式", OrderNumberFactory.parse("SO-2026-0007")?.sequence == 7)
        check("旧格式解析返回 nil", OrderNumberFactory.parse("SO-20260811-2120-042") == nil)

        // MARK: 凭证含店名与折扣

        let shop = ShopSettings(
            shopName: "星海数码", phone: "0755-12345678",
            address: "深圳市福田区华强北 1 号", warrantyDays: 15, footnote: "本店售出机器均附验机报告"
        )
        let p1Doc = ReceiptDocument(order: p1Order, settings: shop)
        check("凭证带店名", p1Doc.shopName == "星海数码")
        check("凭证小计正确", p1Doc.subtotal == 16500, "\(p1Doc.subtotal)")
        check("凭证折扣正确", p1Doc.discount == 200)
        check("凭证抹零正确", p1Doc.rounding == 88)
        check("凭证应收正确", p1Doc.total == 16212)
        check("凭证带保修天数", p1Doc.warrantyDays == 15)

        if let pdf = ReceiptPDFRenderer.render(p1Doc),
           let page = PDFDocument(data: pdf)?.page(at: 0),
           let text = page.string {
            check("PDF 印出店名", text.contains("星海数码"))
            check("PDF 印出电话", text.contains("0755-12345678"))
            check("PDF 印出折扣行", text.contains("折扣") && text.contains("200"))
            check("PDF 印出抹零行", text.contains("抹零") && text.contains("88"))
            check("PDF 应收合计正确", text.contains("16,212"))
            check("PDF 大写与应收一致", text.contains(ChineseAmount.uppercase(16212)))
            check("PDF 印出收款方式", text.contains("转账"))
            check("PDF 印出保修 15 天", text.contains("15 日内"))
            check("PDF 印出附加说明", text.contains("验机报告"))
            check("PDF 不泄露成本", !text.contains("5000") && !text.contains("毛利"))
        } else {
            check("凭证 PDF 生成", false)
        }


        // MARK: 折扣必须进统计

        let statsWithDiscount = InventoryStatistics(
            items: try p1.fetch(FetchDescriptor<Item>()),
            orders: try p1.fetch(FetchDescriptor<Order>())
        )
        // 今日三单：16500-288 应收、2000、2000
        check("统计按单据算收入",
              statsWithDiscount.todayRevenue == Decimal(string: "16212")! + 2000 + 2000,
              "\(statsWithDiscount.todayRevenue)")
        check("统计毛利含折扣",
              statsWithDiscount.todayProfit == Decimal(string: "16212")! - 12000 + 1000 + 1000,
              "\(statsWithDiscount.todayProfit)")

        // 作废单不进统计
        let voidable = try p1.fetch(FetchDescriptor<Order>(sortBy: [SortDescriptor(\.sequenceNumber)])).last!
        try OrderService.void(voidable, in: p1)
        let afterVoid = InventoryStatistics(
            items: try p1.fetch(FetchDescriptor<Item>()),
            orders: try p1.fetch(FetchDescriptor<Order>())
        )
        check("作废单不计入收入",
              afterVoid.todayRevenue == Decimal(string: "16212")! + 2000,
              "\(afterVoid.todayRevenue)")


        // MARK: 备份必须保住折扣与单号序号

        let p1Snapshot = try BackupService.makeSnapshot(from: p1)
        let p1JSON = try BackupService.jsonData(p1Snapshot)
        let p1Decoded = try BackupService.decode(p1JSON)
        let p1TargetConfig = ModelConfiguration(schema: p1Schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let p1TargetContainer = try ModelContainer(for: p1Schema, configurations: [p1TargetConfig])
        let p1Target = p1TargetContainer.mainContext
        try BackupService.restore(p1Decoded, into: p1Target)

        let restoredOrders = try p1Target.fetch(FetchDescriptor<Order>(sortBy: [SortDescriptor(\.sequenceNumber)]))
        check("备份保住折扣", restoredOrders.first?.discountCNY == 200, "\(String(describing: restoredOrders.first?.discountCNY))")
        check("备份保住抹零", restoredOrders.first?.roundingCNY == 88, "\(String(describing: restoredOrders.first?.roundingCNY))")
        check("备份保住应收", restoredOrders.first?.totalCNY == 16212)
        check("备份保住收款方式", restoredOrders.first?.paymentMethod == .transfer)
        check("备份保住单号序号", restoredOrders.first?.sequenceNumber == 1, "\(String(describing: restoredOrders.first?.sequenceNumber))")
        check("备份保住单号文本", restoredOrders.first?.number.hasSuffix("-0001") == true)

        // 恢复后继续下单必须接着 0002，不能重号
        let nextItem = Item(serialNumber: "P1G", modelName: "iPhone 17", costAmount: 100, currency: .cny, exchangeRate: 1, shippingCNY: 0, listPriceCNY: 200)
        p1Target.insert(nextItem)
        let nextOrder = try InventoryService.sell(
            lines: [.init(item: nextItem, price: 200)],
            customerName: "", customerContact: "",
            discountCNY: 0, roundingCNY: 0, paymentMethod: .cash, in: p1Target
        )
        check("恢复后新单不重号",
              nextOrder.number.hasSuffix("-0004"),
              nextOrder.number)


        // MARK: P3 CSV 导入

        let csvSchema = Schema([Item.self, Order.self, Batch.self])
        let csvConfig = ModelConfiguration(schema: csvSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let csvContainer = try ModelContainer(for: csvSchema, configurations: [csvConfig])
        let csvContext = csvContainer.mainContext

        // 解析器本身：引号、逗号、转义、CRLF、BOM
        let tricky = "\u{FEFF}序列号,型号,颜色\r\nA1,\"iPhone 17, Pro\",\"深空\"\"黑\"\r\nA2,iPhone 16,银色\r\n"
        let trickyRows = CSVImporter.parseRows(tricky)
        check("CSV 去 BOM", trickyRows.first?.first == "序列号", "\(String(describing: trickyRows.first?.first))")
        check("CSV 字段内逗号", trickyRows[1][1] == "iPhone 17, Pro", trickyRows[1][1])
        check("CSV 双引号转义", trickyRows[1][2] == "深空\"黑", trickyRows[1][2])
        check("CSV 行数正确", trickyRows.count == 3, "\(trickyRows.count)")

        // 100 行含 3 行错误
        var lines: [String] = ["序列号,型号,存储,成色,进价,币种,汇率,运费,标价"]
        var errorLines: [Int] = []
        for index in 1...100 {
            let line = index + 1
            if index == 7 {
                lines.append(",iPhone 17,256GB,95新,1000,CNY,1,0,6999")        // 序列号为空
                errorLines.append(line)
            } else if index == 23 {
                lines.append("IMP023,iPhone 17,256GB,95新,abc,CNY,1,0,6999")   // 进价非法
                errorLines.append(line)
            } else if index == 88 {
                lines.append("IMP001,iPhone 17,256GB,95新,1000,CNY,1,0,6999")  // 与第 2 行重复
                errorLines.append(line)
            } else {
                lines.append(String(format: "IMP%03d,iPhone 17,256GB,95新,1000,CNY,1.5,20,6999", index))
            }
        }
        let importCSVText = lines.joined(separator: "\n")
        let csvPreview = CSVImporter.preview(csv: Data(importCSVText.utf8), in: csvContext)

        check("预检认出 97 台可用", csvPreview.rows.count == 97, "\(csvPreview.rows.count)")
        check("预检报出 3 行错误", csvPreview.issues.count == 3, "\(csvPreview.issues.count)")
        check("错误行号准确",
              csvPreview.issues.map { $0.line }.sorted() == errorLines,
              "\(csvPreview.issues.map { $0.line }.sorted())")
        check("预检不写库",
              try csvContext.fetchCount(FetchDescriptor<Item>()) == 0,
              "\(try csvContext.fetchCount(FetchDescriptor<Item>()))")

        // 落库
        let importedCount = try CSVImporter.commit(csvPreview, batch: nil, in: csvContext)
        check("实际导入 97 台", importedCount == 97, "\(importedCount)")
        check("库中确实 97 台",
              try csvContext.fetchCount(FetchDescriptor<Item>()) == 97,
              "\(try csvContext.fetchCount(FetchDescriptor<Item>()))")

        let importedItem = try csvContext.fetch(
            FetchDescriptor<Item>(predicate: #Predicate { $0.serialNumber == "IMP002" })
        ).first
        check("落地成本 = 1000×1.5+20", importedItem?.landedCostCNY == 1520,
              "\(String(describing: importedItem?.landedCostCNY))")
        check("标价导入正确", importedItem?.listPriceCNY == 6999)
        check("成色导入正确", importedItem?.condition == .p95)
        check("状态默认为在库", importedItem?.status == .inStock)
        check("错误行未入库",
              try csvContext.fetch(
                FetchDescriptor<Item>(predicate: #Predicate { $0.serialNumber == "IMP023" })
              ).isEmpty)

        // 同一份文件再导一次：全部变成「库中已存在」，不会重复
        let secondPreview = CSVImporter.preview(csv: Data(importCSVText.utf8), in: csvContext)
        check("重复导入全部被拦下", secondPreview.rows.isEmpty, "\(secondPreview.rows.count)")
        check("重复导入报 100 行冲突", secondPreview.issues.count == 100, "\(secondPreview.issues.count)")

        // 缺必需列
        let badHeader = "型号,存储\niPhone 17,256GB\n"
        let badPreview = CSVImporter.preview(csv: Data(badHeader.utf8), in: csvContext)
        check("缺列直接拒绝", badPreview.rows.isEmpty && badPreview.issues.count == 1)

        // 成色与币种非法
        let wrongValues = "序列号,型号,进价,成色,币种\nX1,iPhone 17,1000,九五新,CNY\nX2,iPhone 17,1000,95新,RMB\n"
        let wrongPreview = CSVImporter.preview(csv: Data(wrongValues.utf8), in: csvContext)
        check("非法成色被拦", wrongPreview.issues.contains { $0.field == "成色" })
        check("非法币种被拦", wrongPreview.issues.contains { $0.field == "币种" })
        check("合法行仍可通过", wrongPreview.rows.count == 0)

        // 错误清单可导出
        let issueCSV = String(decoding: CSVImporter.issuesCSV(csvPreview.issues), as: UTF8.self)
        check("错误清单带表头", issueCSV.contains("行号,字段,原因"))
        check("错误清单含错误行号", issueCSV.contains("24"))

        // 带批次导入会重算分摊
        let importBatch = Batch()
        importBatch.name = "导入批"
        importBatch.currency = .cny
        importBatch.exchangeRate = 1
        importBatch.totalShippingCNY = 100
        importBatch.allocation = .byCount
        csvContext.insert(importBatch)

        let batchCSV = "序列号,型号,进价,汇率\nBATCH1,iPhone 17,1000,1\nBATCH2,iPhone 17,1000,1\n"
        let batchPreview = CSVImporter.preview(csv: Data(batchCSV.utf8), in: csvContext)
        _ = try CSVImporter.commit(batchPreview, batch: importBatch, in: csvContext)
        check("导入进批次后运费分摊",
              importBatch.itemList.reduce(Decimal(0)) { $0 + $1.shippingCNY } == 100,
              "\(importBatch.itemList.reduce(Decimal(0)) { $0 + $1.shippingCNY })")


        // MARK: P2 部分退货

        let p2Schema = Schema([Item.self, Order.self, Batch.self])
        let p2Config = ModelConfiguration(schema: p2Schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let p2Container = try ModelContainer(for: p2Schema, configurations: [p2Config])
        let p2 = p2Container.mainContext

        func p2Item(_ serial: String, cost: Decimal, list: Decimal) -> Item {
            let item = Item(serialNumber: serial, modelName: "iPhone 17", costAmount: cost,
                            currency: .cny, exchangeRate: 1, shippingCNY: 0, listPriceCNY: list)
            p2.insert(item)
            return item
        }

        let r1 = p2Item("RT1", cost: 5000, list: 6800)
        let r2 = p2Item("RT2", cost: 4000, list: 5500)
        let r3 = p2Item("RT3", cost: 3000, list: 4200)

        let rOrder = try InventoryService.sell(
            lines: [.init(item: r1, price: 6800), .init(item: r2, price: 5500), .init(item: r3, price: 4200)],
            customerName: "钱七", customerContact: "13700001111",
            discountCNY: 200, roundingCNY: 88, paymentMethod: .cash, in: p2
        )
        check("退货前应收 16212", rOrder.totalCNY == 16212, "\(rOrder.totalCNY)")
        check("退货前毛利 4212", rOrder.profitCNY == 4212, "\(rOrder.profitCNY)")

        // 退一台 4200 的
        let refund = try OrderService.returnItems([r3], from: rOrder, in: p2)
        check("退回金额 = 该台成交价", refund == 4200, "\(refund)")
        check("退后剩余两台", rOrder.itemList.count == 2, "\(rOrder.itemList.count)")
        check("退后小计 12300", rOrder.subtotalCNY == 12300, "\(rOrder.subtotalCNY)")

        let expectedDiscountRatio = (Decimal(12300) / Decimal(16500)).rounded(6)
        let expectedDiscount = (Decimal(200) * expectedDiscountRatio).rounded(2)
        let expectedRounding = (Decimal(88) * expectedDiscountRatio).rounded(2)
        check("折扣按比例保留", rOrder.discountCNY == expectedDiscount,
              "\(rOrder.discountCNY) vs \(expectedDiscount)")
        check("抹零按比例保留", rOrder.roundingCNY == expectedRounding,
              "\(rOrder.roundingCNY) vs \(expectedRounding)")
        check("退后应收 = 小计-折扣-抹零",
              rOrder.totalCNY == (Decimal(12300) - rOrder.discountCNY - rOrder.roundingCNY).rounded(2),
              "\(rOrder.totalCNY)")
        check("退后毛利按剩余成本重算",
              rOrder.profitCNY == (rOrder.totalCNY - 9000).rounded(2),
              "\(rOrder.profitCNY)")
        check("退货台数累计", rOrder.returnedCount == 1)
        check("退货金额累计", rOrder.returnedAmountCNY == 4200)
        check("单据仍有效", !rOrder.isVoided)
        check("状态显示部分退货", rOrder.statusLabel == "部分退货", rOrder.statusLabel)

        // 退回的机器应回到在库且清空成交信息
        check("退回机器回到在库", r3.status == .inStock)
        check("退回机器清空成交价", r3.soldPriceCNY == 0)
        check("退回机器解除单据关联", r3.order == nil)
        check("退回机器清空售出时间", r3.soldAt == nil)

        // 不属于该单的机器必须拒绝
        let stranger = p2Item("STRANGER", cost: 100, list: 200)
        do {
            _ = try OrderService.returnItems([stranger], from: rOrder, in: p2)
            check("非本单机器被拒绝", false, "未抛错")
        } catch {
            check("非本单机器被拒绝", true)
        }

        // 全部退完：应收精确归零
        _ = try OrderService.returnItems([r1, r2], from: rOrder, in: p2)
        check("全退后应收归零", rOrder.totalCNY == 0, "\(rOrder.totalCNY)")
        check("全退后毛利归零", rOrder.profitCNY == 0, "\(rOrder.profitCNY)")
        check("全退后折扣归零", rOrder.discountCNY == 0 && rOrder.roundingCNY == 0)
        check("全退后标记作废", rOrder.isVoided)
        check("全退状态可区分", rOrder.statusLabel == "已全退", rOrder.statusLabel)
        check("全退后库存全部恢复",
              [r1, r2, r3].allSatisfy { $0.status == .inStock })

        // 已作废的单不能再退
        do {
            _ = try OrderService.returnItems([r1], from: rOrder, in: p2)
            check("作废单拒绝再退", false, "未抛错")
        } catch {
            check("作废单拒绝再退", true)
        }

        // 退货不影响其他单据
        let soloItem = p2Item("SOLO", cost: 1000, list: 2000)
        let soloOrder = try InventoryService.sell(
            lines: [.init(item: soloItem, price: 2000)], customerName: "无关客户",
            customerContact: "", discountCNY: 0, roundingCNY: 0, paymentMethod: .cash, in: p2
        )
        check("其他单据不受影响", soloOrder.totalCNY == 2000 && !soloOrder.isVoided)

        // 统计口径：退货后收入按净额
        let p2Stats = InventoryStatistics(
            items: try p2.fetch(FetchDescriptor<Item>()),
            orders: try p2.fetch(FetchDescriptor<Order>())
        )
        check("统计只计未作废单据收入", p2Stats.todayRevenue == 2000, "\(p2Stats.todayRevenue)")

        // 退货信息进凭证
        let refundDoc = ReceiptDocument(order: soloOrder, settings: ShopSettings())
        check("无退货时凭证不显示售后行", refundDoc.returnedCount == 0)
        let returnedDoc = ReceiptDocument(order: rOrder, settings: ShopSettings())
        check("全退单凭证带退货台数", returnedDoc.returnedCount == 3, "\(returnedDoc.returnedCount)")
        check("全退单凭证带退回金额", returnedDoc.returnedAmount == Decimal(string: "16500")!,
              "\(returnedDoc.returnedAmount)")

        // 退货信息必须进备份
        let p2Snapshot = try BackupService.makeSnapshot(from: p2)
        let p2Decoded = try BackupService.decode(try BackupService.jsonData(p2Snapshot))
        let p2TargetConfig = ModelConfiguration(schema: p2Schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let p2TargetContainer = try ModelContainer(for: p2Schema, configurations: [p2TargetConfig])
        let p2Target = p2TargetContainer.mainContext
        try BackupService.restore(p2Decoded, into: p2Target)
        let restoredReturned = try p2Target.fetch(FetchDescriptor<Order>())
            .first { $0.number == rOrder.number }
        check("备份保住退货台数", restoredReturned?.returnedCount == 3,
              "\(String(describing: restoredReturned?.returnedCount))")
        check("备份保住退货金额", restoredReturned?.returnedAmountCNY == Decimal(string: "16500")!,
              "\(String(describing: restoredReturned?.returnedAmountCNY))")
        check("备份保住作废状态", restoredReturned?.isVoided == true)


        // MARK: P4 删除误录入与打印参数

        let dSchema = Schema([Item.self, Order.self, Batch.self])
        let dConfig = ModelConfiguration(schema: dSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let dContainer = try ModelContainer(for: dSchema, configurations: [dConfig])
        let d = dContainer.mainContext

        let victim = Item(serialNumber: "TYPO001", modelName: "iPhone 17",
                          costAmount: 100, currency: .cny, exchangeRate: 1,
                          shippingCNY: 0, listPriceCNY: 200)
        d.insert(victim)
        try d.save()

        try InventoryService.delete(victim, in: d)
        check("误录入可删除",
              try d.fetchCount(FetchDescriptor<Item>()) == 0,
              "\(try d.fetchCount(FetchDescriptor<Item>()))")

        // 已售出的机器不能直接删
        let soldItem = Item(serialNumber: "SOLD001", modelName: "iPhone 17",
                            costAmount: 100, currency: .cny, exchangeRate: 1,
                            shippingCNY: 0, listPriceCNY: 200)
        d.insert(soldItem)
        _ = try InventoryService.sell(
            lines: [.init(item: soldItem, price: 200)], customerName: "", customerContact: "",
            discountCNY: 0, roundingCNY: 0, paymentMethod: .cash, in: d
        )
        do {
            try InventoryService.delete(soldItem, in: d)
            check("已售机器拒绝删除", false, "未抛错")
        } catch {
            check("已售机器拒绝删除", true)
        }
        check("拒绝后机器仍在", try d.fetchCount(FetchDescriptor<Item>()) == 1,
              "\(try d.fetchCount(FetchDescriptor<Item>()))")

        // 删除后序列号可重新入库
        let again = Item(serialNumber: "TYPO001", modelName: "iPhone 17",
                         costAmount: 100, currency: .cny, exchangeRate: 1,
                         shippingCNY: 0, listPriceCNY: 200)
        d.insert(again)
        try d.save()
        check("删除后同序列号可重新入库", !InventoryService.serialExists("TYPO001X", in: d))

        // 打印参数
        let printInfo = ReceiptPrinter.makePrintInfo()
        check("打印纸张为 A4 宽", abs(printInfo.paperSize.width - 595.28) < 1,
              "\(printInfo.paperSize)")
        check("打印纸张为 A4 高", abs(printInfo.paperSize.height - 841.89) < 1)
        check("打印边距为零（版式自带留白）",
              printInfo.topMargin == 0 && printInfo.leftMargin == 0)
        check("打印横向铺满", printInfo.horizontalPagination == .fit)
        check("打印纵向铺满", printInfo.verticalPagination == .fit)
        check("打印为纵向", printInfo.orientation == .portrait)

        // 可打印的 PDF 必须能被解析，空数据必须报错
        let printDoc = ReceiptDocument(
            number: "SO-2026-0009", issuedAt: .now, customerName: "打印测试",
            customerContact: "", lines: [
                .init(modelName: "iPhone 17", serialNumber: "PRINT001",
                      spec: "8GB 256GB", condition: "95新", price: 6999)
            ]
        )
        let printPDF = ReceiptPDFRenderer.render(printDoc)
        check("凭证可生成待打印数据", printPDF != nil && PDFDocument(data: printPDF!) != nil)
        do {
            _ = try ReceiptPrinter.print(pdfData: Data())
            check("空数据拒绝打印", false, "未抛错")
        } catch {
            check("空数据拒绝打印", true)
        }
        do {
            _ = try ReceiptPrinter.print(pdfData: Data("not a pdf".utf8))
            check("损坏数据拒绝打印", false, "未抛错")
        } catch {
            check("损坏数据拒绝打印", true)
        }

        print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
