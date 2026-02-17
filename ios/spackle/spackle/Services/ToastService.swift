import AppKit
import SwiftUI

final class ToastService {
    private let TOAST_OFFSET_Y: CGFloat = 10
    private var panel = ToastPanel()
    private var hide = DispatchWorkItem(block: {})

    func show(message: String, ttl: TimeInterval, point: CGPoint? = nil, pinToMenuBar: Bool = false) {
        if panel.contentViewController == nil {
            panel = ToastPanel(
                contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }

        panel.contentView = NSHostingView(rootView: ToastView(message: message))

        let mouse = pinToMenuBar ? calcMenuBarPoint() : (point ?? NSEvent.mouseLocation)
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - TOAST_OFFSET_Y))
        panel.orderFrontRegardless()

        hide.cancel()
        let job = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
        }
        hide = job
        DispatchQueue.main.asyncAfter(deadline: .now() + ttl, execute: job)
    }

    func hideNow() {
        hide.cancel()
        panel.orderOut(nil)
    }

    private func calcMenuBarPoint() -> CGPoint {
        if let pt = calcStatusItemPoint() {
            return pt
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return NSEvent.mouseLocation
        }
        let frame = screen.frame
        return CGPoint(x: frame.maxX - 26, y: frame.maxY - 6)
    }

    private func calcStatusItemPoint() -> CGPoint? {
        for win in NSApp.windows.reversed() {
            let className = NSStringFromClass(type(of: win))
            if className.contains("NSStatusBarWindow"), win.frame.width > 0, win.frame.height > 0 {
                return CGPoint(x: win.frame.midX, y: win.frame.minY)
            }
            guard let root = win.contentView else {
                continue
            }
            if let btn = calcStatusBarButton(in: root) {
                let r = btn.convert(btn.bounds, to: nil)
                let sr = win.convertToScreen(r)
                return CGPoint(x: sr.midX, y: sr.minY)
            }
        }
        return nil
    }

    private func calcStatusBarButton(in root: NSView) -> NSStatusBarButton? {
        if let btn = root as? NSStatusBarButton {
            return btn
        }
        for child in root.subviews {
            if let btn = calcStatusBarButton(in: child) {
                return btn
            }
        }
        return nil
    }
}

private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct ToastView: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.black.opacity(0.88), in: Capsule())
    }
}
