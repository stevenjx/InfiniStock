import Foundation

/// 定价建议：把「目标毛利率」和「库龄」换成一条能直接用的标价。
///
/// 两步，都能在界面上讲清楚：
/// 1. 按目标毛利率反推基准价。本店口径的毛利率 = 毛利 ÷ 售价，
///    所以 售价 = 总进价 ÷ (1 − 目标毛利率)。
/// 2. 库龄超过 30 天后每满一周降 1%，最多降 15%，但绝不低于总进价——
///    建议价如果低于成本，那是在建议亏本，不如不给建议。
///
/// 纯计算，不读设置、不落库，便于 verify.sh 直接断言。
struct PricingAdvice: Equatable {
    /// 按目标毛利率算出的、未计库龄的标价
    let basePrice: Decimal
    /// 计入库龄折价后的建议价
    let suggestedPrice: Decimal
    /// 相对基准价降了多少（缅币）
    let markdown: Decimal
    /// 生效的折价百分比，0 表示未折价
    let markdownPercent: Int
    let ageInDays: Int
    /// 目标毛利率，用于把「这条建议怎么来的」讲清楚
    let targetMarginPercent: Int

    /// 超过这个库龄才开始折价
    static let markdownStartDays = 30
    /// 每满一周降 1%
    static let markdownPerWeek = 1
    /// 折价上限 15%
    static let maxMarkdownPercent = 15

    /// - Parameters:
    ///   - targetMarginPercent: 目标毛利率，界面上按百分数整数填
    ///   - ageInDays: 库龄，传 0 表示不分库龄（新入库）
    static func make(
        landedCost: Decimal,
        targetMarginPercent: Int,
        ageInDays: Int
    ) -> PricingAdvice? {
        guard landedCost > 0 else { return nil }
        // 毛利率 ≥ 100% 时分母为 0，这条建议没有意义
        guard targetMarginPercent >= 0, targetMarginPercent < 100 else { return nil }

        let margin = Decimal(targetMarginPercent) / 100
        let base = (landedCost / (1 - margin)).rounded(0)

        let overdueWeeks = max(0, (ageInDays - markdownStartDays) / 7)
        let percent = min(overdueWeeks * markdownPerWeek, maxMarkdownPercent)
        let discounted = (base * (1 - Decimal(percent) / 100)).roundedToTenThousand()
        let floor = landedCost.roundedToTenThousand()

        // 兜底永远高于总进价，否则宁可报"不建议降价"
        let suggested = max(discounted, floor)
        let markdown = base - suggested

        return PricingAdvice(
            basePrice: base,
            suggestedPrice: suggested,
            markdown: markdown,
            markdownPercent: percent,
            ageInDays: ageInDays,
            targetMarginPercent: targetMarginPercent
        )
    }

    static func make(for item: Item, targetMarginPercent: Int) -> PricingAdvice? {
        guard item.status == .inStock else { return nil }
        return make(
            landedCost: item.landedCost,
            targetMarginPercent: targetMarginPercent,
            ageInDays: item.ageInDays
        )
    }

    /// 一句话说明这条建议怎么来的，直接显示在详情面板里。
    /// 刻意不报反推出来的原始金额（如 K 1,843,529）——它和取整后的建议价并排出现，
    /// 只会让人多一个"为什么对不上"的疑问。
    var explanation: String {
        var text = String(localized: "目标毛利率 \(targetMarginPercent)% 反推")
        if markdownPercent > 0 {
            text += "，库龄 \(ageInDays) 天再降 \(markdownPercent)%"
        }
        return text
    }
}

extension Decimal {
    /// 缅币报价习惯以万为单位取整，2,588,235 读起来不如 2,590,000
    func roundedToTenThousand() -> Decimal {
        (self / 10_000).rounded(0) * 10_000
    }
}
