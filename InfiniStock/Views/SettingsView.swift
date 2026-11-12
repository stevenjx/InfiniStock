import SwiftUI

/// 店铺信息与凭证抬头。同时提供「数据安全」入口，集中在一个设置窗口里。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var settings = ShopSettings.load()
    @State private var rateText = ""
    @State private var savedMessage: String?
    @State private var showingDataSafety = false

    var body: some View {
        Form {
            Section("店铺信息") {
                TextField("店名", text: $settings.shopName)
                TextField("电话", text: $settings.phone)
                TextField("地址", text: $settings.address)
            }

            Section("入库默认值") {
                HStack {
                    Text("汇率")
                    Spacer()
                    TextField("1 元 = ? 缅币", text: $rateText)
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                        .frame(width: 120)
                    Text("缅币")
                        .font(.caption)
                        .foregroundStyle(Token.Ink.tertiary)
                }
                Text("入库表单会自动填入这个汇率。汇率天天变，改一处比每台机器手输一遍可靠。")
                    .font(.caption)
                    .foregroundStyle(Token.Ink.secondary)
            }

            Section("凭证") {
                Stepper(value: $settings.warrantyDays, in: 0...365) {
                    LabeledContent("保修天数", value: "\(settings.warrantyDays) 天")
                }
                TextField("附加说明（可选，会印在凭证条款最上方）", text: $settings.footnote)
            }

            Section {
                Button("保存") { save() }
                    .keyboardShortcut("s")
                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
            }

            Section("数据") {
                Button {
                    showingDataSafety = true
                } label: {
                    Label("数据安全与备份", systemImage: "externaldrive.badge.checkmark")
                }
                Text("导出、备份目录、恢复。建议每周至少确认一次备份目录可用。")
                    .font(.caption)
                    .foregroundStyle(Token.Ink.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .sheet(isPresented: $showingDataSafety) {
            NavigationStack { DataSafetyView() }
                .frame(minWidth: 560, minHeight: 600)
        }
        .onAppear {
            rateText = settings.defaultExchangeRate > 0 ? Money.text(settings.defaultExchangeRate) : ""
        }
    }

    private func save() {
        settings.shopName = settings.shopName.trimmingCharacters(in: .whitespaces)
        settings.defaultExchangeRate = Money.parse(rateText) ?? 0
        settings.save()
        savedMessage = "已保存"
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            savedMessage = nil
        }
    }
}