import SwiftUI

/// 卡片内工具条：把搜索、筛选、排序收进表格上方一条带底色的横条。
/// 参考图里这一层是"专业感"的主要来源——没有它，卡片就只是一张白纸。
struct FilterBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Token.Space.s) {
            content
        }
        .padding(.horizontal, Token.Space.m)
        .frame(height: 44)
        .background(Token.Surface.header)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// 卡片底部的统计条：左侧条数、右侧选中汇总。
struct TableFooter: View {
    let leading: String
    var trailing: String?

    var body: some View {
        HStack(spacing: Token.Space.s) {
            Text(leading)
                .foregroundStyle(Token.Ink.secondary)
            Spacer(minLength: Token.Space.s)
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .foregroundStyle(Token.Ink.primary)
                    .monospacedDigit()
            }
        }
        .font(Token.Typography.caption)
        .padding(.horizontal, Token.Space.m)
        .frame(height: 32)
        .background(Token.Surface.header)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// 一像素分隔线
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Token.Border.hairline)
            .frame(height: 1)
    }
}

/// 自定义搜索框。系统 .searchable 只会把输入框塞进工具栏，
/// 而参考图的搜索是在内容区里、和筛选并排。
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    /// ⌘F 触发；消费后立刻置回 false
    @Binding var focusRequest: Bool

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Token.Ink.tertiary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(Token.Typography.body)
                .focused($focused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Token.Ink.tertiary)
                }
                .buttonStyle(.plain)
                .help("清空")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Token.Surface.field, in: .rect(cornerRadius: Token.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Token.Radius.control)
                .strokeBorder(Token.Border.hairline, lineWidth: 1)
        }
        .frame(width: 210)
        .onChange(of: focusRequest) { _, requested in
            guard requested else { return }
            focused = true
            focusRequest = false
        }
    }
}

/// 筛选胶囊的选项
struct PillOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: String { title }
}

/// 一组胶囊筛选。选中项用实心强调色，和参考图一致。
struct FilterPillGroup<Value: Hashable>: View {
    var label: String?
    let options: [PillOption<Value>]
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 4) {
            if let label {
                Text(label)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
                    .padding(.trailing, 2)
            }
            ForEach(options) { option in
                FilterPill(
                    title: option.title,
                    isSelected: option.value == selection
                ) {
                    onSelect(option.value)
                }
            }
        }
    }
}

struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Token.Ink.onAccent : Token.Ink.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background {
                    if isSelected {
                        Capsule().fill(Token.Accent.brand)
                    } else if hovering {
                        Capsule().fill(Token.Border.hairline)
                    } else {
                        Capsule().strokeBorder(Token.Border.hairline, lineWidth: 1)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// 详情栏的标题条：与列表工具条同高、同底色，右栏因此不再是一摞悬空卡片。
struct PanelHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Token.Space.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Token.Typography.cardTitle)
                    .foregroundStyle(Token.Ink.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Token.Space.s)
            trailing
        }
        .padding(.horizontal, Token.Space.m)
        .frame(height: 46)
        .background(Token.Surface.header)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 详情栏底部操作条，主操作固定在最显眼的位置。
struct PanelFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Token.Space.s) {
            content
        }
        .padding(.horizontal, Token.Space.m)
        .frame(height: 46)
        .background(Token.Surface.header)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// 详情面板内的分节：小标题 + 内容 + 分隔线。
/// 面板本身是白底，所以用分隔线而不是嵌套卡片来分层，
/// 否则白卡片叠白面板，边框会显得很碎。
struct PanelSection<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Token.Space.s) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Token.Ink.tertiary)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.tertiary)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Token.Space.m)
        .padding(.vertical, Token.Space.m)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

extension PanelSection where Content == EmptyView {
    init(title: String, trailing: String? = nil) {
        self.init(title: title, trailing: trailing) { EmptyView() }
    }
}
