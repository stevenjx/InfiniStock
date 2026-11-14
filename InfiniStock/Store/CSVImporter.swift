import Foundation
import SwiftData

/// CSV 批量导入。分两步：先 preview 做全量校验（不写库），再 commit 只写入通过的行。
/// 这样 100 行里有 3 行错误时，97 台入库、3 行带行号报错，库里不会留脏数据。
@MainActor
enum CSVImporter {

    struct RowPlan {
        let line: Int
        let serialNumber: String
        let modelName: String
        let chip: String
        let memory: String
        let storage: String
        let color: String
        let condition: ItemCondition
        let costCNY: Decimal
        let exchangeRate: Decimal
        let shipping: Decimal
        let listPrice: Decimal
        let batteryHealth: Int
        let batteryCycles: Int
    }

    struct Issue: Identifiable {
        var id: String { "\(line)-\(field)" }
        let line: Int
        let field: String
        let reason: String
    }

    struct Preview {
        var rows: [RowPlan]
        var issues: [Issue]
        var totalLines: Int
    }

    // 表头别名：中文表头与导出文件一致，同时容忍常见英文写法
    private static let aliases: [String: String] = [
        "序列号": "serial", "serial": "serial", "serialnumber": "serial", "sn": "serial",
        "型号": "model", "model": "model", "modelname": "model",
        "芯片": "chip", "chip": "chip",
        "内存": "memory", "memory": "memory", "ram": "memory",
        "存储": "storage", "storage": "storage", "capacity": "storage",
        "颜色": "color", "color": "color",
        "成色": "condition", "condition": "condition", "grade": "condition",
        "电池健康": "battery", "电池": "battery", "battery": "battery", "batteryhealth": "battery",
        "循环次数": "cycles", "循环": "cycles", "cycles": "cycles", "batterycycles": "cycles",
        "进价": "cost", "进价(人民币)": "cost", "cost": "cost", "costamount": "cost",
        "汇率": "rate", "rate": "rate", "exchangerate": "rate",
        "运费": "shipping", "运费(缅币)": "shipping", "shipping": "shipping",
        "标价": "list", "list": "list", "listprice": "list", "售价": "list",
    ]

    // MARK: - 预检

    static func preview(csv data: Data, in context: ModelContext) -> Preview {
        let rows = parseRows(decodeText(data))
        guard let headerRow = rows.first else {
            return Preview(rows: [], issues: [Issue(line: 0, field: "文件", reason: "文件为空")], totalLines: 0)
        }

        var columnIndex: [String: Int] = [:]
        for (index, title) in headerRow.enumerated() {
            let key = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let field = aliases[key], columnIndex[field] == nil {
                columnIndex[field] = index
            }
        }

        guard columnIndex["serial"] != nil, columnIndex["model"] != nil else {
            return Preview(
                rows: [],
                issues: [Issue(line: 1, field: "表头", reason: "缺少必需列「序列号」或「型号」")],
                totalLines: max(0, rows.count - 1)
            )
        }

        var plans: [RowPlan] = []
        var issues: [Issue] = []
        var seenSerials: [String: Int] = [:]   // 文件内查重，记住首次出现的行号
        let existingSerials = existingSerialSet(in: context)

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2   // 1 是表头
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }

            func value(_ field: String) -> String {
                guard let index = columnIndex[field], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let serial = InventoryService.normalize(value("serial"))
            let model = value("model")

            if serial.isEmpty {
                issues.append(Issue(line: line, field: "序列号", reason: "为空"))
                continue
            }
            if model.isEmpty {
                issues.append(Issue(line: line, field: "型号", reason: "为空"))
                continue
            }
            if let firstLine = seenSerials[serial] {
                issues.append(Issue(line: line, field: "序列号", reason: String(localized: "与第 \(firstLine) 行重复")))
                continue
            }
            if existingSerials.contains(serial) {
                issues.append(Issue(line: line, field: "序列号", reason: "库中已存在"))
                continue
            }

            guard let cost = number(value("cost"), field: "进价", line: line, issues: &issues) else { continue }
            guard let rate = number(value("rate"), field: "汇率", line: line, issues: &issues, default: 1) else { continue }
            guard let shipping = number(value("shipping"), field: "运费", line: line, issues: &issues, default: 0) else { continue }
            guard let list = number(value("list"), field: "标价", line: line, issues: &issues, default: 0) else { continue }

            let battery = intValue(value("battery"), field: "电池健康", line: line, issues: &issues)
            let cycles = intValue(value("cycles"), field: "循环次数", line: line, issues: &issues)
            if let battery, !(0...100).contains(battery) {
                issues.append(Issue(line: line, field: "电池健康", reason: "需在 0–100 之间"))
                continue
            }
            if rate <= 0 {
                issues.append(Issue(line: line, field: "汇率", reason: "必须大于 0"))
                continue
            }

            let condition = parseCondition(value("condition"), line: line, issues: &issues)
            guard let condition else { continue }

            seenSerials[serial] = line
            plans.append(RowPlan(
                line: line,
                serialNumber: serial,
                modelName: model,
                chip: value("chip"),
                memory: value("memory"),
                storage: value("storage"),
                color: value("color"),
                condition: condition,
                costCNY: cost,
                exchangeRate: rate,
                shipping: shipping,
                listPrice: list,
                batteryHealth: battery ?? 0,
                batteryCycles: cycles ?? 0
            ))
        }

        return Preview(rows: plans, issues: issues, totalLines: max(0, rows.count - 1))
    }

    // MARK: - 落库

    /// 只写入通过校验的行。返回实际写入台数。
    @discardableResult
    static func commit(_ preview: Preview, batch: Batch?, in context: ModelContext) throws -> Int {
        guard !preview.rows.isEmpty else { return 0 }

        var inserted: [Item] = []
        for plan in preview.rows {
            // 预检到落库之间库可能被改动，这里再查一次，宁可漏导也不重号
            guard !InventoryService.serialExists(plan.serialNumber, in: context) else { continue }

            let item = Item(
                serialNumber: plan.serialNumber,
                modelName: plan.modelName,
                chip: plan.chip,
                memory: plan.memory,
                storage: plan.storage,
                color: plan.color,
                condition: plan.condition,
                costCNY: plan.costCNY,
                exchangeRate: plan.exchangeRate,
                shipping: plan.shipping,
                listPrice: plan.listPrice,
                batteryHealth: plan.batteryHealth,
                batteryCycles: plan.batteryCycles
            )
            item.batch = batch
            context.insert(item)
            inserted.append(item)
        }

        if let batch, !inserted.isEmpty {
            CostAllocation.reallocate(batch)
        }

        try context.save()
        inserted.forEach(SpotlightIndexer.index)
        return inserted.count
    }

    /// 把错误清单导出成 CSV，方便改完再导
    static func issuesCSV(_ issues: [Issue]) -> Data {
        let header = "行号,字段,原因"
        let rows = issues.map { issue in
            [String(issue.line), issue.field, issue.reason]
                .map { field in
                    field.contains(",") || field.contains("\"")
                        ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                        : field
                }
                .joined(separator: ",")
        }
        return Data(("\u{FEFF}" + ([header] + rows).joined(separator: "\r\n") + "\r\n").utf8)
    }

    // MARK: - 解析

    private static func decodeText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        // Excel 另存的中文 CSV 常见 GBK
        let gbk = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String(data: data, encoding: String.Encoding(rawValue: gbk)) ?? ""
    }

    /// RFC 4180 风格：支持引号包裹、双引号转义、CRLF、末尾无换行。
    /// 必须按 Unicode 标量遍历——Swift 会把 CR+LF 合并成一个 Character，
    /// 按 Character 解析时行分隔符永远匹配不上，Excel 导出的文件会整份读成一行。
    static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        let scalars = Array(text.unicodeScalars)
        let quote: Unicode.Scalar = "\""
        let comma: Unicode.Scalar = ","
        let carriageReturn: Unicode.Scalar = "\r"
        let lineFeed: Unicode.Scalar = "\n"
        var index = 0

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while index < scalars.count {
            let scalar = scalars[index]

            if inQuotes {
                if scalar == quote {
                    if index + 1 < scalars.count, scalars[index + 1] == quote {
                        field.unicodeScalars.append(quote)
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                field.unicodeScalars.append(scalar)
                index += 1
                continue
            }

            if scalar == quote {
                inQuotes = true
            } else if scalar == comma {
                endField()
            } else if scalar == carriageReturn {
                // 交给下一个 \n 收行；单独的 \r 也要收行
                if index + 1 >= scalars.count || scalars[index + 1] != lineFeed {
                    endRow()
                }
            } else if scalar == lineFeed {
                endRow()
            } else {
                field.unicodeScalars.append(scalar)
            }
            index += 1
        }

        if !field.isEmpty || !row.isEmpty { endRow() }

        // 去 BOM
        if var first = rows.first, var firstCell = first.first {
            if firstCell.hasPrefix("\u{FEFF}") { firstCell.removeFirst() }
            first[0] = firstCell
            rows[0] = first
        }
        return rows
    }

    private static func existingSerialSet(in context: ModelContext) -> Set<String> {
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        return Set(items.map(\.serialNumber))
    }

    private static func number(
        _ raw: String, field: String, line: Int,
        issues: inout [Issue], default fallback: Decimal? = nil
    ) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            if let fallback { return fallback }
            issues.append(Issue(line: line, field: field, reason: "为空"))
            return nil
        }
        guard let value = Money.parse(trimmed) else {
            issues.append(Issue(line: line, field: field, reason: "不是有效数字"))
            return nil
        }
        if value < 0 {
            issues.append(Issue(line: line, field: field, reason: "不能为负数"))
            return nil
        }
        return value
    }

    /// 电池字段整列缺失是正常的（老模板没有这两列），留空按未检测处理
    private static func intValue(
        _ raw: String, field: String, line: Int, issues: inout [Issue]
    ) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let value = Int(trimmed) else {
            issues.append(Issue(line: line, field: field, reason: "不是整数"))
            return nil
        }
        return value
    }

    private static func parseCondition(_ raw: String, line: Int, issues: inout [Issue]) -> ItemCondition? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .p95 }
        if let matched = ItemCondition(rawValue: trimmed) { return matched }
        issues.append(Issue(
            line: line, field: "成色",
            // 内层 join 的引号进不了 String Catalog 的键，拆成两次格式化
            reason: String(
                format: String(localized: "无法识别「%@」，可选：%@"),
                trimmed,
                ItemCondition.allCases.map(\.rawValue).joined(separator: " / ")
            )
        ))
        return nil
    }
}