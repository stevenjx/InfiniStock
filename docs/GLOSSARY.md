# 术语表（中 → 英）

这份表是唯一的译法依据。同一概念只允许一种英文，否则界面会自己打架。

## 核心概念

| 中文 | English | 备注 |
|---|---|---|
| 机器 / 一台 | machine / unit | 不做 "device"（那是硬件设备的泛称） |
| 入库 | intake | 动词用 add、名词用 intake；不做 "stock in" |
| 出库销售 | sell | 按钮写 "Sell"，不做 "check out" |
| 库存 | inventory | 不做 "stock"（stock 会与 status 混） |
| 待办 | to-do | 复数 "to-dos"，不做 "task"（tasks 全给系统后台用） |
| 批次 | batch | 采购批次 |
| 单据 | order | 不做 "document"（内部另有 receipt） |
| 凭证 | receipt | 打印出来的那张 |
| 客户 | customer | 不做 "client"（to B 才用 client） |
| 成交价 | sale price | 与 list price 区分 |
| 标价 | list price | 不做 "tag price" |
| 进价 | cost | 人民币进价写 "cost (CNY)" |
| 总进价 | landed cost | 成本会计标准说法，含运费 |
| 运费 | shipping | 不做 "freight"（那是物流业的） |
| 汇率 | exchange rate | |
| 毛利 | gross profit | 不做 "margin"（margin 专指率） |
| 毛利率 | gross margin | 与毛利区分开 |
| 折扣 | discount | |
| 抹零 | rounding | 尾数取整 |
| 收款方式 | payment method | |
| 欠款 / 应收 | outstanding | 不做 "receivables"（太财务） |
| 保修 | warranty | |
| 售后 | after-sales | |
| 库龄 | days in stock | 不做 "age"（太模糊） |
| 可售天数 | days of supply | 供应链标准说法 |
| 售速 | sell-through | |
| 滞销 | slow-moving | |
| 缺货 / 断货 | out of stock | |
| 补货 | restock | |
| 盘点 | reconciliation | |
| 数据安全 | data safety | |
| 备份 | backup | |

## 界面元素

| 中文 | English |
|---|---|
| 设置 | Settings |
| 搜索 | Search |
| 筛选 | Filter |
| 全部 | All |
| 空状态 | empty state → 用户可见文案不出现这个词 |
| 已选中 N 台 | N selected |
| 查看详情 | View details |
| 改标价 | Edit price |
| 取消选择 | Clear selection |
| 取消 | Cancel |
| 保存 | Save |
| 完成 | Done |
| 删除 | Delete |
| 确认 | Confirm |
| 导入 | Import |
| 导出 | Export |
| 恢复 | Restore |
| 打印 | Print |

## 状态

| 中文 | English |
|---|---|
| 在库 | In stock |
| 已售 | Sold |
| 锁定 | Locked |
| 有效 | Active |
| 已作废 | Voided |
| 部分退货 | Partially returned |
| 已全退 | Fully returned |

## 成色

| 中文 | English |
|---|---|
| 全新 | New |
| 99新 | Like new |
| 95新 | Excellent |
| 9成新 | Good |
| 8成新 | Fair |
| 7成新以下 | Poor |

> 用 Apple 翻新机的分级用词（New / Like new / Excellent / Good / Fair / Poor），
> 比逐字翻译「99 new」好读，也不失准确。

## 货币

- 中文：`K 2,250,000`
- English：`MMK 2,250,000`
- 人民币：`¥3,600` / `CNY 3,600`

## 语气

- **陈述式，不用祈使句加感叹**：「别再拖了」→「已超过 7 天未备份」；"Stop putting it off" → "No backup in 7 days"
- **不出现第一人称**：不用「我」「你」；改写成无主语或第三人称
- **数字与单位之间加空格**：`7 days`、`K 2,250,000`
- **句末不加句号**（界面短句），完整句子才加
- **动词开头用于按钮**：Edit price / View details / Clear selection

## 禁止翻译（必须原样保留）

- 序列号、型号、芯片名（M2 / M3 Pro）
- 样例客户姓名（陈先生 / 林女士）——这些是用户数据，不进术语表
- 中文财务大写（零壹贰…）、万 / 亿 这类中文数量级词：这是人民币大写金额的实现细节，
  英文界面走数字格式，不该逐字翻
- 机型配色（深空灰 / 午夜色）——属于商品属性值，与型号同理，保持原样

---

## 实现说明

- 译文集中在 `InfiniStock/Localizable.xcstrings`，由 `scripts/build_strings.py`
  与 `scripts/build_strings_interp.py` 生成，便于复核与批量改译。
- 带插值的文案已由 `scripts/wrap_interpolated.py` 改写为
  `String(localized: "...\(expr)...")`，Xcode 才会提取成 `%lld` / `%@` 占位符。
  裸插值到运行时已是拼好的文本，catalog 查不到。
- 少数含嵌套引号的插值无法进 catalog（键里不允许内层引号），
  改写为 `String(format:String(localized: "...%@..."), ...)`。
- 语言切换点：设置 → 外观 → 语言。写 `AppleLanguages` 并重建视图树，不重启。
