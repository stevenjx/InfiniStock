import Foundation

/// 机型。把「MacBook Air M2 13"」这种自由文本拆成可比较的结构。
///
/// 为什么必须结构化：型号是所有统计的分组键。同一台机器写成「MacBook Air M2 13"」
/// 和「MBA M2」就是两款机器，售速、型号毛利、补货判断会同时失真——不是少算，
/// 是算错。字符串只能靠人去保持一致，结构体不需要。
///
/// 不引入新的存储字段：仍然写入 Item.modelName，只是这一列的内容从此由
/// `displayName` 生成。老数据在启动时由 `migrate` 归一一次，之后判重按 key。
struct MacModel: Codable, Hashable, Identifiable {
    /// 产品线
    var line: Line
    /// 屏幕尺寸（英寸），0 表示未知
    var inches: Int
    /// 芯片，如 M2 / M3 Pro / M1 Max
    var chip: String

    var id: String { key }

    enum Line: String, Codable, CaseIterable, Identifiable {
        case air = "MacBook Air"
        case pro = "MacBook Pro"

        var id: String { rawValue }
        /// 产品线名是英文专有名词（MacBook Air / Pro），不需要翻译
        var label: String { rawValue }
    }

    /// 归一后的标准写法，也是写进 Item.modelName 的内容
    var displayName: String {
        var parts = [line.rawValue]
        if inches > 0 { parts.append("\(inches)\"") }
        if !chip.isEmpty { parts.append(chip) }
        return parts.joined(separator: " ")
    }

    /// 判重与分组用的键。大小写、空格、全半角引号都不影响比较
    var key: String {
        displayName
            .lowercased()
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2019}", with: "\"")
            .replacingOccurrences(of: " ", with: "")
    }

    // MARK: - 解析

    /// 从自由文本里认出机型。认不出关键特征时返回 nil——宁可让用户选，
    /// 也不要猜出一个「大概对」的型号，那会把脏数据又写回去。
    static func parse(_ raw: String) -> MacModel? {
        let text = normalizeQuotes(raw)
            .replacingOccurrences(of: "macbook", with: "MacBook", options: .caseInsensitive)

        // 缩写先展开：后面只保留一条解析路径，少一处分支就少一处走样
        let expanded = text
            .replacingOccurrences(of: "MBA", with: "MacBook Air", options: .caseInsensitive)
            .replacingOccurrences(of: "MBP", with: "MacBook Pro", options: .caseInsensitive)

        guard expanded.range(of: "MacBook", options: .caseInsensitive) != nil else { return nil }

        // 产品线：Air 优先于 Pro，因为 "MacBook Air" 里没有 Pro，但 "MBP" 是 Pro 的缩写
        let lower = expanded.lowercased()
        let line: Line
        if lower.contains("air") || lower.contains("mba") {
            line = .air
        } else if lower.contains("pro") || lower.contains("mbp") {
            line = .pro
        } else {
            return nil
        }

        // 尺寸：抓 "13" / "14" / "16" / "15" 这类两位数字，取第一处
        var inches = 0
        if let match = expanded.range(of: #"\b(1[3-7])\b"#, options: .regularExpression) {
            inches = Int(expanded[match]) ?? 0
        } else if let match = expanded.range(of: #"(1[3-7])\D"#, options: .regularExpression) {
            // 无空格写法，如 14寸 / 13.3
            let digits = expanded[match].filter(\.isNumber)
            inches = Int(digits) ?? 0
        }

        let chip = parseChip(lower)
        guard !chip.isEmpty || inches > 0 else { return nil }
        return MacModel(line: line, inches: inches, chip: chip)
    }

    private static func normalizeQuotes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2019}", with: "\"")
            .replacingOccurrences(of: "英寸", with: "\"")
            .replacingOccurrences(of: "寸", with: "\"")
    }

    /// 芯片：M 系列带后缀，或 Intel（i5/i7/i9）。
    /// 只认得出形状的写法，认不出就留空，由用户补。
    private static func parseChip(_ lower: String) -> String {
        let pattern = #"\bm([0-9])(?:\s?(pro|max|ultra))?\b"#
        if let match = lower.range(of: pattern, options: .regularExpression) {
            // 先标准化再大写："m3 pro" → "M3 Pro"。
            // 不能先去掉空格，否则 M3 Pro 会变成 M3PRO，与目录里的写法对不上。
            let parts = lower[match].split(separator: " ")
            guard let base = parts.first else { return "" }
            // M 是大写，后缀只有首字母大写：M3 Pro / M1 Max，不是 M3 PRO
            let suffix = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return ([base.uppercased()] + suffix).joined(separator: " ")
        }
        for intel in ["i9", "i7", "i5", "i3"] {
            if lower.contains(intel) { return intel.uppercased() }
        }
        return ""
    }

    // MARK: - 目录

    /// 入库时可选的标准机型。顺序即常用程度。
    static let catalog: [MacModel] = [
        MacModel(line: .air, inches: 13, chip: "M1"),
        MacModel(line: .air, inches: 13, chip: "M2"),
        MacModel(line: .air, inches: 15, chip: "M2"),
        MacModel(line: .air, inches: 13, chip: "M3"),
        MacModel(line: .air, inches: 15, chip: "M3"),
        MacModel(line: .pro, inches: 13, chip: "M2"),
        MacModel(line: .pro, inches: 14, chip: "M2 Pro"),
        MacModel(line: .pro, inches: 14, chip: "M3"),
        MacModel(line: .pro, inches: 14, chip: "M3 Pro"),
        MacModel(line: .pro, inches: 14, chip: "M3 Max"),
        MacModel(line: .pro, inches: 16, chip: "M1 Max"),
        MacModel(line: .pro, inches: 16, chip: "M3 Pro"),
        MacModel(line: .pro, inches: 16, chip: "M3 Max"),
    ]

    /// 老数据归一：把库里已有的 modelName 全部改写成标准写法。
    /// 返回被改写的条数，用于启动日志与验收。
    @discardableResult
    static func migrate(_ items: [Item]) -> Int {
        var changed = 0
        for item in items {
            guard let parsed = parse(item.modelName) else { continue }
            let canonical = parsed.displayName
            guard canonical != item.modelName else { continue }
            item.modelName = canonical
            changed += 1
        }
        return changed
    }
}
