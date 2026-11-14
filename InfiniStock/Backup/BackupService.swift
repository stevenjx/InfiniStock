import Foundation
import SwiftData

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case legacyVersion(Int)
    case corruptFile(String)
    case emptySnapshot

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "备份格式版本 \(version) 高于当前 App，请先升级"
        case .legacyVersion(let version):
            "这份备份是旧格式（v\(version)），金额口径与当前版本不同，无法直接恢复。请用当前版本重新导出备份。"
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
                costCNY: item.costCNY.plainString,
                exchangeRate: item.exchangeRate.plainString,
                shipping: item.shipping.plainString,
                landedCost: item.landedCost.plainString,
                listPrice: item.listPrice.plainString,
                soldPrice: item.soldPrice.plainString,
                batteryHealth: item.batteryHealth,
                batteryCycles: item.batteryCycles,
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
                subtotal: order.subtotal.plainString,
                total: order.total.plainString,
                profit: order.profit.plainString,
                discount: order.discount.plainString,
                rounding: order.rounding.plainString,
                paymentMethod: order.paymentMethodRaw,
                createdAt: order.createdAt,
                originDeviceID: order.originDeviceID,
                voidedAt: order.voidedAt,
                itemSerials: order.itemList.map(\.serialNumber).sorted(),
                sequenceYear: order.sequenceYear,
                sequenceNumber: order.sequenceNumber,
                returnedAmount: order.returnedAmount.plainString,
                returnedCount: order.returnedCount,
                paidAmount: order.paidAmount?.plainString,
                paidAt: order.paidAt
            )
        }

        let batchDTOs = batches.map { batch in
            BackupSnapshot.BatchDTO(
                name: batch.name,
                supplier: batch.supplier,
                exchangeRate: batch.exchangeRate.plainString,
                totalShipping: batch.totalShipping.plainString,
                allocation: batch.allocationRaw,
                createdAt: batch.createdAt
            )
        }

        // 改价记录挂在机器上，按序列号导出/恢复，换机后对账链不断
        let priceChanges = items.flatMap { item in
            (item.priceChanges ?? []).map { change in
                BackupSnapshot.PriceChangeDTO(
                    itemSerial: item.serialNumber,
                    changedAt: change.changedAt,
                    oldPrice: change.oldPrice.plainString,
                    newPrice: change.newPrice.plainString,
                    landedCost: change.landedCostAtChange.plainString,
                    source: change.sourceRaw
                )
            }
        }

        return BackupSnapshot(
            formatVersion: BackupSnapshot.currentFormatVersion,
            exportedAt: now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            items: itemDTOs,
            orders: orderDTOs,
            batches: batchDTOs,
            shopSettings: ShopSettings.load(),
            priceChanges: priceChanges
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
            guard snapshot.formatVersion >= BackupSnapshot.minimumFormatVersion else {
                throw BackupError.legacyVersion(snapshot.formatVersion)
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
            "电池健康", "循环次数",
            "进价(人民币)", "汇率", "运费(缅币)", "总进价(缅币)", "标价(缅币)",
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
                item.batteryHealth > 0 ? String(item.batteryHealth) : "",
                item.batteryCycles > 0 ? String(item.batteryCycles) : "",
                item.costCNY.plainString,
                item.exchangeRate.plainString,
                item.shipping.plainString,
                item.landedCost.plainString,
                item.listPrice.plainString,
                item.status == .sold ? item.soldPrice.plainString : "",
                item.status == .sold ? item.grossProfit.plainString : "",
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
            batch.exchangeRate = dto.exchangeRate.decimalValue
            batch.totalShipping = dto.totalShipping.decimalValue
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
                costCNY: dto.costCNY.decimalValue,
                exchangeRate: dto.exchangeRate.decimalValue,
                shipping: dto.shipping.decimalValue,
                listPrice: dto.listPrice.decimalValue
            )
            item.statusRaw = dto.status
            item.batteryHealth = dto.batteryHealth ?? 0
            item.batteryCycles = dto.batteryCycles ?? 0
            item.soldPrice = dto.soldPrice.decimalValue
            item.landedCost = dto.landedCost.decimalValue
            item.inboundAt = dto.inboundAt
            item.soldAt = dto.soldAt
            item.photoData = dto.photoBase64.flatMap { Data(base64Encoded: $0) }
            item.batch = dto.batchName.flatMap { batchByName[$0] }
            context.insert(item)
            itemBySerial[dto.serialNumber] = item
        }

        // 旧备份没有这一段，nil 直接跳过——恢复后改价历史从今天开始记，金额不受影响
        for dto in snapshot.priceChanges ?? [] {
            guard let item = itemBySerial[dto.itemSerial] else { continue }
            let change = PriceChange(
                oldPrice: dto.oldPrice.decimalValue,
                newPrice: dto.newPrice.decimalValue,
                landedCostAtChange: dto.landedCost.decimalValue,
                source: PriceChangeSource(rawValue: dto.source) ?? .edit,
                changedAt: dto.changedAt
            )
            change.item = item
            context.insert(change)
        }

        if let settings = snapshot.shopSettings {
            settings.save()
        }

        for dto in snapshot.orders {
            let order = Order()
            order.number = dto.number
            order.customerName = dto.customerName
            order.customerContact = dto.customerContact
            order.subtotal = dto.subtotal.decimalValue
            order.discount = dto.discount.decimalValue
            order.rounding = dto.rounding.decimalValue
            order.total = dto.total.decimalValue
            order.profit = dto.profit.decimalValue
            order.paymentMethodRaw = dto.paymentMethod
            order.createdAt = dto.createdAt
            order.originDeviceID = dto.originDeviceID
            order.voidedAt = dto.voidedAt
            order.returnedAmount = dto.returnedAmount.decimalValue
            order.returnedCount = dto.returnedCount
            // 老备份没有这一项，保持 nil = 已全额收讫
            order.paidAmount = dto.paidAmount.map { $0.decimalValue }
            order.paidAt = dto.paidAt
            order.sequenceYear = dto.sequenceYear
            order.sequenceNumber = dto.sequenceNumber
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

    /// 超过这么多天没写备份，就算过期
    nonisolated static let staleDays = 7

    /// 待办要的提醒：没配目录是「从未备份」，配了但太久没写是「N 天没备份」。
    /// nil 表示不必提醒。类型定义在 TodoCenter，Backup 依赖 Store 而不是反过来。
    static func reminder(now: Date = .now) -> TodoCenter.BackupReminder? {
        guard ShopSettings.load().autoBackupEnabled else { return nil }
        guard let folder = backupFolder() else { return .notConfigured }
        // 目录在，但可能被移动或删除；书签能解出来不代表写得进去，这里只做天数判断，
        // 真正的失败会在写的时候暴露。
        _ = folder
        guard let last = lastBackupAt else { return .notConfigured }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: last), to: Calendar.current.startOfDay(for: now)
        ).day ?? 0
        return days > staleDays ? .stale(days: days) : nil
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

        // 保留份数由设置决定；夹在 1…200 之间，防止手误填 0 把刚写的备份删掉
        let keep = min(max(ShopSettings.load().backupRetention, 1), 200)
        prune(in: folder, keeping: keep)
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

    /// 每天首次启动自动备份一次；未选择目录或用户在设置里关掉时静默跳过。
    @discardableResult
    static func autoBackupIfNeeded(from context: ModelContext, now: Date = .now) -> URL? {
        guard ShopSettings.load().autoBackupEnabled else { return nil }
        guard let folder = backupFolder() else { return nil }
        if let last = lastBackupAt, Calendar.current.isDate(last, inSameDayAs: now) { return nil }
        return try? writeBackup(from: context, into: folder, now: now)
    }
}