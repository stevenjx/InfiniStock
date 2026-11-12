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

        // 只卖 MacBook：进价人民币、汇率 420、运费与售价缅币
        let rate: Decimal = 420
        let samples: [(serial: String, model: String, chip: String, memory: String, storage: String, cost: Decimal, shipping: Decimal, list: Decimal, days: Int, soldHoursAgo: Int?)] = [
            ("F2LX9K3QABCD", "MacBook Air M2 13\"", "M2", "8GB", "256GB", 3_600, 55_000, 2_250_000, 5, nil),
            ("F2LX9K3QABCE", "MacBook Air M1 13\"", "M1", "8GB", "256GB", 2_900, 45_000, 1_850_000, 12, nil),
            ("F2LX9K3QABCF", "MacBook Pro 14\" M3 Pro", "M3 Pro", "18GB", "512GB", 8_800, 80_000, 4_900_000, 75, nil),
            ("F2LX9K3QABCG", "MacBook Pro 13\" M2", "M2", "8GB", "256GB", 5_200, 50_000, 3_150_000, 92, nil),
            ("F2LX9K3QABCH", "MacBook Air M2 15\"", "M2", "8GB", "256GB", 4_200, 60_000, 2_650_000, 30, 1),
            ("F2LX9K3QABCJ", "MacBook Air M3 13\"", "M3", "8GB", "256GB", 4_800, 55_000, 2_900_000, 2, 2),
        ]

        // 电池数据：健康度、循环次数（第 4 台故意偏低，用来看黄色提示）
        let battery: [(health: Int, cycles: Int)] = [
            (92, 210), (88, 340), (85, 520), (78, 890), (90, 260), (96, 120),
        ]

        for (index, sample) in samples.enumerated() {
            let item = Item(
                serialNumber: sample.serial,
                modelName: sample.model,
                chip: sample.chip,
                memory: sample.memory,
                storage: sample.storage,
                color: "深空灰",
                condition: .p95,
                costCNY: sample.cost,
                exchangeRate: rate,
                shipping: sample.shipping,
                listPrice: sample.list
            )
            item.batteryHealth = battery[index].health
            item.batteryCycles = battery[index].cycles
            item.inboundAt = Calendar.current.date(byAdding: .day, value: -sample.days, to: .now) ?? .now
            context.insert(item)

            if let hoursAgo = sample.soldHoursAgo {
                item.status = .sold
                item.soldAt = Date().addingTimeInterval(-Double(hoursAgo) * 3600)
                item.soldPrice = sample.list
            }
        }
        try? context.save()

        // 再造两张单据，便于验收单据列表与退货状态
        let inStock = ((try? context.fetch(FetchDescriptor<Item>())) ?? []).filter { $0.status == .inStock }
        if inStock.count >= 3 {
            let orderA = try? InventoryService.sell(
                lines: [
                    .init(item: inStock[0], price: inStock[0].listPrice),
                    .init(item: inStock[1], price: inStock[1].listPrice),
                ],
                customerName: "陈先生", customerContact: "13600001111",
                discount: 30_000, rounding: 0, paymentMethod: .transfer,
                in: context
            )
            if let orderA, inStock.count >= 4 {
                let orderB = try? InventoryService.sell(
                    lines: [.init(item: inStock[2], price: inStock[2].listPrice)],
                    customerName: "林女士", customerContact: "13500002222",
                    discount: 0, rounding: 0, paymentMethod: .cash,
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
