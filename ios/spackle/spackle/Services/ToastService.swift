import AppKit
import SwiftUI

final class ToastService {
    private let TOAST_OFFSET_Y: CGFloat = 4
    private var panel = ToastPanel()
    private var hide = DispatchWorkItem(block: {})
    weak var statusItem: NSStatusItem?

    func show(message: String, ttl: TimeInterval, point: CGPoint? = nil, pinToMenuBar: Bool = false) {
        if panel.contentViewController == nil {
            panel = ToastPanel(
                contentRect: NSRect(x: 0, y: 0, width: 260, height: 32),
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

        let hostView = NSHostingView(rootView: ToastView(message: message))
        let fitted = hostView.fittingSize
        panel.setContentSize(fitted)
        panel.contentView = hostView

        let anchor: CGPoint
        if pinToMenuBar, let pt = calcStatusItemCenter() {
            anchor = pt
        } else {
            anchor = point ?? NSEvent.mouseLocation
        }
        panel.setFrameOrigin(NSPoint(x: anchor.x - fitted.width / 2, y: anchor.y - fitted.height - TOAST_OFFSET_Y))
        panel.orderFrontRegardless()

        hide.cancel()
        if ttl > 0 {
            let job = DispatchWorkItem { [weak self] in
                self?.panel.orderOut(nil)
            }
            hide = job
            DispatchQueue.main.asyncAfter(deadline: .now() + ttl, execute: job)
        }
    }

    func hideNow() {
        hide.cancel()
        panel.orderOut(nil)
    }

    private func calcStatusItemCenter() -> CGPoint? {
        guard let button = statusItem?.button,
              let win = button.window else { return nil }
        let r = button.convert(button.bounds, to: nil)
        let sr = win.convertToScreen(r)
        return CGPoint(x: sr.midX, y: sr.minY)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
    }
}
