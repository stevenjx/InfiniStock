import SwiftUI

/// 侧栏。刻意不用 List(selection:)，而是每行一个显式按钮自己管选中态：
/// 系统 List 的 selection 在 Optional 标签 + 分节结构下会静默失效，
/// 表现就是"点了没反应"，这类问题不能靠猜，直接绕开。
struct SidebarView: View {
    @Binding var selection: SidebarSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Token.Space.l) {
                group("库存") {
                    row(.stock(.inStock))
                    row(.stock(.sold))
                    row(.stock(.locked))
                    row(.stock(nil))
                }
                group("交易") {
                    row(.orders)
                }
                group("进货") {
                    row(.batches)
                }
                group("客户") {
                    row(.customers)
                }
            }
            .padding(.horizontal, Token.Space.s)
            .padding(.vertical, Token.Space.m)
        }
        .background(Token.Surface.sidebar)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Token.Ink.tertiary)
                .padding(.horizontal, Token.Space.s)
                .padding(.bottom, 2)
            content()
        }
    }

    private func row(_ section: SidebarSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 7) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Token.Accent.brand : Token.Ink.secondary)
                Text(section.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Token.Ink.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Token.Space.s)
            .padding(.vertical, 5)
            .contentShape(.rect)
            .background(
                isSelected ? Token.Accent.fill : Color.clear,
                in: .rect(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}