import Foundation
import SwiftData

/// 标价变动留痕。
///
/// 为什么单独建模型而不是塞进 Item：改价是事件，不是状态。
/// 一台机器可能改过五次价，只有最后一次是「当前标价」，但月末对账要的是全部五次。
///
/// CloudKit 镜像约束同 Item：字段都有默认值、不声明唯一约束。
@Model
final class PriceChange {
    /// 变动时间
    var changedAt: Date = Date()
    /// 原标价（缅币）
    var oldPrice: Decimal = 0
    /// 新标价（缅币）
    var newPrice: Decimal = 0
    /// 变动时的总进价快照，用来判断这次改价是不是把毛利改成了负数
    var landedCostAtChange: Decimal = 0
    /// 变动来源，如「编辑弹窗」「采用建议价」
    var sourceRaw: String = PriceChangeSource.edit.rawValue

    var item: Item?

    init(
        oldPrice: Decimal,
        newPrice: Decimal,
        landedCostAtChange: Decimal,
        source: PriceChangeSource,
        changedAt: Date = .now
    ) {
        self.oldPrice = oldPrice
        self.newPrice = newPrice
        self.landedCostAtChange = landedCostAtChange
        self.sourceRaw = source.rawValue
        self.changedAt = changedAt
    }

    var source: PriceChangeSource {
        PriceChangeSource(rawValue: sourceRaw) ?? .edit
    }

    /// 涨了还是降了，界面上一眼能看出来
    var delta: Decimal { newPrice - oldPrice }

    /// 改完之后的毛利率。进价为 0 时算不出来，返回 nil 而不是 0——
    /// 0% 会被读成「不赚钱」，与「不知道」是两回事。
    var marginAfter: Decimal? {
        guard landedCostAtChange > 0, newPrice > 0 else { return nil }
        return ((newPrice - landedCostAtChange) / newPrice * 100).rounded(1)
    }
}

enum PriceChangeSource: String, CaseIterable, Identifiable {
    case edit
    case advice

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .edit: "手动改价"
        case .advice: "采用建议价"
        }
    }
}

@MainActor
enum PriceAudit {
    /// 只有价格真的变了才记一笔。点开弹窗什么都没改就保存，不该在账本上留痕。
    @discardableResult
    static func record(
        item: Item,
        oldPrice: Decimal,
        newPrice: Decimal,
        source: PriceChangeSource,
        in context: ModelContext,
        now: Date = .now
    ) -> PriceChange? {
        guard oldPrice != newPrice else { return nil }
        let change = PriceChange(
            oldPrice: oldPrice,
            newPrice: newPrice,
            landedCostAtChange: item.landedCost,
            source: source,
            changedAt: now
        )
        change.item = item
        context.insert(change)
        return change
    }

    /// 这台机器的改价历史，新的在前
    static func history(for item: Item) -> [PriceChange] {
        (item.priceChanges ?? []).sorted { $0.changedAt > $1.changedAt }
    }
}
