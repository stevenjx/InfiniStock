import SwiftUI

/// 胶囊徽章。outline 用于"进行中/在库"，filled 用于"已完成/已售"这类终态。
struct Badge: View {
    enum Style {
        case outline
        case filled
    }

    let text: String
    let tone: Tone
    var style: Style = .outline

    var body: some View {
        Text(text)
            .font(Token.Typography.caption.weight(.medium))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background {
                switch style {
                case .outline:
                    Capsule().strokeBorder(tone.color.opacity(0.6), lineWidth: 1)
                case .filled:
                    Capsule().fill(tone.fill)
                }
            }
            .fixedSize()
            .accessibilityLabel(Text("\(text)，\(tone.accessibilityName)"))
    }
}

/// 双行单元格：主标题 + 灰色副标题（序列号等）。
struct CellTitle: View {
    let title: String
    var subtitle: String?
    var monospacedSubtitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Token.Typography.cellPrimary)
                .foregroundStyle(Token.Ink.primary)
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
                    .monospaced(monospacedSubtitle)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// KPI 卡：图标 + 标签 + 数字 + 可选涨跌行。
struct StatCard: View {
    let title: String
    let value: String
    var systemImage: String
    var tone: Tone = .brand
    var delta: String?
    var deltaTone: Tone = .ok

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone.color)
                    .frame(width: 20, height: 20)
                    .background(tone.fill, in: .rect(cornerRadius: 6))
                Text(title)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(Token.Typography.metric)
                .foregroundStyle(Token.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let delta {
                Text(delta)
                    .font(Token.Typography.caption)
                    .foregroundStyle(deltaTone.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Token.Space.m)
        .background(Token.Surface.card, in: .rect(cornerRadius: Token.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Token.Radius.card)
                .strokeBorder(Token.Border.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title)，\(value)\(delta.map { "，" + $0 } ?? "")"))
    }
}

/// 分节卡片：统一详情页/检查器的分节外观。
struct SectionCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.s) {
            if let title {
                Text(title)
                    .font(Token.Typography.cardTitle)
                    .foregroundStyle(Token.Ink.secondary)
                    .padding(.horizontal, Token.Space.l)
                    .padding(.top, Token.Space.m)
            }
            VStack(alignment: .leading, spacing: Token.Space.s) {
                content
            }
            .padding(.horizontal, Token.Space.l)
            .padding(.vertical, title == nil ? Token.Space.m : Token.Space.s)
            .padding(.bottom, Token.Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Token.Surface.card, in: .rect(cornerRadius: Token.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Token.Radius.card)
                .strokeBorder(Token.Border.hairline, lineWidth: 1)
        }
    }
}

/// 键值行，详情页与检查器统一用它，保证左右对齐一致。
struct KeyValueRow: View {
    let label: String
    let value: String
    var valueTone: Tone?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Token.Space.m) {
            Text(label)
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(Token.Typography.body)
                .foregroundStyle(valueTone?.color ?? Token.Ink.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 警示卡：仪表盘的待办区。
struct AlertCard: View {
    let title: String
    let message: String
    let tone: Tone

    var body: some View {
        HStack(alignment: .top, spacing: Token.Space.s) {
            Image(systemName: tone.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone.color)
            VStack(alignment: .leading, spacing: Token.Space.xxs) {
                Text(title)
                    .font(Token.Typography.cardTitle)
                    .foregroundStyle(Token.Ink.primary)
                Text(message)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Token.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.fill, in: .rect(cornerRadius: Token.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title)。\(message)"))
    }
}

/// 空状态：图标 + 一句说明 + 可选操作。
struct EmptyState: View {
    let title: String
    let message: String
    var systemImage: String = "shippingbox"
    /// 空状态最怕"只有一句话"，给一个能立刻点的下一步
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Token.Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Token.Ink.tertiary)
            Text(title)
                .font(Token.Typography.body.weight(.medium))
                .foregroundStyle(Token.Ink.primary)
            Text(message)
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, Token.Space.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Token.Space.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title)。\(message)"))
    }
}
