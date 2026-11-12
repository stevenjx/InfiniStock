import AppKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// 凭证预览 + 保存 / 分享 / 打印。
struct ReceiptSheet: View {
    let order: Order

    @Environment(\.dismiss) private var dismiss
    @State private var pdfData: Data?
    @State private var fileURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let pdfData {
                PDFPreview(data: pdfData)
            } else {
                ContentUnavailableView("无法生成凭证", systemImage: "doc.text", description: Text("订单没有关联机器"))
            }

            Divider()

            HStack(spacing: 10) {
                Button("关闭") { dismiss() }
                Spacer()
                if let fileURL {
                    ShareLink(item: fileURL) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        NSWorkspace.shared.open(fileURL)
                    } label: {
                        Label("在预览中打开", systemImage: "eye")
                    }
                }
                Button("打印…") { printReceipt() }
                    .keyboardShortcut("p")
                    .disabled(pdfData == nil)
                Button("保存 PDF…") { save() }
                    .keyboardShortcut("s")
                    .disabled(pdfData == nil)
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 760)
        .task {
            guard let data = ReceiptPDFRenderer.render(ReceiptDocument(order: order)) else {
                errorMessage = "渲染失败"
                return
            }
            pdfData = data
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("凭证-\(order.number).pdf")
            if (try? data.write(to: url)) != nil {
                fileURL = url
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func printReceipt() {
        guard let pdfData else { return }
        do {
            try ReceiptPrinter.print(pdfData: pdfData)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let pdfData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "凭证-\(order.number).pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pdfData.write(to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .windowBackgroundColor
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}
