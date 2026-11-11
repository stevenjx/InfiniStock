import Foundation
import SwiftData

/// 序列号查询的唯一入口：界面、Spotlight、App Intent 都走这里，避免三处各写一遍谓词。
@MainActor
enum ItemLookup {

    static func find(serial: String, in context: ModelContext) -> Item? {
        let key = InventoryService.normalize(serial)
        guard !key.isEmpty else { return nil }
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.serialNumber == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func recent(limit: Int = 10, in context: ModelContext) -> [Item] {
        var descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\.inboundAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}
