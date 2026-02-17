import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(ctl: AppController) {
        if window == nil {
            window = calcWindow()
        }
        guard let window else {
            return
        }

        applyWindowChrome(window)
        window.contentView = NSHostingView(rootView: SettingsView(ctl: ctl))
        if window.frame.height < 700 || window.frame.width < 680 {
            window.setContentSize(NSSize(width: 700, height: 760))
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == window else {
            return
        }
        window = nil
    }

    private func calcWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 700)
        window.setContentSize(NSSize(width: 700, height: 760))
        window.center()
        return window
    }

    private func applyWindowChrome(_ window: NSWindow) {
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.styleMask.remove(.fullSizeContentView)
        window.title = "Spackle"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbar = nil
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.closeButton)?.isEnabled = true
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.zoomButton)?.isEnabled = true
    }
}
