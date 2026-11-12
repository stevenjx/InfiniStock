import Foundation

/// 金额一律使用 Decimal，避免 Double 在批量统计中累积分位误差。
///
/// 币种口径是固定的，不做成可配置项——这家店只从国内拿货、在缅甸卖：
/// - 进价：人民币（¥），填国内卖家的报价
/// - 汇率：1 元人民币 = N 缅币，只填数字，例如 420
/// - 运费、总进价、卖价、毛利：缅币（K）
enum Money {

    static func parse(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "K", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// 总进价（缅币）= 人民币进价 × 汇率 + 缅币运费
    static func landedCost(costCNY: Decimal, rate: Decimal, shipping: Decimal) -> Decimal {
        (costCNY * rate + shipping).rounded(2)
    }

    static func text(_ value: Decimal) -> String {
        value.rounded(2).description
    }

    /// 缅币千分位。整数带逗号，小数最多两位且只在需要时出现——
    /// 缅币日常没有分币，写 12,500 比 12,500.00 更好读。
    private static let kyatFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func kyat(_ value: Decimal) -> String {
        let rounded = value.rounded(2)
        let body = kyatFormatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "0"
        return "K " + body
    }
}

extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }

    /// 人民币进价
    var cny: String {
        self.formatted(.currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
    }

    /// 缅币金额：售价、总进价、毛利
    var mmk: String {
        Money.kyat(self)
    }

    /// 带正负号，用于毛利展示：+K 1,879,880 / -K 320,000
    var signedMMK: String {
        if self > 0 { return "+" + mmk }
        if self < 0 { return "-" + (-self).mmk }
        return mmk
    }
}
