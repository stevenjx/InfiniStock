import SwiftUI
import SwiftData

/// 机器详情页。内容抽到 ItemDetailContent，方便渲染预览与复用。
struct ItemDetailView: View {
    let item: Item

    @Environment(\.modelContext) private var modelContext
    @State private var showingSale = false
    @State private var showingReceipt = false
    @State private var showingEdit = false
    @State private var showingVoidConfirm = false
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "详情", subtitle: item.status.label) {
                Badge(
                    text: item.status.label,
                    tone: item.status.tone,
                    style: item.status == .inStock ? .outline : .filled
                )
            }

            ScrollView {
                ItemDetailContent(item: item)
            }

            PanelFooter {
                Button("改标价") { showingEdit = true }
                    .buttonStyle(.borderedProminent)
                    .help("改标价与机况")

                if item.status == .inStock {
                    Button("出库销售") { showingSale = true }
                        .help("出库销售（⌘⇧S）")
                }
                if item.order != nil {
                    Button("销售凭证") { showingReceipt = true }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("编辑机况与标价…") { showingEdit = true }
                    Divider()
                    if item.status == .inStock {
                        Button("删除这台（误录入）…", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                    }
                    if item.order != nil {
                        Button("撤销单据", role: .destructive) { showingVoidConfirm = true }
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .background(Token.Surface.card)
        .navigationTitle("")
        .sheet(isPresented: $showingSale) {
            SaleSheet(items: [item])
        }
        .sheet(isPresented: $showingEdit) {
            ItemEditSheet(item: item)
        }
        .sheet(isPresented: $showingReceipt) {
            if let order = item.order {
                ReceiptSheet(order: order)
            }
        }
        .confirmationDialog("删除这台机器？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task { await performDelete() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅用于清理误录入。删除后不可恢复，且需要系统身份验证。已售出的机器请先退货或作废单据。")
        }
        .confirmationDialog("撤销这张单据？", isPresented: $showingVoidConfirm, titleVisibility: .visible) {
            Button("撤销并退回库存", role: .destructive) {
                Task { await performVoid() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("机器会回到在库状态，凭证作废。该操作需要系统身份验证。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func performDelete() async {
        let passed = await BiometricGate.authenticate(reason: "删除机器 \(item.serialNumber)")
        guard passed else {
            errorMessage = "身份验证未通过，删除已取消"
            return
        }
        do {
            try InventoryService.delete(item, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performVoid() async {
        guard let order = item.order else { return }
        let passed = await BiometricGate.authenticate(reason: "撤销销售单 \(order.number)")
        guard passed else {
            errorMessage = "身份验证未通过，撤销已取消"
            return
        }
        do {
            try OrderService.void(order, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 详情页内容（不含滚动与工具栏），可直接渲染成图验收。
/// 结构对齐参考图：整幅照片 → 大号型号名 → 分区字段，一眼先看到"这是什么机器"。
struct ItemDetailContent: View {
    let item: Item

    var body: some View {
        VStack(spacing: 0) {
            photo
            identity

            PanelSection(title: "机器") {
                KeyValueRow(label: "芯片", value: item.chip)
                KeyValueRow(label: "内存", value: item.memory)
                KeyValueRow(label: "存储", value: item.storage)
                KeyValueRow(label: "颜色", value: item.color)
                KeyValueRow(label: "成色", value: item.condition.rawValue)
                KeyValueRow(
                    label: "电池健康",
                    value: item.batteryHealth > 0 ? item.batteryHealthText : "未检测",
                    valueTone: item.isBatteryWeak ? .warn : nil
                )
                KeyValueRow(label: "循环次数", value: item.batteryCycles > 0 ? item.batteryCyclesText : "未检测")
                KeyValueRow(label: "入库时间", value: item.inboundAt.compactStamp)
            }

            PanelSection(title: "成本") {
                KeyValueRow(label: "进价", value: item.costCNY.cny)
                KeyValueRow(label: "汇率", value: "1 元 = \(Money.text(item.exchangeRate)) 缅币")
                KeyValueRow(label: "进价折缅币", value: item.costMMK.mmk)
                KeyValueRow(label: "运费", value: item.shipping.mmk)
                KeyValueRow(label: "总进价", value: item.landedCost.mmk)
                if let batch = item.batch {
                    KeyValueRow(label: "批次", value: batch.name)
                }
                // 汇率风险落到具体数字：标价换回人民币刚好回本的那个汇率，
                // 和今天的汇率一比，就知道这台机器现在结汇是赚是亏。
                if let breakEven = item.breakEvenRate {
                    KeyValueRow(
                        label: "回本汇率",
                        value: Money.text(breakEven),
                        valueTone: breakEvenTone(breakEven)
                    )
                    let current = ShopSettings.load().defaultExchangeRate
                    let loss = item.currencyLoss(at: current)
                    if loss > 0 {
                        KeyValueRow(
                            label: "结汇亏损",
                            value: "−\(loss.cny)",
                            valueTone: .danger
                        )
                    }
                }
            }

            PanelSection(title: "价格") {
                KeyValueRow(label: "标价", value: item.listPrice.mmk)
                if item.status == .sold {
                    KeyValueRow(label: "成交价", value: item.soldPrice.mmk)
                    KeyValueRow(
                        label: "毛利",
                        value: item.grossProfit.signedMMK,
                        valueTone: item.grossProfit < 0 ? .danger : .ok
                    )
                } else {
                    let expected = item.listPrice - item.landedCost
                    KeyValueRow(
                        label: "预计毛利",
                        value: expected.signedMMK,
                        valueTone: expected < 0 ? .danger : .ok
                    )
                    KeyValueRow(label: "毛利率", value: marginText(expected, base: item.listPrice))
                }
            }

            if let order = item.order {
                PanelSection(title: "单据") {
                    KeyValueRow(label: "单号", value: order.number)
                    KeyValueRow(label: "客户", value: order.customerName)
                    KeyValueRow(label: "联系方式", value: order.customerContact)
                    KeyValueRow(label: "收款方式", value: order.paymentMethod.rawValue)
                    KeyValueRow(
                        label: "出库时间",
                        value: (item.soldAt ?? order.createdAt).compactStamp
                    )
                    if order.hasReturns {
                        KeyValueRow(label: "售后", value: "本单已退 \(order.returnedCount) 台", valueTone: .warn)
                    }
                }
            }

            PanelSection(title: "实物照片") {
                PhotoField(item: item)
            }
        }
    }

    /// 整幅照片位。用 Rectangle 打底，保证无论有没有照片都铺满面板宽度。
    private var photo: some View {
        Rectangle()
            .fill(Token.Surface.field)
            .frame(height: 148)
            .overlay {
                if let data = item.photoData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundStyle(Token.Ink.tertiary)
                }
            }
            .clipped()
            .overlay(alignment: .bottom) { Hairline() }
            .accessibilityLabel(Text(item.photoData == nil ? "暂无实物照片" : "实物照片"))
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.modelName.isEmpty ? "未命名型号" : item.modelName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Token.Ink.primary)
                .lineLimit(2)
                .textSelection(.enabled)

            Text(item.serialNumber)
                .font(.system(size: 12).monospaced())
                .foregroundStyle(Token.Ink.secondary)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Badge(
                    text: item.status.label,
                    tone: item.status.tone,
                    style: item.status == .inStock ? .outline : .filled
                )
                if item.isBatteryWeak {
                    Badge(text: "电池偏弱", tone: .warn, style: .filled)
                }
                if item.isOverdue {
                    Badge(text: "库龄 \(item.ageInDays) 天", tone: .danger, style: .filled)
                }
            }

            if !item.specSummary.isEmpty {
                Text(item.specSummary)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
            }
        }
        .padding(.horizontal, Token.Space.m)
        .padding(.vertical, Token.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func marginText(_ profit: Decimal, base: Decimal) -> String {
        guard base > 0 else { return "—" }
        return "\((profit / base * 100).rounded(1))%"
    }

    /// 当前汇率高于回本汇率 = 按今天结汇是亏的
    private func breakEvenTone(_ breakEven: Decimal) -> Tone? {
        let current = ShopSettings.load().defaultExchangeRate
        guard current > 0 else { return nil }
        return current > breakEven ? .danger : .ok
    }
}
