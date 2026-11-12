import AppKit
import CoreText

/// 用 Core Graphics 直接绘制矢量 PDF（不是截图转 PDF），缩放不失真、可选中文字。
enum ReceiptPDFRenderer {
    static let pageSize = CGSize(width: 595.28, height: 841.89) // A4

    private enum Align { case left, right }

    static func render(_ document: ReceiptDocument) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        context.beginPDFPage(nil)
        draw(document, in: context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    // MARK: - 绘制

    private static func draw(_ document: ReceiptDocument, in context: CGContext) {
        let margin: CGFloat = 48
        let contentWidth = pageSize.width - margin * 2
        let right = margin + contentWidth
        var y: CGFloat = 56

        // 抬头：店名优先；未设置时退回通用标题
        if !document.shopName.isEmpty {
            text(document.shopName, x: margin, topY: y, font: .boldSystemFont(ofSize: 19), color: .black, in: context)
            var sub = [document.shopPhone, document.shopAddress].filter { !$0.isEmpty }.joined(separator: "  ·  ")
            if sub.isEmpty { sub = "销售凭证" }
            text(sub, x: margin, topY: y + 25, font: .systemFont(ofSize: 9), color: .gray, in: context)
            text("销售凭证", x: margin, topY: y + 40, font: .systemFont(ofSize: 11), color: .darkGray, in: context)
        } else {
            text("销售凭证", x: margin, topY: y, font: .boldSystemFont(ofSize: 22), color: .black, in: context)
            text("SALES RECEIPT", x: margin, topY: y + 30, font: .systemFont(ofSize: 8), color: .gray, in: context)
        }

        text("单号 \(document.number)", x: right, topY: y + 4, font: .systemFont(ofSize: 10), color: .black, align: .right, in: context)
        text(dateText(document.issuedAt), x: right, topY: y + 20, font: .systemFont(ofSize: 10), color: .gray, align: .right, in: context)

        y += 68
        line(from: CGPoint(x: margin, y: y), to: CGPoint(x: right, y: y), width: 1, color: .black, in: context)
        y += 18

        text("客户", x: margin, topY: y, font: .systemFont(ofSize: 11), color: .gray, in: context)
        text(document.customerName.isEmpty ? "—" : document.customerName,
             x: margin + 40, topY: y, font: .systemFont(ofSize: 11), color: .black, in: context)

        text("联系方式", x: margin + 240, topY: y, font: .systemFont(ofSize: 11), color: .gray, in: context)
        text(document.customerContact.isEmpty ? "—" : document.customerContact,
             x: margin + 300, topY: y, font: .systemFont(ofSize: 11), color: .black, in: context)

        text("收款", x: right - 100, topY: y, font: .systemFont(ofSize: 11), color: .gray, in: context)
        text(document.paymentMethod, x: right, topY: y, font: .systemFont(ofSize: 11), color: .black, align: .right, in: context)

        y += 26

        // 表头
        let columns: [(title: String, x: CGFloat, width: CGFloat)] = [
            ("序号", margin + 6, 30),
            ("型号", margin + 40, 140),
            ("序列号", margin + 184, 120),
            ("规格", margin + 308, 78),
            ("成色", margin + 390, 40),
            ("金额", right - 6, 76),
        ]

        let headerHeight: CGFloat = 22
        context.setFillColor(NSColor(white: 0.94, alpha: 1).cgColor)
        context.fill(CGRect(x: margin, y: pageSize.height - y - headerHeight, width: contentWidth, height: headerHeight))

        for column in columns {
            let isAmount = column.title == "金额"
            text(column.title, x: column.x, topY: y + 6, font: .systemFont(ofSize: 9.5), color: .darkGray,
                 align: isAmount ? .right : .left, in: context)
        }
        y += headerHeight

        // 明细
        for (index, item) in document.lines.enumerated() {
            text("\(index + 1)", x: margin + 6, topY: y + 7, font: .systemFont(ofSize: 9.5), color: .black, in: context)
            text(item.modelName, x: margin + 40, topY: y + 7, font: .systemFont(ofSize: 9.5), color: .black, in: context)
            text(item.serialNumber, x: margin + 184, topY: y + 7, font: .systemFont(ofSize: 9.5), color: .black, in: context)
            text(item.spec, x: margin + 308, topY: y + 7, font: .systemFont(ofSize: 9.5), color: .black, in: context)
            text(item.condition, x: margin + 390, topY: y + 7, font: .systemFont(ofSize: 9.5), color: .black, in: context)
            text(item.price.cny, x: right - 6, topY: y + 7, font: .systemFont(ofSize: 9.5), color: .black, align: .right, in: context)

            y += 26
            line(from: CGPoint(x: margin, y: y), to: CGPoint(x: right, y: y), width: 0.4, color: .lightGray, in: context)
        }

        y += 8

        // 小计 → 折扣 → 抹零 → 应收
        var amountRows: [(String, String)] = [
            ("商品小计（\(document.lines.count) 台）", document.subtotal.cny)
        ]
        if document.discount > 0 {
            amountRows.append(("折扣", "−" + document.discount.cny))
        }
        if document.rounding > 0 {
            amountRows.append(("抹零", "−" + document.rounding.cny))
        }

        for (label, value) in amountRows {
            text(label, x: right - 200, topY: y, font: .systemFont(ofSize: 10), color: .darkGray, in: context)
            text(value, x: right - 6, topY: y, font: .systemFont(ofSize: 10), color: .black, align: .right, in: context)
            y += 18
        }

        line(from: CGPoint(x: right - 200, y: y - 4), to: CGPoint(x: right, y: y - 4), width: 0.4, color: .lightGray, in: context)

        text("应收合计", x: right - 200, topY: y, font: .boldSystemFont(ofSize: 11), color: .black, in: context)
        text(document.total.cny, x: right - 6, topY: y - 2, font: .boldSystemFont(ofSize: 14), color: .black, align: .right, in: context)
        y += 26
        text("大写：\(ChineseAmount.uppercase(document.total))", x: margin + 6, topY: y, font: .systemFont(ofSize: 10), color: .darkGray, in: context)

        if document.returnedCount > 0 {
            y += 16
            text("售后：本单已退货 \(document.returnedCount) 台，退回 \(document.returnedAmount.cny)，上述金额为退货后净额。",
                 x: margin + 6, topY: y, font: .systemFont(ofSize: 9), color: .red, in: context)
        }

        y += 32
        line(from: CGPoint(x: margin, y: y), to: CGPoint(x: right, y: y), width: 0.4, color: .lightGray, in: context)
        y += 14

        let noteFont = NSFont.systemFont(ofSize: 8.5)
        var notes = [
            "1. 本凭证为交易记录，非增值税发票，不可作为税务抵扣凭证。",
            "2. 请当面验机；非人为故障自签收之日起 \(document.warrantyDays) 日内协商处理，人为损坏不在范围内。",
            "3. 序列号与成交价以本凭证为准，涂改无效。",
        ]
        if !document.footnote.isEmpty {
            notes.insert(document.footnote, at: 0)
        }
        for note in notes {
            for line in wrap(note, width: contentWidth - 12, font: noteFont) {
                text(line, x: margin + 6, topY: y, font: noteFont, color: .gray, in: context)
                y += 13
            }
        }

        y += 10
        text("签收：____________________", x: margin + 6, topY: y, font: .systemFont(ofSize: 9), color: .gray, in: context)
        text("日期：____________________", x: margin + 280, topY: y, font: .systemFont(ofSize: 9), color: .gray, in: context)

        // 页脚
        text("由 InfiniStock 生成 · \(dateText(Date()))", x: right, topY: pageSize.height - 44,
             font: .systemFont(ofSize: 8.5), color: .gray, align: .right, in: context)
    }

    // MARK: - 基础图元

    private static func text(
        _ string: String,
        x: CGFloat,
        topY: CGFloat,
        font: NSFont,
        color: NSColor,
        align: Align = .left,
        in context: CGContext
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        var ascent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, nil, nil))

        var originX = x
        switch align {
        case .left: break
        case .right: originX = x - width
        }

        context.textMatrix = .identity
        context.textPosition = CGPoint(x: originX, y: pageSize.height - topY - ascent)
        CTLineDraw(line, context)
    }

    private static func line(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor, in context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.move(to: CGPoint(x: start.x, y: pageSize.height - start.y))
        context.addLine(to: CGPoint(x: end.x, y: pageSize.height - end.y))
        context.strokePath()
    }

    private static func wrap(_ string: String, width: CGFloat, font: NSFont) -> [String] {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let source = string as NSString

        var lines: [String] = []
        var start = 0
        while start < source.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            guard count > 0 else { break }
            lines.append(source.substring(with: NSRange(location: start, length: count)))
            start += count
        }
        return lines
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
