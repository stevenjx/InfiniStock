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
            // 副标题放序列号：状态在下面的徽章里，标题条再写一遍「在库」是重复信息
            PanelHeader(title: "详情", subtitle: item.serialNumber)

            ScrollView {
                ItemDetailContent(item: item)
            }
            // 换一台机器就回到顶部。否则在上一台滚到照片位置，选中下一台还停在那里，
            // 开头最该看的型号与价格被滚出了视野。
            .id(item.persistentModelID)

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
///
/// 顺序按「先决策、后档案」：型号与状态 → 价格（含建议价）→ 照片 → 成本 → 机况 → 单据。
/// 原来是六段等权堆叠，8 行机况压在最前面，最该看的毛利要滚一屏才看得到。
struct ItemDetailContent: View {
    let item: Item

    @Environment(\.modelContext) private var modelContext
    /// 只读一次设置：这里每帧都读会每帧解码一次 JSON。
    /// 改设置后重开详情即可看到新的目标毛利。
    @State private var settings = ShopSettings.load()
    /// 改价验证失败时的提示
    @State private var priceError: String?

    private var isSold: Bool { item.status == .sold }

    private var advice: PricingAdvice? {
        guard !isSold, settings.targetMarginPercent > 0 else { return nil }
        return PricingAdvice.make(for: item, targetMarginPercent: settings.targetMarginPercent)
    }

    /// 卖出去的机器，成交价才是事实上的价格
    private var headlineBase: Decimal {
        isSold ? item.soldPrice : item.listPrice
    }

    private var headlineProfit: Decimal {
        isSold ? item.grossProfit : item.listPrice - item.landedCost
    }

    private var currencyLoss: Decimal {
        item.currencyLoss(at: settings.defaultExchangeRate)
    }

    var body: some View {
        VStack(spacing: 0) {
            identity
            priceBand
            photoSection
            costSection
            specSection
            orderSection
            priceHistorySection
        }
        .alert("改价未生效", isPresented: Binding(
            get: { priceError != nil },
            set: { if !$0 { priceError = nil } }
        )) {
            Button("好", role: .cancel) { priceError = nil }
        } message: {
            Text(priceError ?? "")
        }
    }

    // MARK: - 身份

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

            if !identityCaption.isEmpty {
                Text(identityCaption)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
            }
        }
        .padding(.horizontal, Token.Space.m)
        .padding(.vertical, Token.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// 规格与电池压成一行。电池没测过就不写「未检测」——每台都挂个空值等于噪音
    private var identityCaption: String {
        var parts = [item.memory, item.storage, item.color].filter { !$0.isEmpty }
        if item.batteryHealth > 0 { parts.append("电池 \(item.batteryHealth)%") }
        if item.batteryCycles > 0 { parts.append("\(item.batteryCycles) 次循环") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 价格

    /// 价格带：整个面板唯一用品牌浅底的位置，一眼知道该看这里。
    private var priceBand: some View {
        VStack(alignment: .leading, spacing: Token.Space.s) {
            HStack(alignment: .top, spacing: Token.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSold ? "成交价" : "标价")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Token.Ink.secondary)
                    headlineValue
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(isSold ? "毛利" : "预计毛利")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Token.Ink.secondary)
                    // 没定价就没有毛利可言。把「0 − 成本」当亏损报出来，是拿一个不存在的价格算账
                    if !isSold && item.listPrice <= 0 {
                        Text("—")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Token.Ink.tertiary)
                    } else {
                        Text(headlineProfit.signedMMK)
                            .font(.system(size: 15, weight: .semibold).monospacedDigit())
                            .foregroundStyle(headlineProfit < 0 ? Token.Status.danger : Token.Status.ok)
                        Text(marginText(headlineProfit, base: headlineBase))
                            .font(.system(size: 10))
                            .foregroundStyle(Token.Ink.tertiary)
                    }
                }
            }

            if let advice {
                adviceRow(advice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Token.Space.m)
        .background(Token.Accent.fill)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder
    private var headlineValue: some View {
        if headlineBase > 0 {
            Text(headlineBase.mmk)
                .font(Token.Typography.metric)
                .foregroundStyle(Token.Ink.primary)
        } else {
            Text("未标价")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Token.Status.warn)
        }
    }

    /// 建议价并进价格带，不再单独占一段：它本来就是价格的一部分。
    private func adviceRow(_ advice: PricingAdvice) -> some View {
        let applied = item.listPrice > 0 && item.listPrice == advice.suggestedPrice
        let gap = item.listPrice - advice.suggestedPrice
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Token.Accent.brand.opacity(0.22))
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: Token.Space.s) {
                Text("建议价")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Token.Ink.secondary)
                Text(advice.suggestedPrice.mmk)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Token.Accent.brand)
                Spacer(minLength: Token.Space.s)
                if applied {
                    Text("已采用")
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Status.ok)
                } else {
                    Button("采用") { adopt(advice) }
                        .controlSize(.small)
                        .help("把标价改为 \(advice.suggestedPrice.mmk)")
                }
            }

            Text(adviceLine(advice, gap: gap))
                .font(.system(size: 10))
                .foregroundStyle(Token.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func adviceLine(_ advice: PricingAdvice, gap: Decimal) -> String {
        var text = advice.explanation
        if item.listPrice > 0, gap != 0 {
            text += gap > 0
                ? " · 当前比建议高 \(gap.mmk)"
                : " · 当前比建议低 \((-gap).mmk)"
        }
        return text
    }

    /// 采用建议价同样是改价，走同一道验证。
    /// 少了它，这道门只要换个入口就能绕过去。
    private func adopt(_ advice: PricingAdvice) {
        Task { @MainActor in
            guard await BiometricGate.authenticate(reason: "改动标价需要验证身份") else {
                priceError = "未通过身份验证，标价未改动"
                return
            }
            PriceAudit.record(
                item: item,
                oldPrice: item.listPrice,
                newPrice: advice.suggestedPrice,
                source: .advice,
                in: modelContext
            )
            item.listPrice = advice.suggestedPrice
            // 与编辑弹窗同一个落盘路径；标价不参与 Spotlight 索引
            try? modelContext.save()
        }
    }

    // MARK: - 照片

    private var photoSection: some View {
        PanelSection(title: "实物照片") {
            PhotoField(item: item)
        }
    }

    // MARK: - 成本

    private var costSection: some View {
        PanelSection(title: "成本", trailing: item.batch?.name) {
            // 先给结论（总进价），再拆构成；倒过来的话最该看的数字在最后一行
            MetricGrid {
                MetricCell(label: "总进价", value: item.landedCost.mmk)
                MetricCell(label: "运费", value: item.shipping.mmk)
                MetricCell(label: "进价", value: item.costCNY.cny)
                MetricCell(label: "汇率", value: "1 元 = \(Money.text(item.exchangeRate))")
                MetricCell(label: "进价折缅币", value: item.costMMK.mmk)
                // 汇率风险只对还没卖掉的机器有意义：卖出去之后，结汇这件事已经发生
                if !isSold, let breakEven = item.breakEvenRate {
                    MetricCell(
                        label: "回本汇率",
                        value: Money.text(breakEven),
                        tone: breakEvenTone(breakEven)
                    )
                }
                if !isSold, currencyLoss > 0 {
                    MetricCell(label: "结汇亏损", value: "−\(currencyLoss.cny)", tone: .danger)
                }
            }
        }
    }

    // MARK: - 机况

    private var specSection: some View {
        PanelSection(title: "机况") {
            MetricGrid {
                MetricCell(label: "芯片", value: item.chip)
                MetricCell(label: "内存", value: item.memory)
                MetricCell(label: "存储", value: item.storage)
                MetricCell(label: "颜色", value: item.color)
                MetricCell(label: "成色", value: item.condition.rawValue)
                MetricCell(
                    label: "电池健康",
                    value: item.batteryHealth > 0 ? item.batteryHealthText : "未检测",
                    tone: item.isBatteryWeak ? .warn : nil
                )
                MetricCell(label: "循环次数", value: item.batteryCycles > 0 ? item.batteryCyclesText : "未检测")
                MetricCell(label: "入库时间", value: item.inboundAt.compactStamp)
            }
        }
    }

    // MARK: - 单据

    @ViewBuilder
    private var orderSection: some View {
        if let order = item.order {
            PanelSection(title: "单据", trailing: order.number) {
                MetricGrid {
                    MetricCell(label: "客户", value: order.customerName)
                    MetricCell(label: "联系方式", value: order.customerContact)
                    MetricCell(label: "收款方式", value: order.paymentMethod.rawValue)
                    MetricCell(label: "出库时间", value: (item.soldAt ?? order.createdAt).compactStamp)
                    if order.hasReturns {
                        MetricCell(label: "售后", value: "本单已退 \(order.returnedCount) 台", tone: .warn)
                    }
                }
            }
        }
    }

    // MARK: - 改价记录

    /// 只在真的改过价时出现。对账时，「这台为什么从 420 万变成 380 万」
    /// 只能靠这里回答；没有记录的面板只显示当前值，看不出是怎么走到这一步的。
    @ViewBuilder
    private var priceHistorySection: some View {
        let changes = PriceAudit.history(for: item)
        if !changes.isEmpty {
            PanelSection(title: "改价记录", trailing: "\(changes.count) 次") {
                VStack(spacing: 0) {
                    ForEach(Array(changes.prefix(6))) { change in
                        if change.id != changes.prefix(6).first?.id { Hairline() }
                        priceChangeRow(change)
                    }
                    if changes.count > 6 {
                        Hairline()
                        Text("还有 \(changes.count - 6) 次更早的记录")
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Ink.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
            }
        }
    }

    private func priceChangeRow(_ change: PriceChange) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Token.Space.s) {
                Text(change.changedAt.compactStamp)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
                Text(change.source.label)
                    .font(.system(size: 10))
                    .foregroundStyle(Token.Ink.tertiary)
                Spacer(minLength: 0)
                Text(change.delta.signedMMK)
                    .font(Token.Typography.money)
                    .foregroundStyle(change.delta < 0 ? Token.Status.danger : Token.Status.ok)
            }
            HStack(spacing: 4) {
                Text(change.oldPrice.mmk)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                Text(change.newPrice.mmk)
                if let margin = change.marginAfter {
                    Text("· 毛利率 \(Money.text(margin))%")
                        .foregroundStyle(Token.Ink.tertiary)
                }
            }
            .font(Token.Typography.caption)
            .foregroundStyle(Token.Ink.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func marginText(_ profit: Decimal, base: Decimal) -> String {
        guard base > 0 else { return "—" }
        return "毛利率 \((profit / base * 100).rounded(1))%"
    }

    /// 当前汇率高于回本汇率 = 按今天结汇是亏的
    private func breakEvenTone(_ breakEven: Decimal) -> Tone? {
        let current = settings.defaultExchangeRate
        guard current > 0 else { return nil }
        return current > breakEven ? .danger : .ok
    }
}
