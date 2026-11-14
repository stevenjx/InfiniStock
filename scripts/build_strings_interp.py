#!/usr/bin/env python3
"""插值字符串的译文。

规则：键里的 \\(...) 在英文里原样保留——Swift 会把它们统一编译成 %lld / %@
占位符，翻译只负责调整文字与语序，不能改动或删除占位符本身。
"""
import json
import pathlib

T = {
    # ── 计数类 ──
    "\\(days) 天": "%lld days",
    "\\(badge) 项": "%lld",
    "\\(itemCount) 台": "%lld machines",
    "\\(soldCount) 台": "%lld sold",
    "\\(pool.count) 台": "%lld units",
    "\\(averageAge) 天": "%lld days",
    "\\(orderCount) 张": "%lld orders",
    "\\(kindCount) 类问题": "%lld kinds of issue",
    "\\(items.count) 台": "%lld units",
    "\\(slice.count) 笔": "%lld payments",
    "\\(machineCount) 台": "%lld units",
    "\\(bucket.count) 台": "%lld units",
    "\\(overdueCount) 台": "%lld overdue",
    "\\(sellableCount) 台": "%lld sellable",
    "\\(changes.count) 次": "%lld changes",
    "\\(entries.count) 项": "%lld items",
    "\\(batteryCycles) 次": "%lld cycles",
    "\\(item.ageInDays) 天": "%lld days",
    "\\(customers.count) 位": "%lld customers",
    "\\(filtered.count) 批": "%lld batches",
    "\\(filtered.count) 张": "%lld orders",
    "\\(batches.count) 批": "%lld batches",
    "\\(Item.overdueDays) 天": "%lld days",
    "\\(stats.inStockCount) 台": "%lld units",
    "\\(preview.rows.count) 台": "%lld machines",
    "\\(stats.soldInWindow) 台": "%lld sold",
    "\\(preview.issues.count) 行": "%lld rows",
    "\\(order.itemList.count) 台": "%lld units",
    "\\(monthBatches.count) 批": "%lld batches",
    "\\(preview.totalLines) 行": "%lld rows",
    "\\(item.batteryCycles) 次": "%lld cycles",
    "\\(customer.orderCount) 张": "%lld orders",
    "\\(customer.orderCount) 次": "%lld purchases",
    "\\(customer.machineCount) 台": "%lld units",
    "\\(customerOrders.count) 张": "%lld orders",
    "\\(settings.warrantyDays) 天": "%lld days",
    "\\(settings.backupRetention) 份": "%lld copies",
    "\\(Item.highCycles) 次": "≥ %lld cycles",
    "\\(item.batteryHealth)%": "%lld%",
    "\\(Item.weakHealth)%": "< %lld%",
    "\\(stats.overdueItems.count) 台超期": "%lld overdue",
    "\\(stats.outstandingOrderCount) 张单未收讫": "%lld orders unpaid",
    "\\(stats.slowMovingCount) 台超 \\(Item.overdueDays) 天": "%lld over %lld days",
    "\\(unpricedCount) 台未标价": "%lld unpriced",
    "\\(items.count - sellableCount) 台": "%lld units",
    "\\(items.count - 8) 台未列出": "and %lld more",
    "\\(changes.count - 6) 次更早的记录": "and %lld earlier changes",
    "\\(preview.issues.count - 50) 条未显示": "and %lld more not shown",
    "\\(customers.reduce(0) { $0 + $1.machineCount }) 台": "%lld units",
    "\\(TodoCenter.involvedCount(entries)) 台机器": "%lld machines",

    # ── 计数 + 单位前缀 ──
    "已导入 \\(count) 台": "Imported %lld machines",
    "台数 \\(count)": "%lld units",
    "\\(todayOrders.count) 张单": "%lld orders today",
    "共 \\(rows.count) 台": "%lld machines",
    "共 \\(customers.count) 位": "%lld customers",
    "共 \\(rows.count) 项 · 涉及 \\(TodoCenter.involvedCount(rows)) 台":
        "%lld items · %lld machines involved",
    "共 \\(rows.count) 台 · 筛选「\\(keyword)」": "%lld machines · filtered by \"%@\"",
    "已选 \\(items.count) 台": "%lld selected",
    "已选中 \\(items.count) 台": "%lld selected",
    "删除 \\(targets.count) 台机器": "Delete %lld machines",
    "删除 \\(pendingDelete.count) 台机器？": "Delete %lld machines?",
    "批量出库 \\(chosen.count) 台…": "Sell %lld machines…",
    "待出库 \\(items.count) 台": "%lld to sell",
    "在库 \\(stats.inStockCount) 台": "%lld in stock",
    "在库 \\(items.filter { $0.status == .inStock }.count) 台":
        "%lld in stock",
    "近 \\(stats.windowDays) 天售出": "%lld sold in %lld days",
    "导入 \\(preview.rows.count) 台": "Import %lld machines",
    "已入库 \\(savedSerial)": "Added %@",
    "库存效率 · 近 \\(stats.windowDays) 天": "Stock efficiency · last %lld days",
    "按近 \\(stats.windowDays) 天卖速": "At the last %lld days' rate",
    "库存效率 · 近 \\(stats.windowDays) 天": "Stock efficiency · %lld days",

    # ── 金额 ──
    "· 成本 \\(cost.mmk)": "· Cost %@",
    "标价合计 \\(listed.mmk)": "Total list price %@",
    "标价合计 \\(stats.stockListedValue.mmk)": "Total list price %@",
    "小计 \\(subtotal.mmk)": "Subtotal %@",
    "应收 \\(payable.mmk)": "Due %@",
    "应收 \\(order.total.mmk)，已收 \\(order.collected.mmk)": "Due %@, received %@",
    "欠 \\(outstanding.mmk)": "Owes %@",
    "欠 \\(customer.outstanding.mmk)": "Owes %@",
    "未收 \\(order.outstanding.mmk)": "Unpaid %@",
    "还欠 \\(report.outstanding.mmk)": "Outstanding %@",
    "每台 \\(report.averageTicket.mmk)": "%@ per unit",
    "成本 \\(item.landedCost.mmk)": "Cost %@",
    "毛利 \\(profit.signedMMK)": "Gross profit %@",
    "毛利率 \\(marginText)": "Gross margin %@",
    "· 毛利率 \\(Money.text(margin))%": "· Gross margin %@%%",
    "毛利率 \\(Money.text($0))%": "Gross margin %@%%",
    "毛利率 \\((profit / base * 100).rounded(1))%": "Gross margin %@%%",
    "毛利率 \\((profit / revenue * 100).rounded(1))%": "Gross margin %@%%",
    "毛利率 \\(Money.text(((listed - cost) / listed * 100).rounded(1)))%":
        "Gross margin %@%%",
    "这笔会亏 \\((-profit).mmk)": "This loses %@",
    "实收低于这 \\(items.count) 台的总进价 \\(landedTotal.mmk)，确认前请复核成交价与折扣。":
        "Received is below the %lld machines' landed cost of %@. Check sale prices and discounts before confirming.",
    "把标价改为 \\(advice.suggestedPrice.mmk)": "Set list price to %@",
    " · 当前比建议高 \\(gap.mmk)": " · %@ above the suggestion",
    " · 当前比建议低 \\((-gap).mmk)": " · %@ below the suggestion",
    "折扣加抹零超过商品小计 \\(subtotal.mmk)": "Discount plus rounding exceeds the subtotal of %@",
    "收款金额超过未收的 \\(due.mmk)": "Amount exceeds the %@ still due",
    "均摊每台 \\((totalShipping / Decimal(machineCount)).rounded(0).mmk)":
        "%@ per unit",
    "\\(batch.name) · 成本 \\(cost.mmk)": "%@ · Cost %@",
    "\\(slice.count) 台 · 收入 \\(slice.revenue.mmk)": "%lld units · %@ revenue",
    "\\(customer.name) · 累计 \\(customer.revenue.mmk)": "%@ · %@ total",
    "\\(order.returnedCount) 台 · 退回 \\(order.returnedAmount.mmk)": "%lld units · %@ returned",
    "\\(order.number) · 应收 \\(order.total.mmk)": "%@ · Due %@",
    "售后：本单已退货 \\(document.returnedCount) 台，退回 \\(document.returnedAmount.mmk)，上述金额为退货后净额。":
        "After-sales: %lld units on this order were returned for %@. The amounts above are net of returns.",
    "商品小计（\\(document.lines.count) 台）": "Subtotal (%lld units)",
    "保修：\\(settings.warrantyDays) 天": "Warranty: %lld days",
    "上次 \\(Money.text(settings.defaultExchangeRate))": "Last used %@",
    "1 元 = \\(Money.text(item.exchangeRate))": "1 CNY = %@",
    "1 元 = \\(Money.text(batch.exchangeRate)) 缅币": "1 CNY = %@ MMK",
    "回本汇率 \\(breakEven)，今天 \\(Money.text(currentRate))，结汇亏 ¥\\(Money.text(loss))":
        "Break-even rate %@, today %@, conversion loss ¥%@",

    # ── 提醒与说明 ──
    "上次备份 \\(days) 天前": "Last backup %lld days ago",
    "超过 \\(BackupService.staleDays) 天没写备份，别再拖了":
        "No backup written in over %lld days",
    "\\(summary)，循环偏高": "%@, cycle count high",
    "\\(summary)，低于 \\(Item.weakHealth)%": "%@, below %lld%%",
    "健康 \\(item.batteryHealth)%": "Health %lld%%",
    "健康 \\(item.batteryHealthText) · 循环 \\(item.batteryCyclesText)，建议检测或作为议价点说明":
        "Health %@ · cycles %@. Have it tested or use it as a negotiating point.",
    "保修今天到期，客户随时可能回来": "Warranty expires today; the customer may return at any time",
    "保修还剩 \\(remaining) 天，\\(dayText(expiry)) 到期": "Warranty has %lld days left, expiring %@",
    "\\(overdue.count) 台超 \\(Item.overdueDays) 天": "%lld units over %lld days",
    "在库 \\(item.ageInDays) 天，占用成本 \\(item.landedCost.mmk)，建议促销或调价":
        "In stock %lld days, tying up %@. Consider promoting or repricing.",
    "入库 \\(item.ageInDays) 天仍未售出": "In stock %lld days and still unsold",
    "\\(Money.kyat(unallocated)) 运费还没摊到机器上": "%@ of shipping is not allocated to machines yet",
    "标价比总进价低 \\(Money.kyat(item.landedCost - item.listPrice))":
        "List price is %@ below landed cost",
    "标价 \\(item.listPrice.mmk) 低于总进价 \\(item.landedCost.mmk)，每台亏 \\((item.landedCost - item.listPrice).mmk)，建议调价":
        "List price %@ is below the landed cost of %@: every unit loses %@. Consider repricing.",
    "低于成本 · \\(item.modelName)": "Below cost · %@",
    "电池偏弱 · \\(item.modelName)": "Weak battery · %@",
    "库存超期 · \\(item.modelName)": "Aged stock · %@",
    "库龄 \\(item.ageInDays) 天": "%lld days in stock",
    "电池 \\(item.batteryHealth)%": "Battery %lld%%",
    "\\(customer.daysSinceLastPurchase) 天前": "%lld days ago",
    "\\(customer.orderCount) 次": "%lld purchases",
    "老客户 · 已购 \\(matched.orderCount) 次 · 累计 \\(matched.revenue.mmk)":
        "Returning customer · %lld purchases · %@ total",
    "复购 \\((Decimal(repeaters) / Decimal(customers.count) * 100).rounded(0))%":
        "Repeat rate %@%%",
    "较昨日 \\(sign)\\(Money.text(change))%": "%@%@%% vs yesterday",
    "\\(report.orderCount) 张单 · \\(report.machineCount) 台": "%lld orders · %lld units",
    "按型号 · \\(report.byModel.count) 款": "By model · %lld models",
    "本周累计 销售额 \\(summary.revenue.mmk) · 毛利 \\(summary.profit.signedMMK)":
        "This week: %@ revenue · %@ gross profit",
    "在库机器都已定价、电池正常、库龄在 \\(Item.overdueDays) 天以内，批次运费摊完了，也没有快到期的保修":
        "Everything is priced, batteries are healthy, stock is under %lld days old, batch shipping is allocated, and no warranty is about to expire",
    "每天首次启动写一份快照，只保留最新 \\(settings.backupRetention) 份，更早的自动删除。":
        "A snapshot is written on first launch each day. The newest %lld are kept; older ones are removed.",
    "每天首次启动自动备份一次（可在设置里关闭），保留最近 \\(ShopSettings.load().backupRetention) 份。目录由你在系统面板中授权，App 之后才能持续写入。":
        "One snapshot per day on first launch (can be disabled in Settings), keeping the newest %lld. You grant the folder in a system panel; only then can the app write to it.",
    "可售天数 = 在库 ÷ 近 \\(stats.windowDays) 天日均销量；窗口内没有售出的型号标为「无成交」":
        "Days of supply = stock ÷ average daily sales over the last %lld days. Models with no sales in that window are marked No sales.",
    "现在是 \\(itemCount) 台机器、\\(orderCount) 张单据": "%lld machines, %lld orders",
    "已恢复 \\(snapshot.items.count) 台机器、\\(snapshot.orders.count) 张单据":
        "Restored %lld machines and %lld orders",
    "已导出 \\(report.machineCount) 台到 \\(url.lastPathComponent)": "Exported %lld machines to %@",
    "已导出到 \\(url.lastPathComponent)": "Exported to %@",
    "已备份 \\(url.lastPathComponent)": "Backed up to %@",
    "导出失败：\\(error.localizedDescription)": "Export failed: %@",
    "备份文件无法解析：\\(detail)": "The backup could not be read: %@",
    "备份格式版本 \\(version) 高于当前 App，请先升级":
        "Backup format %lld is newer than this app. Update the app first.",
    "这份备份是旧格式（v\\(version)），金额口径与当前版本不同，无法直接恢复。请用当前版本重新导出备份。":
        "This backup uses an older format (v%lld) with different amount semantics and cannot be restored directly. Export a new backup from the current version.",
    "调试库初始化失败：\\(url.path)": "Could not open the debug store: %@",
    "目标毛利率 \\(targetMarginPercent)% 反推": "Derived from a %lld%% target margin",
    "，库龄 \\(ageInDays) 天再降 \\(markdownPercent)%": ", plus %lld days in stock for another %lld%% off",
    "建议价 = 总进价 ÷ (1 − 目标毛利率)，库龄超过 \\(PricingAdvice.markdownStartDays) 天后每满一周再降 \\(PricingAdvice.markdownPerWeek)%，最多降 \\(PricingAdvice.maxMarkdownPercent)%，且不低于总进价。详情页会按这条规则给出建议价，可一键采用。":
        "Suggested price = landed cost ÷ (1 − target margin), then %lld%% off for every full week past %lld days, capped at %lld%% and never below landed cost. The details panel applies this rule and the price can be adopted in one click.",

    # ── 单据与编号 ──
    "单据 \\(number) 已作废": "Order %@ was voided",
    "单据 \\(number) 没有未收金额": "Order %@ has nothing outstanding",
    "单据 \\(number) 没有关联机器，无法操作": "Order %@ has no machines and cannot be changed",
    "撤销销售单 \\(order.number)": "Void order %@",
    "删除机器 \\(item.serialNumber)": "Delete machine %@",
    "编辑 \\(item.modelName)": "Edit %@",
    "单号 \\(document.number)": "Order %@",
    "本单已退 \\(order.returnedCount) 台": "%lld units returned on this order",
    "凭证-\\(order.number).pdf": "receipt-%@.pdf",
    "销售明细-\\(range.rawValue).csv": "sales-%@.csv",
    "由 InfiniStock 生成 · \\(dateText(Date()))": "Generated by InfiniStock · %@",
    "大写：\\(ChineseAmount.uppercase(document.total))": "In words: %@",
    "\\(formatter.string(from: bounds.start)) 至 \\(formatter.string(from: lastDay))": "%@ to %@",

    # ── 导入与校验 ──
    "第 \\(issue.line) 行": "Row %lld",
    "与第 \\(firstLine) 行重复": "Duplicate of row %lld",
    "序列号 \\(serial) 已入库，本次录入被拦截": "Serial %@ is already in inventory; entry blocked",
    "序列号 \\(serial) 不在库，无法出库": "Serial %@ is not in inventory and cannot be sold",
    "序列号 \\(serial) 无法删除：\\(reason)": "Serial %@ could not be deleted: %@",
    "序列号 \\(serial) 不属于单据 \\(number)": "Serial %@ is not on order %@",
    "\\(field) 不是有效数字": "%@ is not a valid number",
    "\\(bad.item.serialNumber) 的成交价（必须大于 0）": "Sale price for %@ (must be greater than 0)",
    "\\(year) 年单号已用尽（9999），请检查数据": "Order numbers for %lld are exhausted (9999). Check the data.",
    '无法识别「\\(trimmed)」，可选：\\(ItemCondition.allCases.map(\\.rawValue).joined(separator: "、"))':
        "\"%@\" is not recognised. Choose from: %@",

    # ── 机型与状态 ──
    "\\(item.modelName) · \\(item.status.label) · 总进价 \\(item.landedCost.mmk)":
        "%@ · %@ · Landed cost %@",
}

def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    path = root / "InfiniStock" / "Localizable.xcstrings"
    catalog = json.loads(path.read_text(encoding="utf-8"))
    added = 0
    for zh, en in T.items():
        entry = catalog["strings"].setdefault(zh, {})
        entry["extractionState"] = "manual"
        locs = entry.setdefault("localizations", {})
        locs["zh-Hans"] = {"stringUnit": {"state": "translated", "value": zh}}
        locs["en"] = {"stringUnit": {"state": "translated", "value": en}}
        added += 1
    path.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"追加 {added} 条插值译文，catalog 共 {len(catalog['strings'])} 条")

if __name__ == "__main__":
    main()
