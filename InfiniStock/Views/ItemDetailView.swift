import SwiftUI
import SwiftData

struct ItemDetailView: View {
    let item: Item
    @Environment(\.modelContext) private var modelContext
    @State private var showingSale = false
    @State private var showingReceipt = false
    @State private var showingVoidConfirm = false
    @State private var showingDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("机器") {
                LabeledContent("型号", value: item.modelName)
                LabeledContent("序列号", value: item.serialNumber)
                LabeledContent("芯片", value: dash(item.chip))
                LabeledContent("内存", value: dash(item.memory))
                LabeledContent("存储", value: dash(item.storage))
                LabeledContent("颜色", value: dash(item.color))
                LabeledContent("成色", value: item.condition.rawValue)
                LabeledContent("入库时间", value: item.inboundAt.formatted(date: .numeric, time: .shortened))
            }

            Section("实物照片") {
                PhotoField(item: item)
            }

            Section("成本") {
                LabeledContent("进价", value: "\(Money.text(item.costAmount)) \(item.currency.rawValue)")
                LabeledContent("汇率", value: Money.text(item.exchangeRate))
                LabeledContent("运费", value: item.shippingCNY.cny)
                LabeledContent("落地成本", value: item.landedCostCNY.cny)
                if let batch = item.batch {
                    LabeledContent("批次", value: batch.name)
                }
            }

            Section("价格") {
                LabeledContent("标价", value: item.listPriceCNY.cny)
                if item.status == .sold {
                    LabeledContent("成交价", value: item.soldPriceCNY.cny)
                    LabeledContent("毛利") {
                        Text(item.grossProfitCNY.cny)
                            .foregroundStyle(item.grossProfitCNY < 0 ? Color.orange : Color.primary)
                    }
                }
            }

            Section("状态") {
                LabeledContent("当前状态", value: item.status.label)
                if let order = item.order {
                    LabeledContent("单号", value: order.number)
                    LabeledContent("客户", value: dash(order.customerName))
                    LabeledContent("联系方式", value: dash(order.customerContact))
                    LabeledContent("出库时间", value: (item.soldAt ?? order.createdAt).formatted(date: .numeric, time: .shortened))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(item.modelName.isEmpty ? "机器详情" : item.modelName)
        .toolbar {
            if item.status == .inStock {
                ToolbarItem(placement: .primaryAction) {
                    Button("出库销售") { showingSale = true }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("删除这台（误录入）…", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                }
            }
            if item.order != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("销售凭证") { showingReceipt = true }
                        Divider()
                        Button("撤销单据", role: .destructive) { showingVoidConfirm = true }
                    } label: {
                        Label("单据", systemImage: "doc.text")
                    }
                }
            }
        }
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
        .alert("撤销失败", isPresented: Binding(
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

    private func dash(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }
}
