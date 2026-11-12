import SwiftUI

/// 设计 token。所有颜色来自 Asset Catalog（含深色变体），
/// 视图里不允许再出现字面量颜色——否则深色模式下必然翻车。
enum Token {

    enum Surface {
        static let canvas = Color("SurfaceCanvas")
        static let card = Color("SurfaceCard")
        static let sidebar = Color("SurfaceSidebar")
        static let selected = Color("SurfaceSelected")
        /// 卡片内的工具条、表头、页脚，比卡片本身略沉一档
        static let header = Color("SurfaceHeader")
        /// 输入框、未选中的胶囊
        static let field = Color("SurfaceField")
    }

    enum Ink {
        static let primary = Color("TextPrimary")
        static let secondary = Color("TextSecondary")
        static let tertiary = Color("TextTertiary")
        /// 实心强调色上的文字
        static let onAccent = Color("TextOnAccent")
    }

    enum Border {
        static let hairline = Color("BorderHairline")
    }

    enum Shadow {
        /// 卡片投影：浅色下极轻，深色下靠不透明度拉开层次
        static let card = Color("ShadowCard")
    }

    enum Accent {
        static let brand = Color("AccentBrand")
        static let fill = Color("AccentFill")
    }

    /// 图表与徽章共用的状态色
    enum Status {
        static let ok = Color("StatusOK")
        static let warn = Color("StatusWarn")
        static let danger = Color("StatusDanger")
        static let neutral = Color("StatusNeutral")
    }

    enum Radius {
        static let badge: CGFloat = 999
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let panel: CGFloat = 14
    }

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Typography {
        /// 页面大标题
        static let screenTitle = Font.system(size: 26, weight: .bold)
        static let pageTitle = Font.system(size: 22, weight: .semibold)
        static let cardTitle = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let cellPrimary = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11)
        static let metric = Font.system(size: 24, weight: .semibold).monospacedDigit()
        static let money = Font.system(size: 13).monospacedDigit()
    }
}

/// 语义色调。业务状态映射到它，而不是直接挑颜色。
enum Tone {
    case brand
    case ok
    case warn
    case danger
    case neutral

    var color: Color {
        switch self {
        case .brand: Color("AccentBrand")
        case .ok: Color("StatusOK")
        case .warn: Color("StatusWarn")
        case .danger: Color("StatusDanger")
        case .neutral: Color("StatusNeutral")
        }
    }

    var fill: Color {
        switch self {
        case .brand: Color("AccentFill")
        case .ok: Color("StatusOKFill")
        case .warn: Color("StatusWarnFill")
        case .danger: Color("StatusDangerFill")
        case .neutral: Color("StatusNeutralFill")
        }
    }

    /// VoiceOver 朗读时说明颜色含义，避免"只靠颜色传达状态"
    var accessibilityName: String {
        switch self {
        case .brand: "进行中"
        case .ok: "正常"
        case .warn: "需要留意"
        case .danger: "异常"
        case .neutral: "已结束"
        }
    }

    var icon: String {
        switch self {
        case .brand: "info.circle.fill"
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .neutral: "minus.circle.fill"
        }
    }
}

extension ItemStatus {
    var tone: Tone {
        switch self {
        case .inStock: .ok
        case .locked: .warn
        case .sold: .neutral
        }
    }
}

extension Order {
    var tone: Tone {
        if isFullyReturned { return .danger }
        if isVoided { return .neutral }
        if hasReturns { return .warn }
        return .ok
    }
}
