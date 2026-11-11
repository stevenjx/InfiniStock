import Foundation

/// 人民币金额转中文大写。凭证上的金额必须与数字一致，这是可验证的死规则。
enum ChineseAmount {
    private static let digits = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
    private static let groupUnits = ["", "万", "亿", "万亿"]
    private static let innerUnits = ["", "拾", "佰", "仟"]

    static func uppercase(_ value: Decimal) -> String {
        let cents = NSDecimalNumber(decimal: value * 100)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain, scale: 0,
                raiseOnExactness: false, raiseOnOverflow: false,
                raiseOnUnderflow: false, raiseOnDivideByZero: false
            ))
            .int64Value

        if cents == 0 { return "零元整" }

        let negative = cents < 0
        let absolute = abs(cents)
        let yuan = absolute / 100
        let jiao = (absolute % 100) / 10
        let fen = absolute % 10

        var result = ""
        if yuan > 0 { result += group(yuan) + "元" }

        if jiao == 0 && fen == 0 {
            result += "整"
        } else {
            if jiao > 0 {
                result += digits[Int(jiao)] + "角"
            } else if yuan > 0 && fen > 0 {
                result += "零"
            }
            if fen > 0 {
                result += digits[Int(fen)] + "分"
            }
        }
        return negative ? "负" + result : result
    }

    private static func group(_ number: Int64) -> String {
        var sections: [Int] = []
        var remaining = number
        while remaining > 0 {
            sections.append(Int(remaining % 10000))
            remaining /= 10000
        }

        var output = ""
        for index in (0..<sections.count).reversed() {
            let section = sections[index]
            if section == 0 {
                if !output.isEmpty && !output.hasSuffix("零") { output += "零" }
                continue
            }
            // 低位分组不足四位时，必须补零，例如 10001 应为 壹万零壹
            if !output.isEmpty && section < 1000 && !output.hasSuffix("零") {
                output += "零"
            }
            output += sectionText(section) + groupUnits[index]
        }

        while output.hasSuffix("零") { output.removeLast() }
        return output
    }

    private static func sectionText(_ number: Int) -> String {
        var digitsOfSection: [Int] = []
        var remaining = number
        for _ in 0..<4 {
            digitsOfSection.append(remaining % 10)
            remaining /= 10
        }

        var output = ""
        var pendingZero = false
        for index in (0..<4).reversed() {
            let digit = digitsOfSection[index]
            if digit == 0 {
                if !output.isEmpty { pendingZero = true }
            } else {
                if pendingZero {
                    output += "零"
                    pendingZero = false
                }
                output += digits[digit] + innerUnits[index]
            }
        }
        return output
    }
}
