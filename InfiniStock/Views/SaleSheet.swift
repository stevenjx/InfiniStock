import SwiftUI
import SwiftData

/// 出库单。逐台改价 + 折扣 + 抹零 + 收款方式。
///
/// 不用系统 Form：出库是最高频的操作，而 Form 会把毛利压到最底部，
/// 改一次价就要来回滚一屏。这里改成「上方机器与客户，下方常驻结算条」，
/// 成交价、毛利、毛利率始终同屏。
struct SaleSheet: View {
    let items: [Item]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Order.createdAt, order: .reverse) private var orders: [Order]

    @State private var priceTexts: [String: String]
    @State private var customerName = ""
    @State private var customerContact = ""
    @State private var discountText = ""
    @State private var roundingText = ""
    /// 实收金额。留空表示当场全额收讫，填了就按差额记欠款。
    @State private var paidText = ""
    @State private var paymentMethod: PaymentMethod = ShopSettings.load().paymentMethod
    @State private var errorMessage: String?
    /// 出库成功后不立刻关窗：单号、实收、毛利要让人看见一眼，
    /// 否则点完按钮窗口消失，等于没有回执。
    @State private var completed: Order?

    init(items: [Item]) {
        self.items = items
        var initial: [String: String] = [:]
        for item in items {
            initial[item.serialNumber] = item.listPrice > 0 ? Money.text(item.listPrice) : ""
        }
        _priceTexts = State(initialValue: initial)
    }

    // MARK: - 口径

    private var subtotal: Decimal {
        items.reduce(Decimal(0)) { $0 + (priceTexts[$1.serialNumber].flatMap(Money.parse) ?? 0) }
    }

    private var discount: Decimal { Money.parse(discountText) ?? 0 }
    private var rounding: Decimal { Money.parse(roundingText) ?? 0 }
    private var payable: Decimal { subtotal - discount - rounding }

    private var landedTotal: Decimal {
        items.reduce(Decimal(0)) { $0 + $1.landedCost }
    }

    private var profit: Decimal { payable - landedTotal }

    /// 实收：留空即全额，填了就夹在 0…应收 之间（多给的是找零）
    private var received: Decimal {
        guard let parsed = Money.parse(paidText) else { return payable }
        return min(max(parsed, 0), payable)
    }

    private var outstanding: Decimal {
        let value = payable - received
        return value > 0 ? value : 0
    }

    /// 毛利率以实收为分母，和仪表盘、单据上的口径一致
    private var marginRate: Decimal? {
        guard payable > 0 else { return nil }
        return (profit / payable * 100).rounded(1)
    }

    private var hasInvalidPrice: Bool {
        items.contains { priceTexts[$0.serialNumber].flatMap(Money.parse) == nil }
    }

    /// 0 元成交会让统计里"台数 +1、销售额 +0"，口径直接歪掉。
    /// 真要赠送就把折扣填到小计，那是有意为之且金额可追溯。
    private var hasNonPositivePrice: Bool {
        items.contains { (priceTexts[$0.serialNumber].flatMap(Money.parse) ?? 0) <= 0 }
    }

    private var discountInvalid: Bool {
        discount < 0 || rounding < 0 || discount + rounding > subtotal
    }

    /// 同名老客户：开单时直接告诉他这人买过几次，比翻单据快
    private var matchedCustomer: CustomerSummary? {
        let name = customerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return CustomerSummary.build(from: orders).first { $0.name == name }
    }

    private var recentCustomers: [CustomerSummary] {
        Array(CustomerSummary.build(from: orders).prefix(6))
    }

    // MARK: - 界面

    var body: some View {
        VStack(spacing: 0) {
            if let completed {
                completionView(completed)
            } else {
                entryView
            }
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 560, idealHeight: 680)
        .background(Token.Surface.canvas)
        // 出库是从详情栏里弹出来的，会继承「收起详情」环境值；
        // 标题条在这里不该出现 ✕，否则点了收起的是背后的详情栏而不是这张单。
        .environment(\.dismissDetail, nil)
        .alert("出库失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var entryView: some View {
        VStack(spacing: 0) {
            PanelHeader(
                title: items.count == 1 ? "出库销售" : "批量出库",
                subtitle: items.count == 1 ? items[0].serialNumber : "\(items.count) 台"
            ) {
                Text("应收 \(payable.mmk)")
                    .font(Token.Typography.money.weight(.semibold))
                    .foregroundStyle(Token.Ink.primary)
            }

            ScrollView {
                VStack(spacing: Token.Space.m) {
                    if profit < 0 && !hasInvalidPrice {
                        AlertCard(
                            title: "这笔会亏 \((-profit).mmk)",
                            message: "实收低于这 \(items.count) 台的总进价 \(landedTotal.mmk)，确认前请复核成交价与折扣。",
                            tone: .danger
                        )
                    }

                    machinesCard
                    customerCard
                    paymentCard
                }
                .padding(Token.Space.l)
            }

            footer
        }
    }

    /// 出库回执。卖出去不可逆，至少要让单号和实收在眼前停一下。
    private func completionView(_ order: Order) -> some View {
        VStack(spacing: 0) {
            PanelHeader(title: "已出库", subtitle: order.number)

            VStack(spacing: Token.Space.m) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Token.Status.ok)
                    .padding(.top, Token.Space.xl)

                Text(order.number)
                    .font(Token.Typography.pageTitle)
                    .monospaced()

                VStack(spacing: Token.Space.xs) {
                    KeyValueRow(label: "应收", value: order.total.mmk)
                    KeyValueRow(label: "实收", value: order.collected.mmk)
                    if order.outstanding > 0 {
                        KeyValueRow(label: "未收", value: order.outstanding.mmk, valueTone: .warn)
                    }
                    KeyValueRow(label: "毛利", value: order.profit.signedMMK,
                                valueTone: order.profit < 0 ? .danger : .ok)
                    KeyValueRow(label: "台数", value: "\(order.itemList.count) 台")
                    if !order.customerName.isEmpty {
                        KeyValueRow(label: "客户", value: order.customerName)
                    }
                }
                .padding(Token.Space.l)
                .background(Token.Surface.card, in: .rect(cornerRadius: Token.Radius.card))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Token.Space.xl)

            PanelFooter {
                Text("凭证可在「销售记录」里重出，退货也在那里办理")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
                Spacer(minLength: Token.Space.s)
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var machinesCard: some View {
        SectionCard(title: items.count == 1 ? "机器" : "待出库 \(items.count) 台") {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Hairline() }
                    machineRow(item)
                        .padding(.vertical, Token.Space.s)
                }
            }
        }
    }

    private func machineRow(_ item: Item) -> some View {
        let price = priceTexts[item.serialNumber].flatMap(Money.parse)
        let lineProfit = (price ?? 0) - item.landedCost

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Token.Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.modelName)
                        .font(Token.Typography.cellPrimary)
                        .foregroundStyle(Token.Ink.primary)
                    Text(item.serialNumber)
                        .font(Token.Typography.caption)
                        .monospaced()
                        .foregroundStyle(Token.Ink.tertiary)
                }
                Spacer(minLength: Token.Space.s)
                Text("成本 \(item.landedCost.mmk)")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
            }

            HStack(spacing: Token.Space.s) {
                Text("成交价")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)

                TextField("输入成交价", text: binding(for: item))
                    .textFieldStyle(.plain)
                    .font(Token.Typography.money)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Token.Surface.field, in: .rect(cornerRadius: Token.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: Token.Radius.control)
                            .strokeBorder(Token.Border.hairline, lineWidth: 1)
                    }
                    .frame(width: 132)
                    .decimalKeyboard()

                Button("按标价") {
                    priceTexts[item.serialNumber] = Money.text(item.listPrice)
                }
                .buttonStyle(.link)
                .font(Token.Typography.caption)
                .fixedSize()
                .disabled(item.listPrice <= 0)
                .help(item.listPrice > 0 ? "填入标价" : "这台还没定价，先去改标价")

                Spacer(minLength: Token.Space.s)

                Text(price == nil ? "—" : lineProfit.signedMMK)
                    .font(Token.Typography.money)
                    .foregroundStyle(lineProfit < 0 ? Token.Status.danger : Token.Ink.secondary)
                    .help("这台的单台毛利")
            }
        }
    }

    private var customerCard: some View {
        SectionCard(title: "客户") {
            VStack(spacing: Token.Space.s) {
                HStack(spacing: Token.Space.s) {
                    field("客户名称", text: $customerName)
                    if !recentCustomers.isEmpty {
                        Menu {
                            ForEach(recentCustomers) { customer in
                                Button(customer.contact.isEmpty
                                       ? customer.name
                                       : "\(customer.name) · \(customer.contact)") {
                                    customerName = customer.name
                                    customerContact = customer.contact
                                }
                            }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("从最近客户里选")
                    }
                }
                field("联系方式（可选）", text: $customerContact)

                if let matched = matchedCustomer {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 10))
                        Text("老客户 · 已购 \(matched.orderCount) 次 · 累计 \(matched.revenue.mmk)")
                            .font(Token.Typography.caption)
                    }
                    .foregroundStyle(Token.Accent.brand)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var paymentCard: some View {
        SectionCard(title: "收款") {
            VStack(spacing: Token.Space.s) {
                HStack(spacing: Token.Space.m) {
                    amountField("折扣", text: $discountText)
                    amountField("抹零", text: $roundingText)
                }

                HStack(spacing: Token.Space.s) {
                    Text("收款方式")
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                    FilterPillGroup(
                        options: PaymentMethod.allCases.map { PillOption(value: $0, title: $0.rawValue) },
                        selection: paymentMethod
                    ) { paymentMethod = $0 }
                    Spacer(minLength: 0)
                }

                // 实收留空就是全额，只有赊账才需要动手填
                HStack(spacing: Token.Space.s) {
                    Text("实收")
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                    TextField("全额", text: $paidText)
                        .textFieldStyle(.plain)
                        .font(Token.Typography.money)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(Token.Surface.field, in: .rect(cornerRadius: Token.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: Token.Radius.control)
                                .strokeBorder(Token.Border.hairline, lineWidth: 1)
                        }
                        .frame(width: 132)
                        .decimalKeyboard()
                    // 空着就代表全额，此时再摆一个「全额」按钮只是重复一遍占位符，
                    // 还让人以为要按一下才算数。填了金额才出现复位入口。
                    if !paidText.isEmpty {
                        Button("全额") { paidText = "" }
                            .buttonStyle(.link)
                            .font(Token.Typography.caption)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                    if outstanding > 0 {
                        Text("欠 \(outstanding.mmk)")
                            .font(Token.Typography.caption.weight(.medium))
                            .foregroundStyle(Token.Status.warn)
                    } else {
                        Text("已收讫")
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Status.ok)
                    }
                }
            }
        }
    }

    private var footer: some View {
        PanelFooter {
            HStack(spacing: 6) {
                Text("小计 \(subtotal.mmk)")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
                Text("·")
                    .foregroundStyle(Token.Ink.tertiary)
                Text("应收 \(payable.mmk)")
                    .font(Token.Typography.caption.weight(.semibold))
                    .foregroundStyle(Token.Ink.primary)
                Text("·")
                    .foregroundStyle(Token.Ink.tertiary)
                // 价格没填全时不要报毛利：把空值当 0 会算出一个假的亏损
                if hasInvalidPrice {
                    Text("还有成交价没填")
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Status.warn)
                } else {
                    Text("毛利 \(profit.signedMMK)")
                        .font(Token.Typography.caption)
                        .foregroundStyle(profit < 0 ? Token.Status.danger : Token.Status.ok)
                    if let marginRate {
                        Text("(\(Money.text(marginRate))%)")
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Ink.tertiary)
                    }
                }
            }
            .lineLimit(1)

            Spacer(minLength: Token.Space.s)

            Button("取消") { dismiss() }
                .controlSize(.small)

            Button("确认出库") { confirm() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(hasInvalidPrice || hasNonPositivePrice || discountInvalid)
                // 刻意不绑 .defaultAction：卖出不可逆，回车误触就是一笔假账。
                // ⌘↩ 需要两只手，不会手滑。
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(Token.Typography.body)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Token.Surface.field, in: .rect(cornerRadius: Token.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Token.Radius.control)
                    .strokeBorder(Token.Border.hairline, lineWidth: 1)
            }
    }

    private func amountField(_ prompt: String, text: Binding<String>) -> some View {
        HStack(spacing: Token.Space.s) {
            Text(prompt)
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.secondary)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(Token.Typography.money)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Token.Surface.field, in: .rect(cornerRadius: Token.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Token.Radius.control)
                        .strokeBorder(Token.Border.hairline, lineWidth: 1)
                }
                .frame(maxWidth: .infinity)
                .decimalKeyboard()
        }
    }

    private func binding(for item: Item) -> Binding<String> {
        Binding(
            get: { priceTexts[item.serialNumber] ?? "" },
            set: { priceTexts[item.serialNumber] = $0 }
        )
    }

    private func confirm() {
        guard !hasInvalidPrice else {
            errorMessage = "有成交价格式不正确"
            return
        }
        guard !hasNonPositivePrice else {
            errorMessage = "成交价必须大于 0。要赠送请把折扣填到小计，这样金额有据可查。"
            return
        }
        guard !discountInvalid else {
            errorMessage = "折扣加抹零不能超过商品小计"
            return
        }

        let lines = items.compactMap { item -> InventoryService.SaleLine? in
            guard let price = priceTexts[item.serialNumber].flatMap(Money.parse) else { return nil }
            return InventoryService.SaleLine(item: item, price: price)
        }

        do {
            let order = try InventoryService.sell(
                lines: lines,
                customerName: customerName,
                customerContact: customerContact,
                discount: discount,
                rounding: rounding,
                paymentMethod: paymentMethod,
                paid: Money.parse(paidText) == nil ? nil : received,
                in: context
            )
            completed = order
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
