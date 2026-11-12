import Foundation
import SwiftData

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case corruptFile(String)
    case emptySnapshot

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "备份格式版本 \(version) 高于当前 App，请先升级"
        case .corruptFile(let detail):
            "备份文件无法解析：\(detail)"
        case .emptySnapshot:
            "备份文件不含任何机器记录"
        }
    }
}

/// 全量导出、恢复、每日自动备份。
///
/// 沙盒约束：App 不能直接写 ~/Documents。备份目录必须由用户通过文件面板选定一次，
/// 之后用安全作用域书签记住，才能在无人值守时写入。
@MainActor
enum BackupService {

    // MARK: - 导出

    static func makeSnapshot(from context: ModelContext, now: Date = .now) throws -> BackupSnapshot {
        let items = try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.serialNumber)]))
        let orders = try context.fetch(FetchDescriptor<Order>(sortBy: [SortDescriptor(\.createdAt)]))
        let batches = try context.fetch(FetchDescriptor<Batch>(sortBy: [SortDescriptor(\.createdAt)]))

        let itemDTOs = items.map { item in
            BackupSnapshot.ItemDTO(
                serialNumber: item.serialNumber,
                modelName: item.modelName,
                chip: item.chip,
                memory: item.memory,
                storage: item.storage,
                color: item.color,
                condition: item.conditionRaw,
                status: item.statusRaw,
                costAmount: item.costAmount.plainString,
                costCurrency: item.costCurrencyRaw,
                exchangeRate: item.exchangeRate.plainString,
                shippingCNY: item.shippingCNY.plainString,
                landedCostCNY: item.landedCostCNY.plainString,
                listPriceCNY: item.listPriceCNY.plainString,
                soldPriceCNY: item.soldPriceCNY.plainString,
                inboundAt: item.inboundAt,
                soldAt: item.soldAt,
                orderNumber: item.order?.number,
                batchName: item.batch?.name,
                photoBase64: item.photoData?.base64EncodedString()
            )
        }

        let orderDTOs = orders.map { order in
            BackupSnapshot.OrderDTO(
                number: order.number,
                customerName: order.customerName,
                customerContact: order.customerContact,
                subtotalCNY: order.subtotalCNY.plainString,
                totalCNY: order.totalCNY.plainString,
                profitCNY: order.profitCNY.plainString,
                createdAt: order.createdAt,
                originDeviceID: order.originDeviceID,
                voidedAt: order.voidedAt,
                itemSerials: order.itemList.map(\.serialNumber).sorted(),
                discountCNY: order.discountCNY.plainString,
                roundingCNY: order.roundingCNY.plainString,
                paymentMethod: order.paymentMethodRaw,
                sequenceYear: order.sequenceYear,
                sequenceNumber: order.sequenceNumber,
                returnedAmountCNY: order.returnedAmountCNY.plainString,
                returnedCount: order.returnedCount
            )
        }

        let batchDTOs = batches.map { batch in
            BackupSnapshot.BatchDTO(
                name: batch.name,
                supplier: batch.supplier,
                currency: batch.currencyRaw,
                exchangeRate: batch.exchangeRate.plainString,
                totalShippingCNY: batch.totalShippingCNY.plainString,
                allocation: batch.allocationRaw,
                createdAt: batch.createdAt
            )
        }

        return BackupSnapshot(
            formatVersion: BackupSnapshot.currentFormatVersion,
            exportedAt: now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            items: itemDTOs,
            orders: orderDTOs,
            batches: batchDTOs,
            shopSettings: ShopSettings.load()
        )
    }

    static func jsonData(_ snapshot: BackupSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> BackupSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let snapshot = try decoder.decode(BackupSnapshot.self, from: data)
            guard snapshot.formatVersion <= BackupSnapshot.currentFormatVersion else {
                throw BackupError.unsupportedVersion(snapshot.formatVersion)
            }
            guard !snapshot.items.isEmpty else { throw BackupError.emptySnapshot }
            return snapshot
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.corruptFile(error.localizedDescription)
        }
    }

    /// 给 Excel 看的表格。加 BOM，否则中文在 Excel 里会乱码。
    static func csvData(from context: ModelContext) throws -> Data {
        let items = try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.serialNumber)]))

        let header = [
            "序列号", "型号", "芯片", "内存", "存储", "颜色", "成色", "状态",
            "进价", "币种", "汇率", "运费", "落地成本", "标价",
            "成交价", "毛利", "入库日期", "售出日期", "单号", "客户", "批次",
        ].joined(separator: ",")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let rows = items.map { item -> String in
            let cells: [String] = [
                item.serialNumber,
                item.modelName,
                item.chip,
                item.memory,
                item.storage,
                item.color,
                item.condition.rawValue,
                item.status.label,
                item.costAmount.plainString,
                item.currency.rawValue,
                item.exchangeRate.plainString,
                item.shippingCNY.plainString,
                item.landedCostCNY.plainString,
                item.listPriceCNY.plainString,
                item.status == .sold ? item.soldPriceCNY.plainString : "",
                item.status == .sold ? item.grossProfitCNY.plainString : "",
                formatter.string(from: item.inboundAt),
                item.soldAt.map(formatter.string) ?? "",
                item.order?.number ?? "",
                item.order?.customerName ?? "",
                item.batch?.name ?? "",
            ]
            return cells.map(escapeCSV).joined(separator: ",")
        }

        let text = "\u{FEFF}" + ([header] + rows).joined(separator: "\r\n") + "\r\n"
        return Data(text.utf8)
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - 恢复

    /// 清空并回灌。属于破坏性操作，调用方必须先做身份验证。
    static func restore(_ snapshot: BackupSnapshot, into context: ModelContext) throws {
        try wipe(context)

        var batchByName: [String: Batch] = [:]
        for dto in snapshot.batches {
            let batch = Batch()
            batch.name = dto.name
            batch.supplier = dto.supplier
            batch.currencyRaw = dto.currency
            batch.exchangeRate = dto.exchangeRate.decimalValue
            batch.totalShippingCNY = dto.totalShippingCNY.decimalValue
            batch.allocationRaw = dto.allocation
            batch.createdAt = dto.createdAt
            context.insert(batch)
            batchByName[dto.name] = batch
        }

        var itemBySerial: [String: Item] = [:]
        for dto in snapshot.items {
            let item = Item(
                serialNumber: dto.serialNumber,
                modelName: dto.modelName,
                chip: dto.chip,
                memory: dto.memory,
                storage: dto.storage,
                color: dto.color,
                condition: ItemCondition(rawValue: dto.condition) ?? .p95,
                costAmount: dto.costAmount.decimalValue,
                currency: CostCurrency(rawValue: dto.costCurrency) ?? .cny,
                exchangeRate: dto.exchangeRate.decimalValue,
                shippingCNY: dto.shippingCNY.decimalValue,
                listPriceCNY: dto.listPriceCNY.decimalValue
            )
            item.statusRaw = dto.status
            item.soldPriceCNY = dto.soldPriceCNY.decimalValue
            item.landedCostCNY = dto.landedCostCNY.decimalValue
            item.inboundAt = dto.inboundAt
            item.soldAt = dto.soldAt
            item.photoData = dto.photoBase64.flatMap { Data(base64Encoded: $0) }
            item.batch = dto.batchName.flatMap { batchByName[$0] }
            context.insert(item)
            itemBySerial[dto.serialNumber] = item
        }

        if let settings = snapshot.shopSettings {
            settings.save()
        }

        for dto in snapshot.orders {
            let order = Order()
            order.number = dto.number
            order.customerName = dto.customerName
            order.customerContact = dto.customerContact
            order.subtotalCNY = dto.subtotalCNY.decimalValue
            order.discountCNY = (dto.discountCNY ?? "0").decimalValue
            order.roundingCNY = (dto.roundingCNY ?? "0").decimalValue
            order.totalCNY = dto.totalCNY.decimalValue
            order.profitCNY = dto.profitCNY.decimalValue
            order.paymentMethodRaw = dto.paymentMethod ?? PaymentMethod.cash.rawValue
            order.createdAt = dto.createdAt
            order.originDeviceID = dto.originDeviceID
            order.voidedAt = dto.voidedAt
            order.returnedAmountCNY = (dto.returnedAmountCNY ?? "0").decimalValue
            order.returnedCount = dto.returnedCount ?? 0
            order.sequenceYear = dto.sequenceYear ?? Calendar.current.component(.year, from: dto.createdAt)
            order.sequenceNumber = dto.sequenceNumber ?? (OrderNumberFactory.parse(dto.number)?.sequence ?? 0)
            // 旧备份按解析出的序号补齐单号
            if dto.sequenceNumber == nil, let parsed = OrderNumberFactory.parse(dto.number) {
                order.sequenceYear = parsed.year
                order.sequenceNumber = parsed.sequence
            }
            context.insert(order)

            for serial in dto.itemSerials {
                itemBySerial[serial]?.order = order
            }
        }

        try context.save()
    }

    static func wipe(_ context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<Item>()) { context.delete(item) }
        for order in try context.fetch(FetchDescriptor<Order>()) { context.delete(order) }
        for batch in try context.fetch(FetchDescriptor<Batch>()) { context.delete(batch) }
        try context.save()
    }

    // MARK: - 备份目录（安全作用域书签）

    private static let bookmarkKey = "infinistock.backupFolderBookmark"
    private static let lastBackupKey = "infinistock.lastBackupAt"

    static func rememberFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func backupFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale { rememberFolder(url) }
        return url
    }

    static var lastBackupAt: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    // MARK: - 写备份

    @discardableResult
    static func writeBackup(from context: ModelContext, into folder: URL, now: Date = .now) throws -> URL {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let snapshot = try makeSnapshot(from: context, now: now)
        let data = try jsonData(snapshot)
        let url = folder.appendingPathComponent(backupFileName(at: now))
        try data.write(to: url, options: .atomic)

        UserDefaults.standard.set(now, forKey: lastBackupKey)

        prune(in: folder)
        return url
    }

    static func backupFileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "infinistock-\(formatter.string(from: date)).json"
    }

    nonisolated static let retentionCount = 14

    /// 只保留最新的 N 份。按文件名倒序即可，文件名内含零填充时间戳。
    static func prune(in folder: URL, keeping limit: Int = retentionCount) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let backups = names
            .filter { $0.hasPrefix("infinistock-") && $0.hasSuffix(".json") }
            .sorted(by: >)
        guard backups.count > limit else { return }
        for stale in backups.dropFirst(limit) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(stale))
        }
    }

    /// 每天首次启动自动备份一次；未选择目录时静默跳过（界面会提示未启用）。
    @discardableResult
    static func autoBackupIfNeeded(from context: ModelContext, now: Date = .now) -> URL? {
        guard let folder = backupFolder() else { return nil }
        if let last = lastBackupAt, Calendar.current.isDate(last, inSameDayAs: now) { return nil }
        return try? writeBackup(from: context, into: folder, now: now)
    }
}