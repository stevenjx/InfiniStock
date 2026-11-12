import SwiftUI
import SwiftData

/// 未选中机器时，详情区不再是一片空白，而是给出"最近入库"作为落脚点。
struct RecentItemsPanel: View {
    let items: [Item]
    let onSelect: (Item) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Token.Space.m) {
                VStack(spacing: Token.Space.xs) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Token.Ink.tertiary)
                    Text("选择一台机器")
                        .font(Token.Typography.body.weight(.medium))
                        .foregroundStyle(Token.Ink.primary)
                    Text("点下面任意一台直接打开，或用中间列表筛选")
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
                .padding(.top, Token.Space.xl)

                SectionCard(title: "最近入库") {
                    if items.isEmpty {
                        Text("还没有在库机器")
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Ink.secondary)
                    }
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            HStack(spacing: Token.Space.s) {
                                CellTitle(title: item.modelName, subtitle: item.serialNumber)
                                Spacer(minLength: Token.Space.s)
                                Text(item.landedCostCNY.cny)
                                    .font(Token.Typography.money)
                                    .foregroundStyle(Token.Ink.primary)
                                Badge(
                                    text: "\(item.ageInDays) 天",
                                    tone: item.isOverdue ? .danger : .neutral,
                                    style: item.isOverdue ? .filled : .outline
                                )
                            }
                            .contentShape(.rect)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Token.Space.l)
        }
        .background(Token.Surface.canvas)
    }
}