import SwiftUI
import SwiftData

/// 跨视图共享的界面状态，由菜单命令驱动。
@Observable
final class AppState {
    var showingIntake = false
    var showingSearch = false
    var showingSettings = false
    var showingDashboard = false
}
