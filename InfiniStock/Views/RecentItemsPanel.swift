import SwiftUI
import SwiftData

/// 未选中机器时，右栏保持与详情一致的面板结构：标题条 + 最近入库清单。
struct RecentItemsPanel: View {
    let items: [Item]
    let onSelect: (Item) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "详情", subtitle: "未选择机器")

            ScrollView {
                VStack(alignment: .leading, spacing: Token.Space.s) {
                    HStack {
                        Text("最近入库")
                            .font(Token.Typography.cardTitle)
                            .foregroundStyle(Token.Ink.primary)
                        Spacer()
                        Text("\(items.count) 台")
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Ink.tertiary)
                    }
                    .padding(.bottom, 2)

                    VStack(spacing: 0) {
                        if items.isEmpty {
                            Text("还没有在库机器")
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Token.Space.s)
                        }
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Hairline() }
                            Button {
                                onSelect(item)
                            } label: {
                                RecentRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Token.Surface.card)
                    .clipShape(.rect(cornerRadius: Token.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: Token.Radius.control)
                            .strokeBorder(Token.Border.hairline, lineWidth: 1)
                    }

                    Text("点上面任意一台直接打开，或用左侧列表筛选")
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.tertiary)
                        .padding(.top, Token.Space.xs)
                }
                .padding(Token.Space.m)
            }
        }
        .background(Token.Surface.card)
    }
}

private struct RecentRow: View {
    let item: Item
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Token.Space.s) {
            CellTitle(title: item.modelName, subtitle: item.serialNumber)
            Spacer(minLength: Token.Space.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.landedCost.mmk)
                    .font(Token.Typography.money)
                    .foregroundStyle(Token.Ink.primary)
                Badge(
                    text: "\(item.ageInDays) 天",
                    tone: item.isOverdue ? .danger : .neutral,
                    style: item.isOverdue ? .filled : .outline
                )
            }
        }
        .padding(.horizontal, Token.Space.s)
        .padding(.vertical, 6)
        .background(hovering ? Token.Surface.header : Color.clear)
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}
