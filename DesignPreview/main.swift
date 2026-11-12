import SwiftUI
import AppKit

/// 设计系统预览：把同一组组件分别用浅色与深色环境渲染，
/// 拼成一张图输出，用于确认两套色板都成立。
@main
struct DesignPreview {
    @MainActor
    static func main() {
        let renderer = ImageRenderer(content: board())
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("render failed")
            return
        }
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/design.png"
        try? png.write(to: URL(fileURLWithPath: out))
        print("written \(out) \(png.count) bytes")
    }

    @MainActor
    static func board() -> some View {
        HStack(alignment: .top, spacing: 0) {
            panel(scheme: .light, label: "浅色")
            panel(scheme: .dark, label: "深色")
        }
        .frame(width: 1000)
    }

    @MainActor
    static func panel(scheme: ColorScheme, label: String) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.m) {
            Text(label)
                .font(Token.Typography.pageTitle)
                .foregroundStyle(Token.Ink.primary)

            HStack(spacing: Token.Space.s) {
                Badge(text: "在库", tone: .ok)
                Badge(text: "部分退货", tone: .warn, style: .filled)
                Badge(text: "已售", tone: .neutral, style: .filled)
                Badge(text: "已全退", tone: .danger)
            }

            HStack(spacing: Token.Space.s) {
                StatCard(title: "今日毛利", value: "¥4,212", systemImage: "chart.line.uptrend.xyaxis", tone: .ok, delta: "↑ 较昨日 +8.2%")
                StatCard(title: "在库台数", value: "18", systemImage: "shippingbox", tone: .brand)
            }

            SectionCard(title: "成本") {
                KeyValueRow(label: "进价", value: "¥6,958")
                KeyValueRow(label: "落地成本", value: "¥7,220")
                KeyValueRow(label: "预计毛利", value: "+¥1,779", valueTone: .ok)
            }

            AlertCard(title: "低于成本", message: "iPhone 16 · 售价 ¥3,200 低于成本 ¥3,399", tone: .danger)

            VStack(alignment: .leading, spacing: Token.Space.s) {
                HStack {
                    CellTitle(title: "iPhone 17 Pro Max", subtitle: "F2LX9K3QABCD")
                    Spacer()
                    Text("¥7,220").font(Token.Typography.money).foregroundStyle(Token.Ink.primary)
                    Badge(text: "在库", tone: .ok)
                }
                Divider().overlay(Token.Border.hairline)
                HStack {
                    CellTitle(title: "iPhone 16", subtitle: "F2LX9K3QABCG")
                    Spacer()
                    Text("¥4,199").font(Token.Typography.money).foregroundStyle(Token.Ink.primary)
                    Badge(text: "92 天", tone: .danger, style: .filled)
                }
            }
            .padding(Token.Space.m)
            .background(Token.Surface.card, in: .rect(cornerRadius: Token.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Token.Radius.card)
                    .strokeBorder(Token.Border.hairline, lineWidth: 1)
            }
        }
        .padding(Token.Space.l)
        .frame(width: 500, alignment: .topLeading)
        .background(Token.Surface.canvas)
        .environment(\.colorScheme, scheme)
    }
}