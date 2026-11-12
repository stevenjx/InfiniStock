import SwiftUI
import SwiftData

/// 出库单。逐台改价 + 折扣 + 抹零 + 收款方式。
struct SaleSheet: View {
    let items: [Item]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var priceTexts: [PersistentIdentifier: String]
    @State private var customerName = ""
    @State private var customerContact = ""
    @State private var discountText = ""
    @State private var roundingText = ""
    @State private var paymentMethod: PaymentMethod = .cash
    @State private var errorMessage: String?

    init(items: [Item]) {
        self.items = items
        var initial: [PersistentIdentifier: String] = [:]
        for item in items {
            initial[item.id] = item.listPrice > 0 ? Money.text(item.listPrice) : ""
        }
        _priceTexts = State(initialValue: initial)
    }

    private var subtotal: Decimal {
        items.reduce(Decimal(0)) { $0 + (priceTexts[$1.id].flatMap(Money.parse) ?? 0) }
    }

    private var discount: Decimal { Money.parse(discountText) ?? 0 }
    private var rounding: Decimal { Money.parse(roundingText) ?? 0 }
    private var payable: Decimal { subtotal - discount - rounding }

    private var landedTotal: Decimal {
        items.reduce(Decimal(0)) { $0 + $1.landedCost }
    }

    private var profit: Decimal { payable - landedTotal }

    private var hasInvalidPrice: Bool {
        items.contains { priceTexts[$0.id].flatMap(Money.parse) == nil }
    }

    private var discountInvalid: Bool {
        discount < 0 || rounding < 0 || discount + rounding > subtotal
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(items.count == 1 ? "机器" : "待出库 \(items.count) 台") {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.modelName)
                                Text(item.serialNumber)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(Token.Ink.secondary)
                                Spacer()
                                Text("标价 \(item.listPrice.mmk)")
                                    .font(.caption)
                                    .foregroundStyle(Token.Ink.secondary)
                            }
                            HStack {
                                Text("成交价")
                                    .font(.caption)
                                    .foregroundStyle(Token.Ink.secondary)
                                TextField("成交价", text: binding(for: item))
                                    .decimalKeyboard()
                                    .multilineTextAlignment(.trailing)
                                Button("按标价") {
                                    priceTexts[item.id] = Money.text(item.listPrice)
                                }
                                .font(.caption)
                                .buttonStyle(.link)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("客户") {
                    TextField("客户名称", text: $customerName)
                    TextField("联系方式（可选）", text: $customerContact)
                }

                Section("收款") {
                    LabeledContent("商品小计", value: subtotal.mmk)
                    TextField("折扣", text: $discountText)
                        .decimalKeyboard()
                    TextField("抹零", text: $roundingText)
                        .decimalKeyboard()
                    Picker("收款方式", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    HStack {
                        Text("应收合计").fontWeight(.semibold)
                        Spacer()
                        Text(payable.mmk)
                            .fontWeight(.semibold)
                            .foregroundStyle(payable < 0 ? Token.Status.danger : Token.Ink.primary)
                    }
                    HStack {
                        Text("大写").font(.caption).foregroundStyle(Token.Ink.secondary)
                        Spacer()
                        Text(ChineseAmount.uppercase(payable))
                            .font(.caption)
                            .foregroundStyle(Token.Ink.secondary)
                    }
                }

                Section("预估毛利") {
                    LabeledContent("毛利") {
                        Text(profit.mmk)
                            .foregroundStyle(profit < 0 ? Token.Status.danger : Token.Ink.primary)
                    }
                    if profit < 0 {
                        Text("低于总成本，确认前请复核成交价与折扣")
                            .font(.caption)
                            .foregroundStyle(Token.Status.warn)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(items.count == 1 ? "出库销售" : "批量出库")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认出库") { confirm() }
                        .disabled(hasInvalidPrice || discountInvalid)
                }
            }
            .alert("出库失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private func binding(for item: Item) -> Binding<String> {
        Binding(
            get: { priceTexts[item.id] ?? "" },
            set: { priceTexts[item.id] = $0 }
        )
    }

    private func confirm() {
        guard !hasInvalidPrice else {
            errorMessage = "有成交价格式不正确"
            return
        }
        guard !discountInvalid else {
            errorMessage = "折扣加抹零不能超过商品小计"
            return
        }

        let lines = items.compactMap { item -> InventoryService.SaleLine? in
            guard let price = priceTexts[item.id].flatMap(Money.parse) else { return nil }
            return InventoryService.SaleLine(item: item, price: price)
        }

        do {
            try InventoryService.sell(
                lines: lines,
                customerName: customerName,
                customerContact: customerContact,
                discount: discount,
                rounding: rounding,
                paymentMethod: paymentMethod,
                in: context
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}