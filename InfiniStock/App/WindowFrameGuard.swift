import AppKit
import SwiftUI

/// 窗口位置护栏。
///
/// macOS 会把窗口位置记进 `NSWindow` 的 frame autosave，但屏幕换了、分辨率降了、
/// 外接屏拔了之后，这个记忆值仍然被原样恢复——窗口就落在可见区域之外：
/// 进程活着、菜单栏写着 App 名字、屏幕上什么都没有。用户只能删偏好文件才能救回来。
///
/// 这里在窗口挂上视图后检查一次：只要窗口中心不在任何一块屏幕的可见区域里，
/// 或者窗口比屏幕还大，就把它收进主屏并居中。只动首次展示，不做持续监听，
/// 免得跟用户自己拖动窗口打架。
struct WindowFrameGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        GuardView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class GuardView: NSView {
        private var applied = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !applied else { return }
            applied = true
            // 等 SwiftUI 把 minSize / 内容尺寸都算完再决定，否则量到的是 0×0
            DispatchQueue.main.async { Self.fit(window) }
        }

        private static func fit(_ window: NSWindow) {
            guard let screen = targetScreen(for: window) else { return }
            let visible = screen.visibleFrame
            var frame = window.frame

            let tooWide = frame.width > visible.width
            let tooTall = frame.height > visible.height
            let offscreen = !visible.contains(CGPoint(x: frame.midX, y: frame.midY))
            guard tooWide || tooTall || offscreen else { return }

            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = visible.minX + (visible.width - frame.width) / 2
            frame.origin.y = visible.minY + (visible.height - frame.height) / 2
            window.setFrame(frame, display: true)
        }

        /// 优先选跟窗口重叠面积最大的屏幕；完全没重叠时退回主屏。
        private static func targetScreen(for window: NSWindow) -> NSScreen? {
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return nil }
            let frame = window.frame
            let overlapping = screens.max { lhs, rhs in
                area(frame.intersection(lhs.visibleFrame)) < area(frame.intersection(rhs.visibleFrame))
            }
            guard let overlapping, area(frame.intersection(overlapping.visibleFrame)) > 0 else {
                return NSScreen.main ?? screens.first
            }
            return overlapping
        }

        private static func area(_ rect: NSRect) -> CGFloat {
            guard !rect.isNull, rect.width > 0, rect.height > 0 else { return 0 }
            return rect.width * rect.height
        }
    }
}
