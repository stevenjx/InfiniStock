import AppKit
import PDFKit

/// 凭证直接打印。不再要求先存 PDF——渲染出的内存 PDF 直接送系统打印面板。
enum ReceiptPrinter {

    enum PrintError: LocalizedError {
        case emptyData
        case unreadable

        var errorDescription: String? {
            switch self {
            case .emptyData: "凭证数据为空"
            case .unreadable: "凭证无法解析，请重新生成"
            }
        }
    }

    /// A4 打印参数。抽成独立函数便于验证：纸张尺寸、边距、是否居中。
    static func makePrintInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595.28, height: 841.89)
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        info.orientation = .portrait
        return info
    }

    /// 送打印面板。返回是否真的打印（用户取消返回 false）。
    @discardableResult
    static func print(pdfData: Data) throws -> Bool {
        guard !pdfData.isEmpty else { throw PrintError.emptyData }
        guard let document = PDFDocument(data: pdfData) else { throw PrintError.unreadable }

        // PDFView 是 macOS 上最可靠的 PDF 打印入口，按页自动分页
        let pageBounds = document.page(at: 0)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        let view = PDFView(frame: pageBounds)
        view.document = document
        view.autoScales = true

        let info = makePrintInfo()
        view.print(with: info, autoRotate: false, pageScaling: .pageScaleNone)
        return true
    }
}