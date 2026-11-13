import SwiftUI
import SwiftData

/// 跨视图共享的界面状态，由菜单命令驱动。
@Observable
final class AppState {
    var showingIntake = false
    var showingSearch = false
    var showingSettings = false
    var showingImport = false
    /// 分区快捷键（⌘1–⌘5）请求；由 RootView 消费
    var sectionRequest: SidebarSection?
    var showingDashboard = false
    /// ⌘⇧S 出库请求；由 RootView 判断当前是否可出库后消费
    var saleRequest = false
    /// ⌥⌘D 显示/隐藏详情栏；由 RootView 消费
    var detailToggleRequest = false
}
