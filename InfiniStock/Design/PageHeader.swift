import SwiftUI

/// 页面头：左侧大标题，右侧一组「标签 + 数值」摘要。
/// 参考图里这一行是页面层级的第一层，比表格本身更能定调。
struct PageHeaderSummary: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

struct PageHeader<Actions: View>: View {
    let title: String
    var items: [PageHeaderSummary] = []
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: Token.Space.l) {
            Text(title)
                .font(Token.Typography.screenTitle)
                .foregroundStyle(Token.Ink.primary)

            Spacer(minLength: Token.Space.m)

            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(Token.Ink.tertiary)
                    }
                    Text(item.label)
                        .foregroundStyle(Token.Ink.tertiary)
                    Text(item.value)
                        .foregroundStyle(Token.Ink.primary)
                        .monospacedDigit()
                }
            }
            .font(Token.Typography.caption)
            .lineLimit(1)

            if Actions.self != EmptyView.self {
                HStack(spacing: Token.Space.s) {
                    actions
                }
                .padding(.leading, Token.Space.xs)
            }
        }
    }
}

extension PageHeader where Actions == EmptyView {
    init(title: String, items: [PageHeaderSummary] = []) {
        self.init(title: title, items: items) { EmptyView() }
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
            .shadow(color: Token.Shadow.card, radius: 6, y: 2)
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

/// 右栏未选中时的占位：保持与详情一致的面板结构，不出现空洞。
struct DetailPlaceholder: View {
    let title: String
    let message: String
    var systemImage: String
    var subtitle: String = "未选择"

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "详情", subtitle: subtitle)
            EmptyState(title: title, message: message, systemImage: systemImage)
        }
        .background(Token.Surface.card)
    }
}
