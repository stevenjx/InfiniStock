import AppIntents
import Foundation
import SwiftData

/// 让机器成为系统级可查询实体，Spotlight 与「聚焦」都能命中序列号。
struct ItemEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "机器")
    static let defaultQuery = ItemEntityQuery()

    let id: String
    let modelName: String
    let serialNumber: String
    let status: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(modelName)",
            subtitle: "\(serialNumber) · \(status)"
        )
    }

    init(item: Item) {
        id = item.serialNumber
        modelName = item.modelName
        serialNumber = item.serialNumber
        status = String(localized: item.status.label)
    }
}

struct ItemEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ItemEntity] {
        let context = AppStore.shared.container.mainContext
        return identifiers.compactMap { ItemLookup.find(serial: $0, in: context) }.map(ItemEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [ItemEntity] {
        let context = AppStore.shared.container.mainContext
        return ItemLookup.recent(in: context).map(ItemEntity.init)
    }

    @MainActor
    func defaultResult() async -> ItemEntity? {
        let context = AppStore.shared.container.mainContext
        return ItemLookup.recent(limit: 1, in: context).first.map(ItemEntity.init)
    }
}

/// 不打开 App 也能查机况。
struct FindItemIntent: AppIntent {
    static let title: LocalizedStringResource = "查询机器"
    static let description = IntentDescription("按序列号查询机器型号、状态与总进价")
    static let openAppWhenRun = false

    @Parameter(title: "Serial number")
    var serial: String

    static var parameterSummary: some ParameterSummary {
        Summary("查询 \(\.$serial)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppStore.shared.container.mainContext
        guard let item = ItemLookup.find(serial: serial, in: context) else {
            return .result(dialog: "没有找到序列号 \(InventoryService.normalize(serial))")
        }
        return .result(
            dialog: "\(item.modelName) · \(item.status.label) · 总进价 \(item.landedCost.mmk)"
        )
    }
}

struct InfiniStockShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindItemIntent(),
            phrases: ["用 \(.applicationName) 查机器"],
            shortTitle: "查询机器",
            systemImageName: "magnifyingglass"
        )
    }
}
