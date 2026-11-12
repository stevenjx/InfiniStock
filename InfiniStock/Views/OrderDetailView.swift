import SwiftUI
import SwiftData

/// 单据详情：看明细、重出凭证、逐台退货。
struct OrderDetailView: View {
    let order: Order

    @Environment(\.modelContext) private var modelContext
    @State private var showingReceipt = false
    @State private var showingReturn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "订单详情", subtitle: order.number) {
                Badge(
                    text: order.statusLabel,
                    tone: order.tone,
                    style: order.isVoided ? .filled : .outline
                )
            }

            ScrollView {
                VStack(spacing: 0) {
                    PanelSection(title: "单据") {
                        KeyValueRow(label: "单号", value: order.number)
                        KeyValueRow(label: "日期", value: order.createdAt.compactStamp)
                        KeyValueRow(label: "状态", value: order.statusLabel)
                        KeyValueRow(label: "收款方式", value: order.paymentMethod.rawValue)
                        KeyValueRow(label: "客户", value: order.customerName.isEmpty ? "—" : order.customerName)
                        KeyValueRow(label: "联系方式", value: order.customerContact.isEmpty ? "—" : order.customerContact)
                    }

                    PanelSection(title: "金额") {
                        KeyValueRow(label: "商品小计", value: order.subtotal.mmk)
                        if order.discount > 0 {
                            KeyValueRow(label: "折扣 + 抹零", value: "−" + (order.discount + order.rounding).mmk)
                        }
                        KeyValueRow(label: "应收合计", value: order.total.mmk)
                        KeyValueRow(
                            label: "毛利",
                            value: order.profit.signedMMK,
                            valueTone: order.profit < 0 ? .danger : .ok
                        )
                        if order.hasReturns {
                            KeyValueRow(
                                label: "已退货",
                                value: "\(order.returnedCount) 台 · 退回 \(order.returnedAmount.mmk)",
                                valueTone: .warn
                            )
                        }
                    }

                    PanelSection(title: "机器", trailing: "\(order.itemList.count) 台") {
                        if order.itemList.isEmpty {
                            Text("此单机器已全部退回")
                                .font(Token.Typography.caption)
                                .foregroundStyle(Token.Ink.secondary)
                        }
                        ForEach(order.itemList.sorted { $0.serialNumber < $1.serialNumber }) { item in
                            HStack(spacing: Token.Space.s) {
                                CellTitle(title: item.modelName, subtitle: item.serialNumber)
                                Spacer()
                                Text(item.soldPrice.mmk)
                                    .font(Token.Typography.money)
                                    .foregroundStyle(Token.Ink.primary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            PanelFooter {
                Button("凭证") { showingReceipt = true }
                    .buttonStyle(.borderedProminent)
                if !order.isVoided, !order.itemList.isEmpty {
                    Button("退货…") { showingReturn = true }
                }
                Spacer(minLength: 0)
            }
        }
        .background(Token.Surface.card)
        .navigationTitle("")
        .sheet(isPresented: $showingReceipt) {
            ReceiptSheet(order: order)
        }
        .sheet(isPresented: $showingReturn) {
            ReturnSheet(order: order)
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
}

/// 逐台勾选退货。勾选时实时显示退回金额与重算后的应收，避免事后才发现金额不对。
struct ReturnSheet: View {
    let order: Order

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<PersistentIdentifier> = []
    @State private var errorMessage: String?

    private var selectedItems: [Item] {
        order.itemList.filter { selected.contains($0.id) }
    }

    private var refund: Decimal {
        selectedItems.reduce(Decimal(0)) { $0 + $1.soldPrice }
    }

    /// 预览重算结果，与 OrderService 使用同一套规则
    private var previewTotal: Decimal {
        let remaining = order.itemList.filter { !selected.contains($0.id) }
        guard !remaining.isEmpty else { return 0 }
        let priceBefore = order.itemList.reduce(Decimal(0)) { $0 + $1.soldPrice }
        let subtotal = remaining.reduce(Decimal(0)) { $0 + $1.soldPrice }
        guard priceBefore > 0 else { return 0 }
        let ratio = (subtotal / priceBefore).rounded(6)
        let discount = (order.discount * ratio).rounded(2)
        let rounding = (order.rounding * ratio).rounded(2)
        return (subtotal - discount - rounding).rounded(2)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("选择要退回的机器") {
                    ForEach(order.itemList.sorted { $0.serialNumber < $1.serialNumber }) { item in
                        Toggle(isOn: binding(for: item)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.modelName)
                                    Text(item.serialNumber)
                                        .font(.caption)
                                        .monospaced()
                                        .foregroundStyle(Token.Ink.secondary)
                                }
                                Spacer()
                                Text(item.soldPrice.mmk)
                                    .monospacedDigit()
                                    .foregroundStyle(Token.Ink.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }

                Section("影响") {
                    LabeledContent("退回金额", value: refund.mmk)
                    LabeledContent("剩余应收", value: previewTotal.mmk)
                    if selected.count == order.itemList.count {
                        Text("全部退回后单据将标记为已全退，库存全部恢复。")
                            .font(.caption)
                            .foregroundStyle(Token.Status.warn)
                    } else if !selected.isEmpty {
                        Text("折扣与抹零按剩余货值比例保留，退货部分连同折扣一起退回。")
                            .font(.caption)
                            .foregroundStyle(Token.Ink.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("退货")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认退货") { confirm() }
                        .disabled(selected.isEmpty)
                }
            }
            .alert("退货失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    private func binding(for item: Item) -> Binding<Bool> {
        Binding(
            get: { selected.contains(item.id) },
            set: { isOn in
                if isOn { selected.insert(item.id) } else { selected.remove(item.id) }
            }
        )
    }

    private func confirm() {
        do {
            try OrderService.returnItems(selectedItems, from: order, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}