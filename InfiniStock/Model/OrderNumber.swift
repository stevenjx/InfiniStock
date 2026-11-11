import Foundation
import SwiftData

/// 单号：`SO-2026-0001`，按自然年顺序递增。
/// 序号存在订单上而不是计数器里，恢复备份后号码能跟着数据一起回来，不会重号。
enum OrderNumberFactory {

    static func make(year: Int, sequence: Int) -> String {
        "SO-\(year)-" + String(format: "%04d", sequence)
    }

    /// 兼容旧格式 `SO-20260811-2120xx-xxx`，解析不出返回 nil
    static func parse(_ number: String) -> (year: Int, sequence: Int)? {
        let parts = number.split(separator: "-")
        guard parts.count == 3, parts[0] == "SO",
              let year = Int(parts[1]), let sequence = Int(parts[2]) else {
            return nil
        }
        return (year, sequence)
    }

    /// 下一年度的下一个序号
    static func nextSequence(for year: Int, in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Order>(predicate: #Predicate { $0.sequenceYear == year })
        let existing = try context.fetch(descriptor)
        let maximum = existing.map(\.sequenceNumber).max() ?? 0
        guard maximum < 9999 else { throw OrderError.sequenceExhausted(year) }
        return maximum + 1
    }
}
