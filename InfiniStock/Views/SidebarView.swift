import SwiftUI
import SwiftData

/// 侧栏。刻意不用 List(selection:)，而是每行一个显式按钮自己管选中态：
/// 系统 List 的 selection 在 Optional 标签 + 分节结构下会静默失效，
/// 表现就是"点了没反应"，这类问题不能靠猜，直接绕开。
struct SidebarView: View {
    @Binding var selection: SidebarSection
    var onSettings: () -> Void = {}

    @Query private var items: [Item]
    @Query private var batches: [Batch]
    @Query private var orders: [Order]

    /// 侧栏只报条数，不报明细——明细在待办页里
    private var todoCount: Int {
        TodoCenter.build(items: items, batches: batches, orders: orders,
                         currentRate: ShopSettings.load().defaultExchangeRate).count
    }

    private var inStockCount: Int {
        items.reduce(0) { $0 + ($1.status == .inStock ? 1 : 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    group("日常") {
                        row(.todos, badge: todoCount > 0 ? todoCount : nil)
                        row(.stock(nil), badge: inStockCount > 0 ? inStockCount : nil)
                    }
                    group("交易") {
                        row(.orders)
                        row(.batches)
                        row(.customers)
                    }
                    group("分析") {
                        row(.report)
                    }
                }
                .padding(.horizontal, Token.Space.s)
                .padding(.bottom, Token.Space.m)
            }

            footer
        }
        // 侧栏用比画布略冷一档的底色，和右侧白卡片形成层次；
        // 纯白侧栏贴在白卡片上时分不出边界。
        .background(Token.Surface.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Token.Border.hairline)
                .frame(width: 1)
        }
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
        .padding(.bottom, Token.Space.m)
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
                    Text("⌘,")
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(Token.Ink.tertiary)
                }
                .padding(.horizontal, Token.Space.s)
                .padding(.vertical, 5)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Token.Space.s)
            .padding(.top, Token.Space.s)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(backupStatus.tone)
                        .frame(width: 5, height: 5)
                    Text(backupStatus.text)
                        .font(.system(size: 10))
                        .foregroundStyle(Token.Ink.tertiary)
                    Spacer(minLength: 0)
                }
                Text(shopName.isEmpty ? "未设置店名" : shopName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Token.Space.m)
            .padding(.top, 6)
            .padding(.bottom, Token.Space.m)
        }
    }

    private var shopName: String {
        ShopSettings.load().shopName.trimmingCharacters(in: .whitespaces)
    }

    private var backupStatus: (text: String, tone: Color) {
        if !ShopSettings.load().autoBackupEnabled {
            return ("自动备份已关闭", Token.Status.warn)
        }
        if BackupService.backupFolder() == nil {
            return ("仅存本机 · 未配备份", Token.Status.warn)
        }
        return ("每日自动备份已开启", Token.Status.ok)
    }

    /// 库存的四个状态共用一个入口：选中态按"是不是库存分区"判断，
    /// 否则从胶囊切到「已售」时侧栏会整列失去高亮。
    private func isCurrent(_ section: SidebarSection) -> Bool {
        if section.isStock { return selection.isStock }
        return selection == section
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Token.Ink.tertiary)
            .padding(.horizontal, Token.Space.s)
            .padding(.top, Token.Space.m)
            .padding(.bottom, 4)
        VStack(spacing: 2) {
            content()
        }
    }

    private func row(_ section: SidebarSection, badge: Int? = nil) -> some View {
        SidebarRow(
            title: section.label,
            icon: section.icon,
            isSelected: isCurrent(section),
            badge: badge
        ) {
            selection = section
        }
    }
}

/// 单行。悬停给一层极浅底色，否则未选中行在浅色侧栏里没有边界感。
private struct SidebarRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var badge: Int?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 17)
                    .foregroundStyle(isSelected ? Token.Ink.onAccent : Token.Ink.secondary)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Token.Ink.onAccent : Token.Ink.primary)
                Spacer(minLength: 0)
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Token.Ink.onAccent : Token.Ink.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            isSelected ? Token.Ink.onAccent.opacity(0.18) : Token.Surface.header,
                            in: .capsule
                        )
                        .accessibilityLabel(Text("\(badge) 项"))
                }
            }
            .padding(.horizontal, Token.Space.s)
            .frame(height: 32)
            .contentShape(.rect)
            .background(
                isSelected
                    ? Token.Accent.brand
                    : (hovering ? Token.Surface.header : Color.clear),
                in: .rect(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
