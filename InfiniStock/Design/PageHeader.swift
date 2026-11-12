import SwiftUI

/// 页面头：左侧大标题，右侧一行灰色统计摘要。
/// 参考图的"高级感"主要来自这一层，而不是单元格里的胶囊。
struct PageHeader: View {
    let title: String
    var summary: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Token.Space.m) {
            Text(title)
                .font(Token.Typography.pageTitle)
                .foregroundStyle(Token.Ink.primary)
            Spacer(minLength: Token.Space.s)
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospacedDigit()
            }
        }
    }
}

/// 卡片容器：把内容托到浅底上，形成分层。
struct CardSurface: ViewModifier {
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Token.Surface.card)
            .clipShape(.rect(cornerRadius: Token.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Token.Radius.card)
                    .strokeBorder(Token.Border.hairline, lineWidth: 1)
            }
    }
}

extension View {
    /// 表格/列表坐进圆角卡片
    func cardSurface(padding: CGFloat = 0) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

/// 分节标题（页面内的二级标题，与卡片标题区分）
struct SectionHeading: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(Token.Typography.cardTitle)
                .foregroundStyle(Token.Ink.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
            }
        }
    }
}