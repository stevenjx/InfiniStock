import Foundation
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

        let schema = Schema([Item.self, Order.self])
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

        print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
