import SwiftUI
import SwiftData

/// 机器详情页。内容抽到 ItemDetailContent，方便渲染预览与复用。
struct ItemDetailView: View {
    let item: Item

    @Environment(\.modelContext) private var modelContext
    @State private var showingSale = false
    @State private var showingReceipt = false
    @State private var showingVoidConfirm = false
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "详情") {
                Badge(
                    text: item.status.label,
                    tone: item.status.tone,
                    style: item.status == .inStock ? .outline : .filled
                )
            }

            ScrollView {
                ItemDetailContent(item: item)
                    .padding(Token.Space.m)
            }

            PanelFooter {
                if item.status == .inStock {
                    Button("出库销售") { showingSale = true }
                        .buttonStyle(.borderedProminent)
                }
                if item.order != nil {
                    Button("销售凭证") { showingReceipt = true }
                }
                Spacer(minLength: 0)
                Menu {
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
struct ItemDetailContent: View {
    let item: Item

    var body: some View {
        VStack(spacing: 0) {
            header

            PanelSection(title: "机器") {
                KeyValueRow(label: "芯片", value: item.chip)
                KeyValueRow(label: "内存", value: item.memory)
                KeyValueRow(label: "存储", value: item.storage)
                KeyValueRow(label: "颜色", value: item.color)
                KeyValueRow(label: "成色", value: item.condition.rawValue)
                KeyValueRow(label: "入库时间", value: item.inboundAt.compactStamp)
            }

            PanelSection(title: "成本") {
                KeyValueRow(label: "进价", value: "\(Money.text(item.costAmount)) \(item.currency.rawValue)")
                KeyValueRow(label: "汇率", value: Money.text(item.exchangeRate))
                KeyValueRow(label: "运费", value: item.shippingCNY.cny)
                KeyValueRow(label: "落地成本", value: item.landedCostCNY.cny)
                if let batch = item.batch {
                    KeyValueRow(label: "批次", value: batch.name)
                }
            }

            PanelSection(title: "价格") {
                KeyValueRow(label: "标价", value: item.listPriceCNY.cny)
                if item.status == .sold {
                    KeyValueRow(label: "成交价", value: item.soldPriceCNY.cny)
                    KeyValueRow(
                        label: "毛利",
                        value: item.grossProfitCNY.signedCNY,
                        valueTone: item.grossProfitCNY < 0 ? .danger : .ok
                    )
                } else {
                    let expected = item.listPriceCNY - item.landedCostCNY
                    KeyValueRow(
                        label: "预计毛利",
                        value: expected.signedCNY,
                        valueTone: expected < 0 ? .danger : .ok
                    )
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

    private var header: some View {
        HStack(alignment: .top, spacing: Token.Space.m) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                Text(item.modelName.isEmpty ? "未命名型号" : item.modelName)
                    .font(Token.Typography.pageTitle)
                    .foregroundStyle(Token.Ink.primary)
                    .lineLimit(2)
                Text(item.serialNumber)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(Token.Ink.secondary)
                HStack(spacing: 6) {
                    Badge(
                        text: item.status.label,
                        tone: item.status.tone,
                        style: item.status == .inStock ? .outline : .filled
                    )
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
            Spacer(minLength: 0)
        }
        .padding(Token.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = item.photoData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(.rect(cornerRadius: Token.Radius.control))
        } else {
            RoundedRectangle(cornerRadius: Token.Radius.control)
                .fill(Token.Surface.sidebar)
                .frame(width: 84, height: 84)
                .overlay {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Token.Ink.tertiary)
                }
        }
    }
}