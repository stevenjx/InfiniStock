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
        draft.modelName = "MacBook Air M2 13\""
        draft.storage = "256GB"
        draft.costCNY = "1000"
        draft.exchangeRate = "420"
        draft.shipping = "120"
        draft.listPrice = "2300000"
        draft.batteryHealth = "78"
        draft.batteryCycles = "890"

        let item = try InventoryService.intake(draft, in: context)
        check("入库规范化序列号", item.serialNumber == "C02ABC123", item.serialNumber)
        check("总进价 = 1000×420+120", item.landedCost == 420120, "\(item.landedCost)")
        check("默认状态为在库", item.status == .inStock)
        check("电池健康写入", item.batteryHealth == 78, "\(item.batteryHealth)")
        check("循环次数写入", item.batteryCycles == 890, "\(item.batteryCycles)")
        check("健康 < 80 判为电池偏弱", item.isBatteryWeak)

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
            unitPrice: 2300000,
            customerName: "张三",
            customerContact: "13800000000",
            in: context
        )
        check("出库后状态为已售", item.status == .sold)
        check("成交价写入", item.soldPrice == 2300000)
        check("订单金额", order.total == 2300000, "\(order.total)")
        check("订单毛利 = 2,300,000-420,120", order.profit == 1879880, "\(order.profit)")
        check("单台毛利一致", item.grossProfit == 1879880)
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
        second.listPrice = "7999"
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
        countBatch.exchangeRate = 420
        countBatch.totalShipping = 100
        countBatch.allocation = .byCount
        context.insert(countBatch)

        for index in 1...3 {
            var d = IntakeDraft()
            d.serialNumber = "CNT00\(index)"
            d.modelName = "MacBook Air M2"
            d.costCNY = "100"
            d.exchangeRate = "420"
            _ = try InventoryService.intake(d, batch: countBatch, in: context)
        }

        let countShares = countBatch.itemList.map(\.shipping).sorted()
        check("按台均摊 3 台", countShares.count == 3, "\(countShares)")
        check("按台均摊合计精确 = 100",
              countBatch.itemList.reduce(Decimal(0)) { $0 + $1.shipping } == 100,
              "\(countBatch.itemList.reduce(Decimal(0)) { $0 + $1.shipping })")
        check("尾差落在最后一台", countShares.last == Decimal(string: "33.34"), "\(String(describing: countShares.last))")
        check("汇率锁定到每台",
              countBatch.itemList.allSatisfy { $0.exchangeRate == 420 })

        let valueBatch = Batch()
        valueBatch.name = "按货值分摊"
        valueBatch.exchangeRate = 400
        valueBatch.totalShipping = 120
        valueBatch.allocation = .byValue
        context.insert(valueBatch)

        for (index, cost) in [100, 200, 300].enumerated() {
            var d = IntakeDraft()
            d.serialNumber = "VAL00\(index)"
            d.modelName = "MacBook Air M1"
            d.costCNY = "\(cost)"
            d.exchangeRate = "400"
            _ = try InventoryService.intake(d, batch: valueBatch, in: context)
        }

        let valueShares = valueBatch.itemList.sorted { $0.serialNumber < $1.serialNumber }.map(\.shipping)
        check("按货值分摊 100/200/300 → 20/40/60",
              valueShares == [20, 40, 60],
              "\(valueShares)")
        check("按货值分摊合计精确 = 120",
              valueBatch.itemList.reduce(Decimal(0)) { $0 + $1.shipping } == 120)

        let baseSum = valueBatch.itemList.reduce(Decimal(0)) { $0 + $1.costCNY * $1.exchangeRate }
        let landedSum = valueBatch.itemList.reduce(Decimal(0)) { $0 + $1.landedCost }
        check("落地成本合计 = 货值 + 运费", landedSum == baseSum + 120, "\(landedSum) vs \(baseSum + 120)")


        // MARK: 统计口径

        let statsSchema = Schema([Item.self, Order.self, Batch.self])
        let statsConfig = ModelConfiguration(schema: statsSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let statsContainer = try ModelContainer(for: statsSchema, configurations: [statsConfig])
        let statsContext = statsContainer.mainContext

        func makeItem(_ serial: String, cost: Decimal, list: Decimal, days: Int, sold: Bool = false) -> Item {
            let item = Item(
                serialNumber: serial, modelName: "MacBook Air M2",
                costCNY: cost, exchangeRate: 1,
                shipping: 0, listPrice: list
            )
            item.inboundAt = calendar.date(byAdding: .day, value: -days, to: .now)!
            if sold {
                item.status = .sold
                item.soldAt = .now
                item.soldPrice = list
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
        bad.modelName = "MacBook Air M2"
        bad.costCNY = "abc"
        do {
            _ = try InventoryService.intake(bad, in: context)
            check("非法进价被拦截", false)
        } catch {
            check("非法进价被拦截", true)
        }


        // MARK: 币种口径（进价人民币 / 其余缅币）

        check("缅币千分位", Decimal(1234567).mmk == "K 1,234,567", Decimal(1234567).mmk)
        check("缅币保留两位小数", Decimal(string: "1234.56")!.mmk == "K 1,234.56", Decimal(string: "1234.56")!.mmk)
        check("人民币进价带 ¥", Decimal(3600).cny.contains("¥"), Decimal(3600).cny)
        check("毛利带正号", Decimal(1879880).signedMMK == "+K 1,879,880", Decimal(1879880).signedMMK)
        check("总进价构成 = 进价折缅币 + 运费",
              item.landedCost == item.costMMK + item.shipping,
              "\(item.landedCost) vs \(item.costMMK + item.shipping)")

        var noRate = IntakeDraft()
        noRate.serialNumber = "NORATE01"
        noRate.modelName = "MacBook Air M2"
        noRate.costCNY = "100"
        do {
            _ = try InventoryService.intake(noRate, in: context)
            check("缺汇率被拦截", false, "未抛错")
        } catch {
            check("缺汇率被拦截", true)
        }

        // MARK: 电池、批次状态、客户等级

        let batterySnapshot = try BackupService.makeSnapshot(from: context)
        let decoded = try BackupService.decode(try BackupService.jsonData(batterySnapshot))
        let dto = decoded.items.first { $0.serialNumber == "C02ABC123" }
        check("备份保留电池健康", dto?.batteryHealth == 78, "\(String(describing: dto?.batteryHealth))")
        check("备份保留循环次数", dto?.batteryCycles == 890, "\(String(describing: dto?.batteryCycles))")

        let stageBatch = Batch()
        stageBatch.name = "状态测试"
        stageBatch.exchangeRate = 400
        stageBatch.totalShipping = 100
        context.insert(stageBatch)
        check("空批次 = 待入库", stageBatch.stage == .empty, stageBatch.stage.rawValue)

        var stageDraft = IntakeDraft()
        stageDraft.serialNumber = "STG001"
        stageDraft.modelName = "MacBook Air M2"
        stageDraft.costCNY = "100"
        stageDraft.exchangeRate = "400"
        _ = try InventoryService.intake(stageDraft, batch: stageBatch, in: context)
        check("入库并分摊后 = 已入库", stageBatch.stage == .settled, stageBatch.stage.rawValue)

        stageBatch.totalShipping = 200
        check("改总运费后 = 待分摊", stageBatch.stage == .pending, stageBatch.stage.rawValue)

        let customerList = CustomerSummary.build(from: try context.fetch(FetchDescriptor<Order>()))
        let zhang = customerList.first { $0.name == "张三" }
        check("单次购买 = 潜力客户", zhang?.tier == .potential, zhang?.tier.rawValue ?? "nil")
        check("客户最近购买型号", zhang?.lastModel == "MacBook Air M2 13\"", zhang?.lastModel ?? "nil")

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
        check("PDF 含合计金额", content.contains("2,300,000"))
        check("PDF 含大写金额", content.contains("贰佰叁拾万元整"))
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
        voidDraft.modelName = "MacBook Pro 14\" M3 Pro"
        voidDraft.costCNY = "5000"
        voidDraft.exchangeRate = "1"
        voidDraft.listPrice = "6999"
        let voidItem = try InventoryService.intake(voidDraft, in: context)
        let voidOrder = try InventoryService.sell(
            items: [voidItem], unitPrice: 6999,
            customerName: "李四", customerContact: "", in: context
        )

        check("撤销前为已售", voidItem.status == .sold)
        try OrderService.void(voidOrder, in: context)
        check("撤销后回到在库", voidItem.status == .inStock)
        check("撤销后清空成交价", voidItem.soldPrice == 0)
        check("撤销后清空售出时间", voidItem.soldAt == nil)
        check("撤销后解除单据关联", voidItem.order == nil)
        check("单据标记作废但保留", voidOrder.voidedAt != nil && voidOrder.total == 6999)

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
        srcBatch.exchangeRate = 412.5
        srcBatch.totalShipping = 333.33
        srcBatch.allocation = .byValue
        source.insert(srcBatch)

        for (index, cost) in ["1234.56", "987.65", "0.01"].enumerated() {
            var d = IntakeDraft()
            d.serialNumber = "BKP00\(index)"
            d.modelName = "MacBook Air M2"
            d.memory = "8GB"
            d.storage = "256GB"
            d.color = "深空黑"
            d.costCNY = cost
            d.exchangeRate = "412.5"
            d.shipping = "0"
            d.listPrice = "8999.99"
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
        let expectedCost = try source.fetch(FetchDescriptor<Item>()).reduce(Decimal(0)) { $0 + $1.landedCost }
        let expectedRevenue = try source.fetch(FetchDescriptor<Item>()).reduce(Decimal(0)) { $0 + $1.soldPrice }
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
        check("金额字符串无损 1234.56", restoredItemA.costCNY == "1234.56", restoredItemA.costCNY)
        let restoredItemC = restored.items.first { $0.serialNumber == "BKP002" }!
        check("小额 0.01 无损", restoredItemC.costCNY == "0.01", restoredItemC.costCNY)
        let restoredOrder = restored.orders.first!
        check("成交价无损 8888.88", restoredOrder.total == "8888.88", restoredOrder.total)
        check("单据关联序列号", restoredOrder.itemSerials == ["BKP000"], "\(restoredOrder.itemSerials)")
        check("毛利字段非空", !restoredOrder.profit.isEmpty)

        // 回灌到空库
        let targetConfig = ModelConfiguration(schema: backupSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let targetContainer = try ModelContainer(for: backupSchema, configurations: [targetConfig])
        let target = targetContainer.mainContext
        try BackupService.restore(restored, into: target)

        let restoredItems = try target.fetch(FetchDescriptor<Item>())
        check("恢复后台数一致", restoredItems.count == expectedItemCount, "\(restoredItems.count)")
        check("恢复后序列号集合一致", Set(restoredItems.map(\.serialNumber)) == expectedSerials)
        check("恢复后落地成本合计一致",
              restoredItems.reduce(Decimal(0)) { $0 + $1.landedCost } == expectedCost,
              "\(restoredItems.reduce(Decimal(0)) { $0 + $1.landedCost }) vs \(expectedCost)")
        check("恢复后成交额合计一致",
              restoredItems.reduce(Decimal(0)) { $0 + $1.soldPrice } == expectedRevenue)

        let restoredSoldItem = restoredItems.first { $0.serialNumber == "BKP000" }!
        check("恢复后状态为已售", restoredSoldItem.status == .sold)
        check("恢复后单据挂回机器", restoredSoldItem.order?.number == soldOrder.number)
        check("恢复后批次挂回机器", restoredSoldItem.batch?.name == "备份批")
        check("恢复后汇率保留四位",
              restoredSoldItem.batch?.exchangeRate == Decimal(string: "412.5"),
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
        check("CSV 含表头", csvText.contains("序列号") && csvText.contains("总进价(缅币)"))
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
                serialNumber: serial, modelName: "MacBook Air M2",
                costCNY: cost, exchangeRate: 1,
                shipping: 0, listPrice: list
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
            discount: 200, rounding: 88, paymentMethod: .transfer,
            in: p1
        )

        check("单号为 SO-年-四位序号",
              p1Order.number.hasPrefix("SO-\(Calendar.current.component(.year, from: .now))-"),
              p1Order.number)
        check("首单序号为 0001", p1Order.number.hasSuffix("-0001"), p1Order.number)
        check("小计 = 16500", p1Order.subtotal == 16500, "\(p1Order.subtotal)")
        check("应收 = 16500-200-88 = 16212", p1Order.total == 16212, "\(p1Order.total)")
        check("毛利计入折扣", p1Order.profit == 16212 - 12000, "\(p1Order.profit)")
        check("收款方式保存", p1Order.paymentMethod == .transfer)
        check("逐台价格分别写入",
              a.soldPrice == 6800 && b.soldPrice == 5500 && c.soldPrice == 4200,
              "\(a.soldPrice)/\(b.soldPrice)/\(c.soldPrice)")

        // 第二单、第三单必须连号
        for serial in ["P1D", "P1E"] {
            let item = p1Item(serial, cost: 1000, list: 2000)
            let order = try InventoryService.sell(
                lines: [.init(item: item, price: 2000)],
                customerName: "", customerContact: "",
                discount: 0, rounding: 0, paymentMethod: .cash, in: p1
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
                discount: 200, rounding: 0, paymentMethod: .cash, in: p1
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
        check("备份保住折扣", restoredOrders.first?.discount == 200, "\(String(describing: restoredOrders.first?.discount))")
        check("备份保住抹零", restoredOrders.first?.rounding == 88, "\(String(describing: restoredOrders.first?.rounding))")
        check("备份保住应收", restoredOrders.first?.total == 16212)
        check("备份保住收款方式", restoredOrders.first?.paymentMethod == .transfer)
        check("备份保住单号序号", restoredOrders.first?.sequenceNumber == 1, "\(String(describing: restoredOrders.first?.sequenceNumber))")
        check("备份保住单号文本", restoredOrders.first?.number.hasSuffix("-0001") == true)

        // 恢复后继续下单必须接着 0002，不能重号
        let nextItem = Item(serialNumber: "P1G", modelName: "MacBook Air M2", costCNY: 100, exchangeRate: 1, shipping: 0, listPrice: 200)
        p1Target.insert(nextItem)
        let nextOrder = try InventoryService.sell(
            lines: [.init(item: nextItem, price: 200)],
            customerName: "", customerContact: "",
            discount: 0, rounding: 0, paymentMethod: .cash, in: p1Target
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
        let tricky = "\u{FEFF}序列号,型号,颜色\r\nA1,\"MacBook Air M2, Pro\",\"深空\"\"黑\"\r\nA2,MacBook Air M1,银色\r\n"
        let trickyRows = CSVImporter.parseRows(tricky)
        check("CSV 去 BOM", trickyRows.first?.first == "序列号", "\(String(describing: trickyRows.first?.first))")
        check("CSV 字段内逗号", trickyRows[1][1] == "MacBook Air M2, Pro", trickyRows[1][1])
        check("CSV 双引号转义", trickyRows[1][2] == "深空\"黑", trickyRows[1][2])
        check("CSV 行数正确", trickyRows.count == 3, "\(trickyRows.count)")

        // 100 行含 3 行错误
        var lines: [String] = ["序列号,型号,存储,成色,进价,汇率,运费,标价"]
        var errorLines: [Int] = []
        for index in 1...100 {
            let line = index + 1
            if index == 7 {
                lines.append(",MacBook Air M2,256GB,95新,1000,1,0,6999")         // 序列号为空
                errorLines.append(line)
            } else if index == 23 {
                lines.append("IMP023,MacBook Air M2,256GB,95新,abc,1,0,6999")    // 进价非法
                errorLines.append(line)
            } else if index == 88 {
                lines.append("IMP001,MacBook Air M2,256GB,95新,1000,1,0,6999")   // 与第 2 行重复
                errorLines.append(line)
            } else {
                lines.append(String(format: "IMP%03d,MacBook Air M2,256GB,95新,1000,1.5,20,6999", index))
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
        check("总进价 = 1000×1.5+20", importedItem?.landedCost == 1520,
              "\(String(describing: importedItem?.landedCost))")
        check("标价导入正确", importedItem?.listPrice == 6999)
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
        let badHeader = "型号,存储\nMacBook Air M2,256GB\n"
        let badPreview = CSVImporter.preview(csv: Data(badHeader.utf8), in: csvContext)
        check("缺列直接拒绝", badPreview.rows.isEmpty && badPreview.issues.count == 1)

        // 成色非法 + 汇率为 0
        let wrongValues = "序列号,型号,进价,成色,汇率\nX1,MacBook Air M2,1000,九五新,420\nX2,MacBook Air M2,1000,95新,0\n"
        let wrongPreview = CSVImporter.preview(csv: Data(wrongValues.utf8), in: csvContext)
        check("非法成色被拦", wrongPreview.issues.contains { $0.field == "成色" })
        check("汇率为 0 被拦", wrongPreview.issues.contains { $0.field == "汇率" })
        check("无可用行", wrongPreview.rows.count == 0)

        // 错误清单可导出
        let issueCSV = String(decoding: CSVImporter.issuesCSV(csvPreview.issues), as: UTF8.self)
        check("错误清单带表头", issueCSV.contains("行号,字段,原因"))
        check("错误清单含错误行号", issueCSV.contains("24"))

        // 带批次导入会重算分摊
        let importBatch = Batch()
        importBatch.name = "导入批"
        importBatch.exchangeRate = 1
        importBatch.totalShipping = 100
        importBatch.allocation = .byCount
        csvContext.insert(importBatch)

        let batchCSV = "序列号,型号,进价,汇率\nBATCH1,MacBook Air M2,1000,1\nBATCH2,MacBook Air M2,1000,1\n"
        let batchPreview = CSVImporter.preview(csv: Data(batchCSV.utf8), in: csvContext)
        _ = try CSVImporter.commit(batchPreview, batch: importBatch, in: csvContext)
        check("导入进批次后运费分摊",
              importBatch.itemList.reduce(Decimal(0)) { $0 + $1.shipping } == 100,
              "\(importBatch.itemList.reduce(Decimal(0)) { $0 + $1.shipping })")


        // MARK: P2 部分退货

        let p2Schema = Schema([Item.self, Order.self, Batch.self])
        let p2Config = ModelConfiguration(schema: p2Schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let p2Container = try ModelContainer(for: p2Schema, configurations: [p2Config])
        let p2 = p2Container.mainContext

        func p2Item(_ serial: String, cost: Decimal, list: Decimal) -> Item {
            let item = Item(serialNumber: serial, modelName: "MacBook Air M2", costCNY: cost,
                            exchangeRate: 1, shipping: 0, listPrice: list)
            p2.insert(item)
            return item
        }

        let r1 = p2Item("RT1", cost: 5000, list: 6800)
        let r2 = p2Item("RT2", cost: 4000, list: 5500)
        let r3 = p2Item("RT3", cost: 3000, list: 4200)

        let rOrder = try InventoryService.sell(
            lines: [.init(item: r1, price: 6800), .init(item: r2, price: 5500), .init(item: r3, price: 4200)],
            customerName: "钱七", customerContact: "13700001111",
            discount: 200, rounding: 88, paymentMethod: .cash, in: p2
        )
        check("退货前应收 16212", rOrder.total == 16212, "\(rOrder.total)")
        check("退货前毛利 4212", rOrder.profit == 4212, "\(rOrder.profit)")

        // 退一台 4200 的
        let refund = try OrderService.returnItems([r3], from: rOrder, in: p2)
        check("退回金额 = 该台成交价", refund == 4200, "\(refund)")
        check("退后剩余两台", rOrder.itemList.count == 2, "\(rOrder.itemList.count)")
        check("退后小计 12300", rOrder.subtotal == 12300, "\(rOrder.subtotal)")

        let expectedDiscountRatio = (Decimal(12300) / Decimal(16500)).rounded(6)
        let expectedDiscount = (Decimal(200) * expectedDiscountRatio).rounded(2)
        let expectedRounding = (Decimal(88) * expectedDiscountRatio).rounded(2)
        check("折扣按比例保留", rOrder.discount == expectedDiscount,
              "\(rOrder.discount) vs \(expectedDiscount)")
        check("抹零按比例保留", rOrder.rounding == expectedRounding,
              "\(rOrder.rounding) vs \(expectedRounding)")
        check("退后应收 = 小计-折扣-抹零",
              rOrder.total == (Decimal(12300) - rOrder.discount - rOrder.rounding).rounded(2),
              "\(rOrder.total)")
        check("退后毛利按剩余成本重算",
              rOrder.profit == (rOrder.total - 9000).rounded(2),
              "\(rOrder.profit)")
        check("退货台数累计", rOrder.returnedCount == 1)
        check("退货金额累计", rOrder.returnedAmount == 4200)
        check("单据仍有效", !rOrder.isVoided)
        check("状态显示部分退货", rOrder.statusLabel == "部分退货", rOrder.statusLabel)

        // 退回的机器应回到在库且清空成交信息
        check("退回机器回到在库", r3.status == .inStock)
        check("退回机器清空成交价", r3.soldPrice == 0)
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
        check("全退后应收归零", rOrder.total == 0, "\(rOrder.total)")
        check("全退后毛利归零", rOrder.profit == 0, "\(rOrder.profit)")
        check("全退后折扣归零", rOrder.discount == 0 && rOrder.rounding == 0)
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
            customerContact: "", discount: 0, rounding: 0, paymentMethod: .cash, in: p2
        )
        check("其他单据不受影响", soloOrder.total == 2000 && !soloOrder.isVoided)

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
        check("备份保住退货金额", restoredReturned?.returnedAmount == Decimal(string: "16500")!,
              "\(String(describing: restoredReturned?.returnedAmount))")
        check("备份保住作废状态", restoredReturned?.isVoided == true)


        // MARK: P4 删除误录入与打印参数

        let dSchema = Schema([Item.self, Order.self, Batch.self])
        let dConfig = ModelConfiguration(schema: dSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let dContainer = try ModelContainer(for: dSchema, configurations: [dConfig])
        let d = dContainer.mainContext

        let victim = Item(serialNumber: "TYPO001", modelName: "MacBook Air M2",
                          costCNY: 100, exchangeRate: 1,
                          shipping: 0, listPrice: 200)
        d.insert(victim)
        try d.save()

        try InventoryService.delete(victim, in: d)
        check("误录入可删除",
              try d.fetchCount(FetchDescriptor<Item>()) == 0,
              "\(try d.fetchCount(FetchDescriptor<Item>()))")

        // 已售出的机器不能直接删
        let soldItem = Item(serialNumber: "SOLD001", modelName: "MacBook Air M2",
                            costCNY: 100, exchangeRate: 1,
                            shipping: 0, listPrice: 200)
        d.insert(soldItem)
        _ = try InventoryService.sell(
            lines: [.init(item: soldItem, price: 200)], customerName: "", customerContact: "",
            discount: 0, rounding: 0, paymentMethod: .cash, in: d
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
        let again = Item(serialNumber: "TYPO001", modelName: "MacBook Air M2",
                         costCNY: 100, exchangeRate: 1,
                         shipping: 0, listPrice: 200)
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
                .init(modelName: "MacBook Air M2", serialNumber: "PRINT001",
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


        // MARK: U4 仪表盘口径

        let dashSchema = Schema([Item.self, Order.self, Batch.self])
        let dashConfig = ModelConfiguration(schema: dashSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let dashContainer = try ModelContainer(for: dashSchema, configurations: [dashConfig])
        let dash = dashContainer.mainContext

        func dashItem(_ serial: String, cost: Decimal, list: Decimal) -> Item {
            let item = Item(serialNumber: serial, modelName: "MacBook Air M2", costCNY: cost,
                            exchangeRate: 1, shipping: 0, listPrice: list)
            dash.insert(item)
            return item
        }

        // 今天两单（不同收款方式），一单作废
        let d1 = dashItem("DSH1", cost: 3000, list: 5000)
        _ = try InventoryService.sell(lines: [.init(item: d1, price: 5000)], customerName: "甲", customerContact: "",
                                      discount: 0, rounding: 0, paymentMethod: .cash, in: dash)
        let d2 = dashItem("DSH2", cost: 4000, list: 6000)
        _ = try InventoryService.sell(lines: [.init(item: d2, price: 6000)], customerName: "乙", customerContact: "",
                                      discount: 0, rounding: 0, paymentMethod: .transfer, in: dash)
        let d3 = dashItem("DSH3", cost: 1000, list: 2000)
        let voided = try InventoryService.sell(lines: [.init(item: d3, price: 2000)], customerName: "丙", customerContact: "",
                                               discount: 0, rounding: 0, paymentMethod: .card, in: dash)
        try OrderService.void(voided, in: dash)

        // 一台成本高于标价（用于低于成本告警）
        _ = dashItem("DSH4", cost: 9000, list: 5000)
        // 一台超期
        let stale = dashItem("DSH5", cost: 1500, list: 2500)
        stale.inboundAt = Calendar.current.date(byAdding: .day, value: -120, to: .now) ?? .now
        try dash.save()

        let dashStats = InventoryStatistics(
            items: try dash.fetch(FetchDescriptor<Item>()),
            orders: try dash.fetch(FetchDescriptor<Order>())
        )

        check("仪表盘-今日销售额含两笔有效单", dashStats.todayRevenue == 11000, "\(dashStats.todayRevenue)")
        check("仪表盘-今日毛利 = 2000+2000", dashStats.todayProfit == 4000, "\(dashStats.todayProfit)")
        check("仪表盘-作废单不计入", !dashStats.dailyPoints.isEmpty && dashStats.dailyPoints.last!.revenue == 11000,
              "\(dashStats.dailyPoints.last?.revenue ?? -1)")
        check("仪表盘-7 天序列补齐", dashStats.dailyPoints.count == 7, "\(dashStats.dailyPoints.count)")
        check("仪表盘-序列按日升序",
              dashStats.dailyPoints.map(\.date) == dashStats.dailyPoints.map(\.date).sorted())
        check("仪表盘-今日点位有 2 笔", dashStats.dailyPoints.last?.count == 2,
              "\(dashStats.dailyPoints.last?.count ?? -1)")

        let payments = Dictionary(uniqueKeysWithValues: dashStats.paymentSlices.map { ($0.method, $0.amount) })
        check("仪表盘-现金 5000", payments[.cash] == 5000, "\(String(describing: payments[.cash]))")
        check("仪表盘-转账 6000", payments[.transfer] == 6000, "\(String(describing: payments[.transfer]))")
        check("仪表盘-作废单的收款方式不出现", payments[.card] == nil)

        check("仪表盘-低于成本告警命中 1 台", dashStats.lowMarginItems.count == 1, "\(dashStats.lowMarginItems.count)")
        check("仪表盘-告警机器正确", dashStats.lowMarginItems.first?.serialNumber == "DSH4")
        check("仪表盘-超期告警命中", dashStats.overdueItems.contains { $0.serialNumber == "DSH5" })
        check("仪表盘-近7天摘要与末点一致",
              dashStats.summary(days: 1).revenue == 11000,
              "\(dashStats.summary(days: 1).revenue)")
        check("仪表盘-毛利率 4000/11000", dashStats.todayMarginRate == Decimal(string: "36.4"),
              "\(String(describing: dashStats.todayMarginRate))")

        // MARK: P3 库存周转

        let velSchema = Schema([Item.self, Order.self, Batch.self])
        let velConfig = ModelConfiguration(schema: velSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let velContainer = try ModelContainer(for: velSchema, configurations: [velConfig])
        let vel = velContainer.mainContext

        func daysAgo(_ n: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -n, to: .now) ?? .now
        }

        @discardableResult
        func velItem(
            _ serial: String,
            model: String,
            cost: Decimal,
            inStock: Bool,
            soldDaysAgo: Int? = nil,
            inboundDaysAgo: Int = 10
        ) -> Item {
            let item = Item(serialNumber: serial, modelName: model, costCNY: cost,
                            exchangeRate: 1, shipping: 0, listPrice: 3000)
            item.inboundAt = daysAgo(inboundDaysAgo)
            if !inStock, let soldDaysAgo {
                item.status = .sold
                item.soldAt = daysAgo(soldDaysAgo)
            }
            vel.insert(item)
            return item
        }

        // Alpha：窗口内卖 2 台、在库 2 台 → 2 × 30 ÷ 2 = 30 天
        velItem("V1", model: "Alpha", cost: 1000, inStock: false, soldDaysAgo: 5, inboundDaysAgo: 20)
        velItem("V2", model: "Alpha", cost: 1000, inStock: false, soldDaysAgo: 25, inboundDaysAgo: 40)
        velItem("V3", model: "Alpha", cost: 1000, inStock: true)
        velItem("V4", model: "Alpha", cost: 1000, inStock: true)
        // 40 天前卖的落在窗口外，不计入 30 天售速
        velItem("V5", model: "Alpha", cost: 1000, inStock: false, soldDaysAgo: 40, inboundDaysAgo: 60)
        // Beta：3 台在库、一台没卖出去，其中一台库龄 100 天
        velItem("V6", model: "Beta", cost: 2000, inStock: true)
        velItem("V7", model: "Beta", cost: 2000, inStock: true)
        velItem("V8", model: "Beta", cost: 2000, inStock: true, inboundDaysAgo: 100)

        let velStats = InventoryStatistics(items: try vel.fetch(FetchDescriptor<Item>()), orders: [])

        check("周转-窗口 30 天", velStats.windowDays == 30, "\(velStats.windowDays)")
        check("周转-窗口内售出 2 台", velStats.soldInWindow == 2, "\(velStats.soldInWindow)")
        check("周转-可售天数 = 5×30÷2 = 75", velStats.daysOfSupply == 75,
              "\(String(describing: velStats.daysOfSupply))")
        check("周转-卖不动的型号排最前", velStats.velocity.first?.model == "Beta",
              velStats.velocity.first?.model ?? "nil")
        check("周转-卖不动的型号没有可售天数", velStats.velocity.first?.daysOfSupply == nil)
        check("周转-Alpha 可售 30 天", velStats.velocity.last?.daysOfSupply == 30,
              "\(String(describing: velStats.velocity.last?.daysOfSupply))")
        check("周转-滞销占用只算超期那台", velStats.slowMovingValue == 2000, "\(velStats.slowMovingValue)")
        check("周转-滞销台数 1", velStats.slowMovingCount == 1, "\(velStats.slowMovingCount)")

        // 完全没有成交时不能报 0 天——那是「马上卖完」，与实际相反
        let noSales = InventoryStatistics(
            items: [velItem("V9", model: "Gamma", cost: 500, inStock: true)],
            orders: []
        )
        check("周转-无成交时不给可售天数", noSales.daysOfSupply == nil)
        check("周转-无成交型号标记为卖不动", noSales.velocity.first?.daysOfSupply == nil)


        // MARK: U5 客户聚合

        let cusSchema = Schema([Item.self, Order.self, Batch.self])
        let cusConfig = ModelConfiguration(schema: cusSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let cusContainer = try ModelContainer(for: cusSchema, configurations: [cusConfig])
        let cus = cusContainer.mainContext

        func cusItem(_ serial: String) -> Item {
            let item = Item(serialNumber: serial, modelName: "MacBook Air M2", costCNY: 1000,
                            exchangeRate: 1, shipping: 0, listPrice: 2000)
            cus.insert(item)
            return item
        }

        _ = try InventoryService.sell(lines: [.init(item: cusItem("C1"), price: 2000)],
                                      customerName: "张三", customerContact: "13800000000",
                                      discount: 0, rounding: 0, paymentMethod: .cash, in: cus)
        _ = try InventoryService.sell(lines: [.init(item: cusItem("C2"), price: 3000)],
                                      customerName: "张三", customerContact: "13800000000",
                                      discount: 0, rounding: 0, paymentMethod: .cash, in: cus)
        // 同名不同电话，必须算两个人
        _ = try InventoryService.sell(lines: [.init(item: cusItem("C3"), price: 1500)],
                                      customerName: "张三", customerContact: "13900000000",
                                      discount: 0, rounding: 0, paymentMethod: .cash, in: cus)
        // 散客（无姓名），不进客户列表
        _ = try InventoryService.sell(lines: [.init(item: cusItem("C4"), price: 2500)],
                                      customerName: "", customerContact: "",
                                      discount: 0, rounding: 0, paymentMethod: .cash, in: cus)
        // 作废单不计入客户
        let voidCustomerOrder = try InventoryService.sell(lines: [.init(item: cusItem("C5"), price: 4000)],
                                                          customerName: "李四", customerContact: "13700000000",
                                                          discount: 0, rounding: 0, paymentMethod: .cash, in: cus)
        try OrderService.void(voidCustomerOrder, in: cus)

        let customerOrders = try cus.fetch(FetchDescriptor<Order>())
        let summaries = CustomerSummary.build(from: customerOrders)

        check("客户-同名同电话合并为 1 人", summaries.filter { $0.contact == "13800000000" }.count == 1)
        check("客户-合并后 2 张单", summaries.first { $0.contact == "13800000000" }?.orderCount == 2,
              "\(String(describing: summaries.first { $0.contact == "13800000000" }?.orderCount))")
        check("客户-合并后累计 5000",
              summaries.first { $0.contact == "13800000000" }?.revenue == 5000,
              "\(String(describing: summaries.first { $0.contact == "13800000000" }?.revenue))")
        check("客户-同名异电话算两人",
              summaries.filter { $0.name == "张三" }.count == 2,
              "\(summaries.filter { $0.name == "张三" }.count)")
        check("客户-散客不进列表", summaries.allSatisfy { !$0.name.isEmpty })
        check("客户-作废单客户不出现", !summaries.contains { $0.name == "李四" })
        check("客户-按消费额降序",
              summaries.map(\.revenue) == summaries.map(\.revenue).sorted(by: >))
        check("客户-台数正确", summaries.first { $0.contact == "13800000000" }?.machineCount == 2)

        // MARK: 待办中心

        let todoSchema = Schema([Item.self, Order.self, Batch.self])
        let todoConfig = ModelConfiguration(schema: todoSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let todoContainer = try ModelContainer(for: todoSchema, configurations: [todoConfig])
        let todoCtx = todoContainer.mainContext

        func todoItem(
            _ serial: String, price: Decimal, cost: Decimal = 1000,
            health: Int = 92, cycles: Int = 200, daysAgo: Int = 0
        ) -> Item {
            let item = Item(serialNumber: serial, modelName: "MacBook Air M2",
                            costCNY: cost, exchangeRate: 1, shipping: 0, listPrice: price,
                            batteryHealth: health, batteryCycles: cycles)
            todoCtx.insert(item)
            if daysAgo > 0 {
                item.inboundAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            }
            return item
        }

        _ = todoItem("T-UNPRICED", price: 0)
        _ = todoItem("T-CHEAP", price: 800, cost: 1000)
        // 电池偏弱 + 库龄超期：同一台机器两条待办，用于验证金额去重
        _ = todoItem("T-BATT", price: 2000, health: 76, cycles: 900, daysAgo: 70)
        _ = todoItem("T-AGED", price: 2000, daysAgo: 75)
        _ = todoItem("T-OK", price: 2000)
        let soldTodo = todoItem("T-SOLD", price: 2000, health: 70)
        soldTodo.status = .sold
        soldTodo.soldAt = .now

        // 批次待分摊
        let pendingBatch = Batch()
        pendingBatch.name = "曼德勒补货"
        pendingBatch.exchangeRate = 400
        todoCtx.insert(pendingBatch)
        var pendingDraft = IntakeDraft()
        pendingDraft.serialNumber = "T-BATCH1"
        pendingDraft.modelName = "MacBook Pro 14"
        pendingDraft.costCNY = "1000"
        pendingDraft.exchangeRate = "400"
        pendingDraft.listPrice = "600000"
        _ = try InventoryService.intake(pendingDraft, batch: pendingBatch, in: todoCtx)
        pendingBatch.totalShipping = 12000

        // 已分摊完的批次不该出现
        let settledBatch = Batch()
        settledBatch.name = "已摊批次"
        settledBatch.exchangeRate = 400
        todoCtx.insert(settledBatch)
        var settledDraft = IntakeDraft()
        settledDraft.serialNumber = "T-BATCH2"
        settledDraft.modelName = "MacBook Pro 14"
        settledDraft.costCNY = "1000"
        settledDraft.exchangeRate = "400"
        settledDraft.listPrice = "600000"
        _ = try InventoryService.intake(settledDraft, batch: settledBatch, in: todoCtx)

        let todos = TodoCenter.build(
            items: try todoCtx.fetch(FetchDescriptor<Item>()),
            batches: try todoCtx.fetch(FetchDescriptor<Batch>())
        )
        func hasTodo(_ kind: TodoKind, _ serial: String) -> Bool {
            todos.contains { $0.kind == kind && $0.subtitle == serial }
        }

        check("待办-未标价", hasTodo(.unpriced, "T-UNPRICED"))
        check("待办-标价低于成本",
              todos.first { $0.subtitle == "T-CHEAP" }?.kind == .negativeMargin)
        check("待办-亏本金额 = 成本 − 标价",
              todos.first { $0.subtitle == "T-CHEAP" }?.amount == 200,
              "\(String(describing: todos.first { $0.subtitle == "T-CHEAP" }?.amount))")
        check("待办-电池偏弱", hasTodo(.weakBattery, "T-BATT"))
        check("待办-库龄超期", hasTodo(.aged, "T-AGED"))
        check("待办-正常机器不进待办", !todos.contains { $0.subtitle == "T-OK" })
        check("待办-已售机器不进待办", !todos.contains { $0.subtitle == "T-SOLD" })
        check("待办-批次待分摊",
              todos.contains { $0.kind == .pendingAllocation && $0.amount == 12000 },
              "\(todos.filter { $0.kind == .pendingAllocation }.map(\.amount))")
        check("待办-已分摊批次不进待办", !todos.contains { $0.subtitle == "已摊批次" })
        check("待办-先堵漏后慢销",
              todos.first?.kind == .pendingAllocation && todos.last?.kind == .aged,
              "\(todos.map(\.kind.title))")
        check("待办-涉及成本按机器去重", TodoCenter.involvedCost(todos) == 4000,
              "\(TodoCenter.involvedCost(todos))")
        check("待办-涉及台数按机器去重", TodoCenter.involvedCount(todos) == 4,
              "\(TodoCenter.involvedCount(todos))")
        check("待办-分类计数", TodoCenter.count(todos, of: .aged) == 2,
              "\(TodoCenter.count(todos, of: .aged))")

        // MARK: 零价成交

        let zeroPriceItem = todoItem("T-ZERO", price: 2000)
        do {
            _ = try InventoryService.sell(
                lines: [.init(item: zeroPriceItem, price: 0)],
                customerName: "", customerContact: "",
                discount: 0, rounding: 0, paymentMethod: .cash, in: todoCtx
            )
            check("零价成交被拦截", false, "未抛错")
        } catch {
            check("零价成交被拦截", true)
        }
        check("零价成交不改变机器状态", zeroPriceItem.status == .inStock, zeroPriceItem.status.label)

        // MARK: 赊账与收款

        let creditItem = todoItem("T-CREDIT", price: 2000)
        let creditOrder = try InventoryService.sell(
            lines: [.init(item: creditItem, price: 2000)],
            customerName: "吴先生", customerContact: "0955000111",
            discount: 0, rounding: 0, paymentMethod: .cash,
            paid: 1200, in: todoCtx
        )
        check("赊账-应收 2000", creditOrder.total == 2000, "\(creditOrder.total)")
        check("赊账-已收 1200", creditOrder.collected == 1200, "\(creditOrder.collected)")
        check("赊账-未收 800", creditOrder.outstanding == 800, "\(creditOrder.outstanding)")
        check("赊账-毛利仍按应收算", creditOrder.profit == 1000, "\(creditOrder.profit)")
        check("赊账-标记为欠款", creditOrder.isOutstanding)

        try OrderService.collect(300, for: creditOrder, in: todoCtx)
        check("收款-累加到 1500", creditOrder.collected == 1500, "\(creditOrder.collected)")
        check("收款-剩余 500", creditOrder.outstanding == 500, "\(creditOrder.outstanding)")

        do {
            try OrderService.collect(600, for: creditOrder, in: todoCtx)
            check("收款-超过未收被拒", false, "未抛错")
        } catch {
            check("收款-超过未收被拒", true)
        }

        try OrderService.collect(500, for: creditOrder, in: todoCtx)
        check("收款-收讫后不再欠", !creditOrder.isOutstanding)
        do {
            try OrderService.collect(1, for: creditOrder, in: todoCtx)
            check("收款-收讫后拒绝再收", false, "未抛错")
        } catch {
            check("收款-收讫后拒绝再收", true)
        }

        // 实收超过应收只记到应收为止：多给的是找零，不该进账
        let overpaidItem = todoItem("T-OVERPAID", price: 1000)
        let overpaidOrder = try InventoryService.sell(
            lines: [.init(item: overpaidItem, price: 1000)],
            customerName: "", customerContact: "",
            discount: 0, rounding: 0, paymentMethod: .cash,
            paid: 1500, in: todoCtx
        )
        check("赊账-多收只记应收", overpaidOrder.collected == 1000, "\(overpaidOrder.collected)")

        // 老单据没有 paidAmount，必须视为已全额收讫，否则升级当天全变欠款
        let legacyOrder = Order()
        legacyOrder.number = "SO-LEGACY"
        legacyOrder.total = 5000
        // 模拟升级前的老单据：日期在很久以前，不落在报表的近 7 天窗口里
        legacyOrder.createdAt = Calendar.current.date(byAdding: .day, value: -60, to: .now) ?? .now
        todoCtx.insert(legacyOrder)
        check("旧单据视为已付清", legacyOrder.collected == 5000 && legacyOrder.outstanding == 0,
              "collected=\(legacyOrder.collected) outstanding=\(legacyOrder.outstanding)")

        // 欠款进待办
        let owingItem = todoItem("T-OWING", price: 3000)
        let owingOrder = try InventoryService.sell(
            lines: [.init(item: owingItem, price: 3000)],
            customerName: "吴先生", customerContact: "0955000111",
            discount: 0, rounding: 0, paymentMethod: .transfer,
            paid: 1000, in: todoCtx
        )
        let todosWithOrders = TodoCenter.build(
            items: try todoCtx.fetch(FetchDescriptor<Item>()),
            batches: try todoCtx.fetch(FetchDescriptor<Batch>()),
            orders: try todoCtx.fetch(FetchDescriptor<Order>())
        )
        check("待办-应收未收进清单",
              todosWithOrders.contains { $0.kind == .outstanding && $0.amount == 2000 },
              "\(todosWithOrders.filter { $0.kind == .outstanding }.map(\.amount))")
        check("待办-已收讫的单不进清单",
              !todosWithOrders.contains { $0.kind == .outstanding && $0.subtitle == creditOrder.number })

        let creditStats = InventoryStatistics(
            items: try todoCtx.fetch(FetchDescriptor<Item>()),
            orders: try todoCtx.fetch(FetchDescriptor<Order>())
        )
        check("统计-应收未收合计 2000", creditStats.outstandingAmount == 2000,
              "\(creditStats.outstandingAmount)")
        check("统计-欠款单数 1", creditStats.outstandingOrderCount == 1,
              "\(creditStats.outstandingOrderCount)")

        // 备份要保住实收，否则恢复后欠款凭空消失
        let creditSnapshot = try BackupService.makeSnapshot(from: todoCtx)
        check("备份-格式版本 5", creditSnapshot.formatVersion == 5, "\(creditSnapshot.formatVersion)")
        let creditDecoded = try BackupService.decode(try BackupService.jsonData(creditSnapshot))
        let owingDTO = creditDecoded.orders.first { $0.number == owingOrder.number }
        check("备份-保留实收", owingDTO?.paidAmount == "1000",
              owingDTO?.paidAmount ?? "nil")

        // MARK: 期间报表

        // 作废单必须整张排除，否则"这个月赚多少"会被废单污染
        let voidedForReport = try InventoryService.sell(
            lines: [.init(item: todoItem("T-REPORTVOID", price: 5000), price: 5000)],
            customerName: "作废测试", customerContact: "",
            discount: 0, rounding: 0, paymentMethod: .cash, in: todoCtx
        )
        try OrderService.void(voidedForReport, in: todoCtx)

        let cal = Calendar.current
        let reportEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        let reportStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now)) ?? .now
        let period = PeriodReport(
            orders: try todoCtx.fetch(FetchDescriptor<Order>()),
            start: reportStart,
            end: reportEnd
        )

        check("报表-只算有效单", period.orderCount == 3, "\(period.orderCount)")
        check("报表-销售额 6000", period.revenue == 6000, "\(period.revenue)")
        check("报表-实收 4000", period.collected == 4000, "\(period.collected)")
        check("报表-未收 2000", period.outstanding == 2000, "\(period.outstanding)")
        check("报表-毛利 3000", period.profit == 3000, "\(period.profit)")
        check("报表-毛利率 50%", period.marginRate == 50, "\(String(describing: period.marginRate))")
        check("报表-台数 3", period.machineCount == 3, "\(period.machineCount)")
        check("报表-客单价 2000", period.averageOrder == 2000, "\(period.averageOrder)")
        check("报表-同型号合并", period.byModel.count == 1 && period.byModel.first?.count == 3,
              "\(period.byModel.map { "\($0.model)=\($0.count)" })")
        check("报表-按毛利降序",
              period.byModel.map(\.profit) == period.byModel.map(\.profit).sorted(by: >))
        check("报表-每日补零", period.byDay.count == 7, "\(period.byDay.count)")

        // 边界：左闭右开，月末最后一单不会被算进下个月
        var marchComponents = DateComponents()
        marchComponents.year = 2026
        marchComponents.month = 3
        marchComponents.day = 15
        if let march = cal.date(from: marchComponents) {
            let bounds = ReportRange.thisMonth.bounds(now: march, calendar: cal)
            check("报表-本月起点是 3 月 1 日",
                  cal.component(.day, from: bounds.start) == 1 && cal.component(.month, from: bounds.start) == 3,
                  "\(bounds.start)")
            check("报表-本月终点是 4 月 1 日",
                  cal.component(.day, from: bounds.end) == 1 && cal.component(.month, from: bounds.end) == 4,
                  "\(bounds.end)")

            let lastMonth = ReportRange.lastMonth.bounds(now: march, calendar: cal)
            check("报表-上月是 2 月",
                  cal.component(.month, from: lastMonth.start) == 2,
                  "\(lastMonth.start)")
        }

        // 报表 CSV 带 BOM，Excel 打开中文不乱码
        let reportCSV = PeriodReport.csv(period, orders: try todoCtx.fetch(FetchDescriptor<Order>()))
        check("报表-导出带 BOM", reportCSV.hasPrefix("\u{FEFF}"))
        check("报表-导出含表头", reportCSV.contains("单号,日期,客户"))
        check("报表-导出行数 = 台数", reportCSV.components(separatedBy: "\r\n").count == 4,
              "\(reportCSV.components(separatedBy: "\r\n").count)")

        // MARK: 回本汇率与汇率风险

        // 进价 ¥3,600，运费 K 55,000，标价 K 2,250,000
        // 回本汇率 = (2,250,000 − 55,000) / 3,600 = 609.7
        let rateItem = Item(
            serialNumber: "T-RATE", modelName: "MacBook Air M2",
            costCNY: 3600, exchangeRate: 420, shipping: 55_000, listPrice: 2_250_000
        )
        todoCtx.insert(rateItem)

        check("回本汇率 609.7", rateItem.breakEvenRate == Decimal(string: "609.7"),
              "\(String(describing: rateItem.breakEvenRate))")
        check("汇率 420 时不亏", rateItem.currencyLoss(at: 420) == 0,
              "\(rateItem.currencyLoss(at: 420))")
        check("汇率 650 时亏 ¥223.08", rateItem.currencyLoss(at: 650) == Decimal(string: "223.08"),
              "\(rateItem.currencyLoss(at: 650))")

        let riskTodos = TodoCenter.build(items: [rateItem], currentRate: 650)
        check("汇率亏损进待办", riskTodos.contains { $0.kind == .currencyRisk })
        check("汇率安全不进待办",
              !TodoCenter.build(items: [rateItem], currentRate: 420).contains { $0.kind == .currencyRisk })
        check("没设汇率不产生该待办",
              !TodoCenter.build(items: [rateItem], currentRate: 0).contains { $0.kind == .currencyRisk })

        // 没定价的机器谈不上结汇，不该有回本汇率
        let unpricedRate = Item(
            serialNumber: "T-RATE0", modelName: "MacBook Air M2",
            costCNY: 3600, exchangeRate: 420, shipping: 0, listPrice: 0
        )
        check("未标价没有回本汇率", unpricedRate.breakEvenRate == nil)

        // MARK: 配置解码兼容

        // 旧版配置没有 defaultExchangeRate 字段。合成 Codable 会在这里抛 keyNotFound，
        // 而 load() 用 try? 吞掉后返回空白配置——店名、电话、地址会静默消失。
        let legacyJSON = #"{"shopName":"曼德勒小店","phone":"0912345","address":"80 街","warrantyDays":14,"footnote":"谢谢惠顾"}"#
        let legacySettings = try JSONDecoder().decode(ShopSettings.self, from: Data(legacyJSON.utf8))
        check("配置-旧 JSON 保留店名", legacySettings.shopName == "曼德勒小店", legacySettings.shopName)
        check("配置-旧 JSON 保留电话", legacySettings.phone == "0912345", legacySettings.phone)
        check("配置-旧 JSON 保留保修天数", legacySettings.warrantyDays == 14, "\(legacySettings.warrantyDays)")
        check("配置-缺失的新字段回落默认值", legacySettings.defaultExchangeRate == 0,
              "\(legacySettings.defaultExchangeRate)")

        var rateSettings = legacySettings
        rateSettings.defaultExchangeRate = 420
        let rateRoundTrip = try JSONDecoder().decode(
            ShopSettings.self, from: try JSONEncoder().encode(rateSettings)
        )
        check("配置-往返保留默认汇率", rateRoundTrip.defaultExchangeRate == 420,
              "\(rateRoundTrip.defaultExchangeRate)")
                check("配置-往返保留店名", rateRoundTrip.shopName == "曼德勒小店", rateRoundTrip.shopName)

        // 二期新增的字段同样要能缺省回落：老用户的配置里没有这几项
        check("配置-旧 JSON 回落目标毛利 15%", legacySettings.targetMarginPercent == 15,
              "\(legacySettings.targetMarginPercent)")
        check("配置-旧 JSON 回落默认收款方式", legacySettings.paymentMethod == .cash,
              legacySettings.defaultPaymentMethod)
        check("配置-旧 JSON 回落自动备份开启", legacySettings.autoBackupEnabled)
        check("配置-旧 JSON 回落保留 14 份", legacySettings.backupRetention == 14,
              "\(legacySettings.backupRetention)")

        // MARK: 定价建议

        // 总进价 K 1,000,000，目标毛利 20% → 售价 = 1,000,000 / 0.8 = 1,250,000
        let fresh = PricingAdvice.make(landedCost: 1_000_000, targetMarginPercent: 20, ageInDays: 0)
        check("定价-按毛利率反推基准价", fresh?.basePrice == 1_250_000, "\(String(describing: fresh?.basePrice))")
        check("定价-新入库不折价", fresh?.markdownPercent == 0, "\(String(describing: fresh?.markdownPercent))")
        check("定价-新入库建议价 = 基准价", fresh?.suggestedPrice == 1_250_000,
              "\(String(describing: fresh?.suggestedPrice))")

        // 库龄 30 天落在边界上，不该开始折价
        let boundary = PricingAdvice.make(landedCost: 1_000_000, targetMarginPercent: 20, ageInDays: 30)
        check("定价-库龄 30 天不折价", boundary?.markdownPercent == 0,
              "\(String(describing: boundary?.markdownPercent))")

        // 库龄 44 天 = 满 2 周 → 降 2%
        let aged = PricingAdvice.make(landedCost: 1_000_000, targetMarginPercent: 20, ageInDays: 44)
        check("定价-库龄 44 天降 2%", aged?.markdownPercent == 2, "\(String(describing: aged?.markdownPercent))")
        check("定价-折价后按万取整", aged?.suggestedPrice == 1_230_000,
              "\(String(describing: aged?.suggestedPrice))")

        // 库龄再长也只封顶 15%
        let staleAdvice = PricingAdvice.make(landedCost: 1_000_000, targetMarginPercent: 20, ageInDays: 900)
        check("定价-折价封顶 15%", staleAdvice?.markdownPercent == 15, "\(String(describing: staleAdvice?.markdownPercent))")

        // 目标毛利 0% 时基准价 = 成本，库龄折价会把它压到成本以下 → 必须托底
        let zeroMargin = PricingAdvice.make(landedCost: 1_000_000, targetMarginPercent: 0, ageInDays: 200)
        check("定价-建议价不低于总进价", (zeroMargin?.suggestedPrice ?? 0) >= 1_000_000,
              "\(String(describing: zeroMargin?.suggestedPrice))")

        check("定价-无成本不给建议", PricingAdvice.make(landedCost: 0, targetMarginPercent: 20, ageInDays: 0) == nil)
        check("定价-毛利率 100% 不给建议",
              PricingAdvice.make(landedCost: 1_000_000, targetMarginPercent: 100, ageInDays: 0) == nil)

        // 已售机器不该出现建议价
        check("定价-已售机器不给建议",
              PricingAdvice.make(for: item, targetMarginPercent: 20) == nil)

        // 保留份数夹在 1…200：填 0 时不能把刚写好的备份一起删掉
        check("备份-保留份数下限保护", min(max(0, 1), 200) == 1)
        check("备份-保留份数上限保护", min(max(5000, 1), 200) == 200)

        print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
