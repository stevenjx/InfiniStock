import SwiftUI
import SwiftData
import AppKit

/// 渲染真实视图（不是仿制品）到图片，用于双模式验收。
/// 用内存数据库喂入确定的样例数据，保证每次出图可复现。
@main
struct ViewPreview {
    @MainActor
    static func main() {
        guard let container = try? makeContainer() else {
            print("container failed")
            return
        }
        let context = container.mainContext
        let items = (try? context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.serialNumber)]))) ?? []
        guard let first = items.first else {
            print("no items")
            return
        }

        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/views.png"

        let detail = ItemDetailContent(item: first).padding(16)
            .modelContainer(container)
            .frame(width: 520, height: 980)

        let summary = SelectionSummaryView(items: items)
            .modelContainer(container)
            .frame(width: 340, height: 620, alignment: .top)

        let stats = InventoryStatistics(items: items, orders: (try? context.fetch(FetchDescriptor<Order>())) ?? [])
        let dash = DashboardContent(stats: stats, cloudSyncEnabled: false, backupConfigured: false)
            .frame(width: 620)

        let content = HStack(alignment: .top, spacing: 0) {
            panel(.light, title: "详情 · 浅色") { detail }
            panel(.dark, title: "详情 · 深色") { detail }
            VStack(spacing: 0) {
                panel(.light, title: "多选汇总") { summary }
                panel(.dark, title: "仪表盘") { dash }
            }
        }

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("render failed")
            return
        }
        try? png.write(to: URL(fileURLWithPath: out))
        print("written \(out) \(png.count)")
    }

    @MainActor
    static func panel<C: View>(_ scheme: ColorScheme, title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            content()
                .environment(\.colorScheme, scheme)
                .background(scheme == .dark ? Color(white: 0.09) : Color(white: 0.94))
        }
    }

    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, Order.self, Batch.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let batch = Batch()
        batch.name = "2026-11 深圳批"
        batch.exchangeRate = 420
        batch.totalShipping = 240_000
        batch.allocation = .byValue
        context.insert(batch)

        var draft = IntakeDraft()
        draft.serialNumber = "F2LX9K3QABCD"
        draft.modelName = "MacBook Air M2 13\""
        draft.chip = "M2"
        draft.memory = "8GB"
        draft.storage = "256GB"
        draft.color = "深空灰"
        draft.condition = .p95
        draft.batteryHealth = "92"
        draft.batteryCycles = "210"
        draft.costCNY = "3600"
        draft.exchangeRate = "420"
        draft.shipping = "55000"
        draft.listPrice = "2250000"
        _ = try? InventoryService.intake(draft, batch: batch, in: context)

        var second = draft
        second.serialNumber = "F2LX9K3QABCE"
        second.modelName = "MacBook Pro 14\" M3 Pro"
        second.storage = "512GB"
        second.listPrice = "4900000"
        let old = try? InventoryService.intake(second, in: context)
        old?.inboundAt = Calendar.current.date(byAdding: .day, value: -92, to: .now) ?? .now

        try? context.save()
        return container
    }
}