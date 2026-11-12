#if DEBUG
import Foundation
import SwiftData

/// 仅 Debug 构建可用：把 `seed.flag` 放进 App 的 Application Support 目录后启动，
/// 会插入一批样例数据并删除该文件。用于验收界面，不参与 Release 构建。
///
/// 沙盒路径：
///   ~/Library/Containers/com.infinistock.app/Data/Library/Application Support/seed.flag
@MainActor
enum DebugSeed {
    static func seedIfRequested(_ context: ModelContext) {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let flag = support.appendingPathComponent("seed.flag")
        guard FileManager.default.fileExists(atPath: flag.path) else { return }
        try? FileManager.default.removeItem(at: flag)

        let existing = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        guard existing == 0 else { return }

        let samples: [(serial: String, model: String, storage: String, cost: Decimal, list: Decimal, days: Int, soldHoursAgo: Int?)] = [
            ("F2LX9K3QABCD", "iPhone 17 Pro Max", "256GB", 980, 8999, 5, nil),
            ("F2LX9K3QABCE", "iPhone 17 Pro", "128GB", 820, 7299, 12, nil),
            ("F2LX9K3QABCF", "iPhone 16 Pro", "256GB", 700, 6199, 75, nil),
            ("F2LX9K3QABCG", "iPhone 16", "128GB", 520, 4699, 92, nil),
            ("F2LX9K3QABCH", "iPhone 15 Pro Max", "512GB", 640, 5899, 30, 1),
            ("F2LX9K3QABCJ", "iPhone 15", "128GB", 380, 3399, 2, 2),
        ]

        for sample in samples {
            let item = Item(
                serialNumber: sample.serial,
                modelName: sample.model,
                chip: "A19",
                memory: "8GB",
                storage: sample.storage,
                color: "深空黑",
                condition: .p95,
                costAmount: sample.cost,
                currency: .usd,
                exchangeRate: 7.1,
                shippingCNY: 120,
                listPriceCNY: sample.list
            )
            item.inboundAt = Calendar.current.date(byAdding: .day, value: -sample.days, to: .now) ?? .now
            context.insert(item)

            if let hoursAgo = sample.soldHoursAgo {
                item.status = .sold
                item.soldAt = Date().addingTimeInterval(-Double(hoursAgo) * 3600)
                item.soldPriceCNY = sample.list
            }
        }
        try? context.save()

        // 再造两张单据，便于验收单据列表与退货状态
        let inStock = ((try? context.fetch(FetchDescriptor<Item>())) ?? []).filter { $0.status == .inStock }
        if inStock.count >= 3 {
            let orderA = try? InventoryService.sell(
                lines: [
                    .init(item: inStock[0], price: inStock[0].listPriceCNY),
                    .init(item: inStock[1], price: inStock[1].listPriceCNY),
                ],
                customerName: "陈先生", customerContact: "13600001111",
                discountCNY: 200, roundingCNY: 88, paymentMethod: .transfer,
                in: context
            )
            if let orderA, inStock.count >= 4 {
                let orderB = try? InventoryService.sell(
                    lines: [.init(item: inStock[2], price: inStock[2].listPriceCNY)],
                    customerName: "林女士", customerContact: "13500002222",
                    discountCNY: 0, roundingCNY: 0, paymentMethod: .cash,
                    in: context
                )
                if orderB != nil {
                    _ = try? OrderService.returnItems([inStock[2]], from: orderB!, in: context)
                }
            }
            _ = orderA
        }
    }
}
#endif
