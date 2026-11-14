import SwiftUI
import SwiftData

/// 设置。左侧分栏 + 右侧表单，改完即存。
///
/// 原来的版本是一个 Form 加一个「保存」按钮：进来看不到数据规模、看不到备份状态、
/// 也不知道哪些阈值在影响待办。现在按「改什么」分组，每个分栏只回答一个问题。
/// 设置左侧分栏。提成顶层类型，AppState 才能记住"从备份待办进来要落在哪一栏"。
enum SettingsPane: String, CaseIterable, Identifiable {
    case shop = "店铺"
    case receipt = "单据凭证"
    case pricing = "定价与汇率"
    case backup = "数据与备份"
    case about = "关于"

    var id: String { rawValue }

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .shop: "storefront"
        case .receipt: "doc.plaintext"
        case .pricing: "tag"
        case .backup: "externaldrive.badge.checkmark"
        case .about: "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .shop: "抬头信息与开单默认值"
        case .receipt: "凭证上印什么、保修多久"
        case .pricing: "汇率、目标毛利与建议价口径"
        case .backup: "自动备份、保留份数与恢复"
        case .about: "版本、数据位置与快捷键"
        }
    }
}

struct SettingsView: View {
    /// 打开时落在哪一栏
    var initialPane: SettingsPane = .shop

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var settings = ShopSettings.load()
    @State private var rateText = ""
    @State private var pane: SettingsPane = .shop
    @State private var justSaved = false

    @State private var itemCount = 0
    @State private var orderCount = 0
    @State private var backupFolder: URL?
    @State private var lastBackupAt: Date?
    @State private var showingDataSafety = false
    @State private var choosingBackupFolder = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle()
                .fill(Token.Border.hairline)
                .frame(width: 1)
            content
        }
        .background(Token.Surface.canvas)
        .navigationTitle("设置")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $showingDataSafety) {
            NavigationStack { DataSafetyView() }
                .frame(minWidth: 560, minHeight: 600)
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        // 设置项都是配置，不是账目，没有"取消"的语义。改完立刻落盘，
        // 关窗口就生效，避免"填了但忘了点保存"这种只有用户会遇到的失败。
        .onChange(of: settings) { _, value in
            value.save()
            flashSaved()
        }
        .onChange(of: rateText) { _, text in
            settings.defaultExchangeRate = Money.parse(text) ?? 0
        }
        .onAppear {
            rateText = settings.defaultExchangeRate > 0 ? Money.text(settings.defaultExchangeRate) : ""
            pane = initialPane
            refreshData()
        }
        .fileImporter(isPresented: $choosingBackupFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                BackupService.rememberFolder(url)
                refreshData()
                flashSaved()
            }
        }
    }

    // MARK: - 分栏导航

    private var rail: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text("设置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Token.Ink.primary)
                Text("改动即时生效")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.tertiary)
            }
            .padding(.horizontal, Token.Space.m)
            .padding(.top, Token.Space.m)
            .padding(.bottom, Token.Space.m)

            ForEach(SettingsPane.allCases) { item in
                railRow(item)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 184, alignment: .leading)
        .background(Token.Surface.sidebar)
    }

    private func railRow(_ item: SettingsPane) -> some View {
        let selected = pane == item
        return Button {
            pane = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Token.Ink.onAccent : Token.Ink.secondary)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Token.Ink.onAccent : Token.Ink.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Token.Space.s)
            .frame(height: 32)
            .contentShape(.rect)
            .background(selected ? Token.Accent.brand : Color.clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Token.Space.s)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - 内容

    private var content: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.title)
                        .font(Token.Typography.pageTitle)
                        .foregroundStyle(Token.Ink.primary)
                    Text(pane.subtitle)
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.tertiary)
                }
                Spacer(minLength: 0)
                if justSaved {
                    Label("已保存", systemImage: "checkmark.circle")
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Status.ok)
                }
            }
            .padding(.horizontal, Token.Space.xl)
            .padding(.top, Token.Space.l)
            .padding(.bottom, Token.Space.s)

            Form {
                switch pane {
                case .shop: shopForm
                case .receipt: receiptForm
                case .pricing: pricingForm
                case .backup: backupForm
                case .about: aboutForm
                }
            }
            .formStyle(.grouped)
            // 分组表单默认自带一层灰底，铺在白卡上会出现一块突兀的圆角灰砖
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Token.Surface.card)
    }

    // MARK: - 店铺

    @ViewBuilder
    private var shopForm: some View {
        Section {
            TextField("店名", text: $settings.shopName)
            TextField("电话", text: $settings.phone)
            TextField("地址", text: $settings.address)
        } header: {
            Text("抬头信息")
        } footer: {
            Text("这三项会原样印在销售凭证顶部。留空也能开单，凭证上就不显示对应的行。")
        }

        Section("开单默认值") {
            Picker("收款方式", selection: $settings.defaultPaymentMethod) {
                ForEach(PaymentMethod.allCases) { method in
                    Text(method.rawValue).tag(method.rawValue)
                }
            }
            Text("新建出库单时预先选中的收款方式，开单时仍可改。")
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.secondary)
        }
    }

    // MARK: - 凭证

    @ViewBuilder
    private var receiptForm: some View {
        Section {
            Stepper(value: $settings.warrantyDays, in: 0...365) {
                LabeledContent("保修天数", value: settings.warrantyDays == 0 ? "不保修" : "\(settings.warrantyDays) 天")
            }
            TextField("附加说明", text: $settings.footnote, prompt: Text("可选，印在凭证条款最上方"))
        } header: {
            Text("凭证条款")
        } footer: {
            Text("凭证是销售凭证／收据，不是税务发票。真电子发票需要对接税务服务商。")
        }

        Section("预览") {
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.shopName.isEmpty ? "（未填店名）" : settings.shopName)
                    .font(Token.Typography.body.weight(.semibold))
                    .foregroundStyle(settings.shopName.isEmpty ? Token.Ink.tertiary : Token.Ink.primary)
                if !settings.phone.isEmpty {
                    Text(settings.phone)
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
                if !settings.address.isEmpty {
                    Text(settings.address)
                        .font(Token.Typography.caption)
                        .foregroundStyle(Token.Ink.secondary)
                }
                Hairline().padding(.vertical, 4)
                Text(settings.footnote.isEmpty ? "（无附加说明）" : settings.footnote)
                    .font(Token.Typography.caption)
                    .foregroundStyle(settings.footnote.isEmpty ? Token.Ink.tertiary : Token.Ink.primary)
                Text(settings.warrantyDays == 0 ? "保修：不保修" : "保修：\(settings.warrantyDays) 天")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 定价

    @ViewBuilder
    private var pricingForm: some View {
        Section {
            HStack {
                Text("1 元人民币 =")
                Spacer()
                TextField("460", text: $rateText)
                    .multilineTextAlignment(.trailing)
                    .decimalKeyboard()
                    .frame(width: 120)
                Text("缅币")
                    .font(.caption)
                    .foregroundStyle(Token.Ink.tertiary)
            }
        } header: {
            Text("当前汇率")
        } footer: {
            Text(settings.defaultExchangeRate > 0
                 ? "入库时自动填入这个汇率；每台机器入库时快照一次，之后改这里不动老货。"
                 : "还没设汇率：入库表单会留空，机型详情里也算不出回本汇率。")
        }

        Section {
            Stepper(value: $settings.targetMarginPercent, in: 0...80) {
                LabeledContent(
                    "目标毛利率",
                    value: settings.targetMarginPercent == 0 ? "关闭建议" : "\(settings.targetMarginPercent)%"
                )
            }
            if let example = PricingAdvice.make(
                landedCost: 1_000_000,
                targetMarginPercent: settings.targetMarginPercent,
                ageInDays: 0
            ) {
                LabeledContent("成本 K 1,000,000 时") {
                    Text(example.suggestedPrice.mmk)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("定价建议")
        } footer: {
            Text("建议价 = 总进价 ÷ (1 − 目标毛利率)，库龄超过 \(PricingAdvice.markdownStartDays) 天后每满一周再降 \(PricingAdvice.markdownPerWeek)%，最多降 \(PricingAdvice.maxMarkdownPercent)%，且不低于总进价。详情页会按这条规则给出建议价，可一键采用。")
        }

        Section {
            ruleRow("库龄警戒", "\(Item.overdueDays) 天")
            ruleRow("电池偏弱", "健康 < \(Item.weakHealth)%")
            ruleRow("循环偏高", "≥ \(Item.highCycles) 次")
        } header: {
            Text("待办口径")
        } footer: {
            Text("这三条决定「待办」里出现哪些提醒。口径固定写死，是为了让列表、待办、统计三处永远一致——同一台机器不该有两个超期标准。")
        }
    }

    private func ruleRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(Token.Typography.money)
                .foregroundStyle(Token.Ink.secondary)
        }
    }

    // MARK: - 备份

    @ViewBuilder
    private var backupForm: some View {
        if backupFolder == nil {
            Section {
                HStack(alignment: .top, spacing: Token.Space.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Token.Status.warn)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("还没有备份目录")
                            .font(Token.Typography.cellPrimary)
                            .foregroundStyle(Token.Ink.primary)
                        Text("整店的账只有一份，就在这台 Mac 的沙盒里。选一个文件夹，每天首次启动自动写一份过去。")
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("选择备份目录…") { choosingBackupFolder = true }
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("需要处理")
            }
        }

        Section("当前数据") {
            LabeledContent("机器", value: "\(itemCount) 台")
            LabeledContent("单据", value: "\(orderCount) 张")
        }

        Section {
            Toggle("每天首次启动自动备份", isOn: $settings.autoBackupEnabled)
            Stepper(value: $settings.backupRetention, in: 3...60, step: 1) {
                LabeledContent("保留份数", value: "\(settings.backupRetention) 份")
            }
            LabeledContent("备份目录") {
                Text(backupFolder?.path ?? "未设置")
                    .font(Token.Typography.caption)
                    .foregroundStyle(backupFolder == nil ? Token.Status.warn : Token.Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
            }
            LabeledContent("最近备份") {
                Text(lastBackupAt.map { $0.compactStamp } ?? "尚无")
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
            }
            HStack(spacing: Token.Space.s) {
                Button("选择备份目录…") { choosingBackupFolder = true }
                Button("立即备份") { runBackup() }
                    .disabled(backupFolder == nil)
            }
        } header: {
            Text("自动备份")
        } footer: {
            Text(backupFolder == nil
                 ? "还没选目录。macOS 沙盒不允许直接写「文稿」，必须由你在文件面板里授权一次，App 之后才能持续写入。"
                 : "每天首次启动写一份快照，只保留最新 \(settings.backupRetention) 份，更早的自动删除。")
        }

        Section("导出与恢复") {
            Button {
                showingDataSafety = true
            } label: {
                Label("打开数据安全", systemImage: "arrow.up.arrow.down.square")
            }
            Text("全量 JSON（可回灌）、CSV（给 Excel 看）、从备份恢复。恢复会覆盖当前数据，需要系统身份验证。")
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.secondary)
        }
    }

    // MARK: - 关于

    @ViewBuilder
    private var aboutForm: some View {
        Section {
            LabeledContent("名称", value: "InfiniStock")
            LabeledContent("版本", value: appVersion)
            LabeledContent("数据位置") {
                Text(storePath)
                    .font(Token.Typography.caption)
                    .foregroundStyle(Token.Ink.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        } header: {
            Text("应用")
        }

        Section("快捷键") {
            shortcut("入库", "⌘N")
            shortcut("搜索", "⌘F")
            shortcut("出库销售", "⌘⇧S")
            shortcut("批量导入", "⌘⇧I")
            shortcut("统计", "⌘⇧D")
            shortcut("显示/隐藏详情", "⌥⌘D")
            shortcut("设置", "⌘,")
            shortcut("删除选中机器", "⌫")
        }

        Section {
            Text("本地优先：数据只存在这台 Mac 上，没有云端副本。备份才是唯一的数据保险。")
                .font(Token.Typography.caption)
                .foregroundStyle(Token.Ink.secondary)
        }
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) {
            Text(keys)
                .font(Token.Typography.money)
                .foregroundStyle(Token.Ink.secondary)
        }
    }

    // MARK: - 动作

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private var storePath: String {
        AppStore.shared.container.configurations.first?.url.path ?? "—"
    }

    private func refreshData() {
        itemCount = (try? modelContext.fetchCount(FetchDescriptor<Item>())) ?? 0
        orderCount = (try? modelContext.fetchCount(FetchDescriptor<Order>())) ?? 0
        backupFolder = BackupService.backupFolder()
        lastBackupAt = BackupService.lastBackupAt
    }

    private func runBackup() {
        guard let folder = BackupService.backupFolder() else { return }
        do {
            _ = try BackupService.writeBackup(from: modelContext, into: folder)
            refreshData()
            flashSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func flashSaved() {
        withAnimation { justSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { justSaved = false }
        }
    }
}
