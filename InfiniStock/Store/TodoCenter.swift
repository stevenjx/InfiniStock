import Foundation
import SwiftData

/// 待办类型。声明顺序即列表里的排序优先级：先堵漏（成本算错、卖一台亏一台），
/// 再议价（电池），最后才是慢销。
enum TodoKind: String, CaseIterable, Identifiable {
    case pendingAllocation
    case unpriced
    case negativeMargin
    case weakBattery
    case aged

    var id: String { rawValue }

    /// 列表徽章用的短名，长名字塞不进一列
    var title: String {
        switch self {
        case .pendingAllocation: "待分摊"
        case .unpriced: "未标价"
        case .negativeMargin: "低于成本"
        case .weakBattery: "电池偏弱"
        case .aged: "库龄超期"
        }
    }

    /// 这条待办到底要人做什么
    var actionHint: String {
        switch self {
        case .pendingAllocation: "分摊运费"
        case .unpriced: "定标价"
        case .negativeMargin: "调价"
        case .weakBattery: "议价或备注"
        case .aged: "促销或调价"
        }
    }
}

/// 一条待办。item / batch 二者必有其一，界面据此决定跳到哪里。
struct TodoEntry: Identifiable {
    /// 选中标识：同一台机器可以有多条待办，所以必须带上类型
    struct Key: Hashable {
        let kind: TodoKind
        let target: PersistentIdentifier
    }

    let id: Key
    let kind: TodoKind
    /// 机器型号或批次名
    let title: String
    /// 序列号或供应商
    let subtitle: String
    /// 为什么要处理，一句话说清
    let reason: String
    /// 涉及金额：占用成本、亏损额或未分摊运费
    let amount: Decimal
    let item: Item?
    let batch: Batch?
}

/// 待办清单的生成逻辑。纯函数，不碰界面状态，可被 verify.sh 直接断言。
///
/// 只收在库机器：已售的机器再怎么提醒也没法动手，那是售后的事。
enum TodoCenter {
    static func build(items: [Item], batches: [Batch] = []) -> [TodoEntry] {
        var entries: [TodoEntry] = []
        let inStock = items.filter { $0.status == .inStock }

        for item in inStock {
            let target = item.persistentModelID

            func add(_ kind: TodoKind, _ reason: String, _ amount: Decimal) {
                entries.append(TodoEntry(
                    id: TodoEntry.Key(kind: kind, target: target),
                    kind: kind,
                    title: item.modelName,
                    subtitle: item.serialNumber,
                    reason: reason,
                    amount: amount,
                    item: item,
                    batch: nil
                ))
            }

            // 未标价与亏本互斥：没定价就谈不上亏
            if item.listPrice <= 0 {
                add(.unpriced, "还没有标价，无法出库", item.landedCost)
            } else if item.listPrice < item.landedCost {
                add(.negativeMargin,
                    "标价比总进价低 \(Money.kyat(item.landedCost - item.listPrice))",
                    item.landedCost - item.listPrice)
            }

            if item.isBatteryWeak {
                add(.weakBattery, batteryReason(item), item.landedCost)
            }

            if item.ageInDays >= Item.overdueDays {
                add(.aged, "入库 \(item.ageInDays) 天仍未售出", item.landedCost)
            }
        }

        for batch in batches where batch.stage == .pending {
            let unallocated = batch.totalShipping - batch.allocatedShipping
            entries.append(TodoEntry(
                id: TodoEntry.Key(kind: .pendingAllocation, target: batch.persistentModelID),
                kind: .pendingAllocation,
                title: batch.name.isEmpty ? "未命名批次" : batch.name,
                subtitle: batch.supplier.isEmpty ? "未填供应商" : batch.supplier,
                reason: "\(Money.kyat(unallocated)) 运费还没摊到机器上",
                amount: unallocated,
                item: nil,
                batch: batch
            ))
        }

        let rank = Dictionary(
            uniqueKeysWithValues: TodoKind.allCases.enumerated().map { ($1, $0) }
        )
        return entries.sorted { lhs, rhs in
            let l = rank[lhs.kind] ?? 0
            let r = rank[rhs.kind] ?? 0
            if l != r { return l < r }
            return lhs.amount > rhs.amount
        }
    }

    /// 电池这条要同时说清健康度和循环次数，只说一半会让人判断错
    static func batteryReason(_ item: Item) -> String {
        var parts: [String] = []
        if item.batteryHealth > 0 {
            parts.append("健康 \(item.batteryHealth)%")
        }
        if item.batteryCycles > 0 {
            parts.append("\(item.batteryCycles) 次循环")
        }
        let summary = parts.isEmpty ? "电池数据缺失" : parts.joined(separator: " · ")
        if item.batteryHealth > 0 && item.batteryHealth < Item.weakHealth {
            return "\(summary)，低于 \(Item.weakHealth)%"
        }
        return "\(summary)，循环偏高"
    }

    /// 涉及金额合计。同一台机器可能同时有多条待办，按机器去重，
    /// 否则"占用资金"会被同一台机器重复计入两次。
    static func involvedCost(_ entries: [TodoEntry]) -> Decimal {
        var seen = Set<PersistentIdentifier>()
        var total = Decimal(0)
        for entry in entries {
            guard let item = entry.item, !seen.contains(item.persistentModelID) else { continue }
            seen.insert(item.persistentModelID)
            total += item.landedCost
        }
        return total
    }

    static func involvedCount(_ entries: [TodoEntry]) -> Int {
        Set(entries.compactMap { $0.item?.persistentModelID }).count
    }

    static func count(_ entries: [TodoEntry], of kind: TodoKind) -> Int {
        entries.reduce(0) { $0 + ($1.kind == kind ? 1 : 0) }
    }
}
