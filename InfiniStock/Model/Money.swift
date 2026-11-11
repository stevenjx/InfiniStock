import Foundation

/// 金额一律使用 Decimal，避免 Double 在批量统计中累积分位误差。
enum Money {

    static func parse(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// 落地成本 = 原币进价 × 汇率 + 运费（人民币）
    static func landedCost(amount: Decimal, rate: Decimal, shippingCNY: Decimal) -> Decimal {
        (amount * rate + shippingCNY).rounded(2)
    }

    static func text(_ value: Decimal) -> String {
        value.rounded(2).description
    }
}

extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }

    var cny: String {
        self.formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
    }
}
