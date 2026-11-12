import SwiftUI

/// 侧栏。刻意不用 List(selection:)，而是每行一个显式按钮自己管选中态：
/// 系统 List 的 selection 在 Optional 标签 + 分节结构下会静默失效，
/// 表现就是"点了没反应"，这类问题不能靠猜，直接绕开。
struct SidebarView: View {
    @Binding var selection: SidebarSection
    var onSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    row(.stock(nil))
                    row(.orders)
                    row(.customers)
                    row(.batches)
                }
                .padding(.horizontal, Token.Space.s)
                .padding(.top, Token.Space.s)
                .padding(.bottom, Token.Space.m)
            }

            footer
        }
        .background(Token.Surface.card)
    }

    private var header: some View {
        HStack(spacing: Token.Space.s) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Token.Accent.fill)
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Token.Accent.brand)
                }
            VStack(alignment: .leading, spacing: 0) {
                Text("InfiniStock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Token.Ink.primary)
                Text("库存管理")
                    .font(.system(size: 10))
                    .foregroundStyle(Token.Ink.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Token.Space.m)
        .padding(.top, Token.Space.m)
        .padding(.bottom, Token.Space.s)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            Button(action: onSettings) {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16)
                        .foregroundStyle(Token.Ink.secondary)
                    Text("设置")
                        .font(.system(size: 13))
                        .foregroundStyle(Token.Ink.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Token.Space.s)
                .padding(.vertical, 5)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Token.Space.s)
            .padding(.top, Token.Space.s)

            HStack(spacing: 5) {
                Circle()
                    .fill(backupConfigured ? Token.Status.ok : Token.Status.warn)
                    .frame(width: 5, height: 5)
                Text(backupConfigured ? "每日自动备份已开启" : "仅存本机 · 未配备份")
                    .font(.system(size: 10))
                    .foregroundStyle(Token.Ink.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Token.Space.m)
            .padding(.top, 4)
            .padding(.bottom, Token.Space.m)
        }
    }

    private var backupConfigured: Bool {
        BackupService.backupFolder() != nil
    }

    /// 库存的四个状态共用一个入口：选中态按"是不是库存分区"判断，
    /// 否则从胶囊切到「已售」时侧栏会整列失去高亮。
    private func isCurrent(_ section: SidebarSection) -> Bool {
        if section.isStock { return selection.isStock }
        return selection == section
    }

    private func row(_ section: SidebarSection) -> some View {
        let isSelected = isCurrent(section)
        return Button {
            selection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 17)
                    .foregroundStyle(isSelected ? Token.Ink.onAccent : Token.Ink.secondary)
                Text(section.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Token.Ink.onAccent : Token.Ink.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Token.Space.s)
            .frame(height: 32)
            .contentShape(.rect)
            .background(
                isSelected ? Token.Accent.brand : Color.clear,
                in: .rect(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
