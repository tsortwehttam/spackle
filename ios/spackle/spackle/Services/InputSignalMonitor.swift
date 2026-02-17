import ApplicationServices
import AppKit
import Carbon
import Foundation

final class InputSignalMonitor {
    var onHint: () -> Void = {}
    var onInputActivity: () -> Void = {}
    var onTypedTrigger: (String, Int, String) -> Void = { _, _, _ in }
    var onSelectionShortcut: () -> Void = {}

    private let settings: () -> AppSettings
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var keyBuffer = ""
    private var rawBuffer = ""
    private var pasteTimer = Timer()
    private var lastPasteCount = NSPasteboard.general.changeCount
    private var lastHint = Date.distantPast
    private var lastTypedSignature = ""
    private var lastSelectionShortcutAt = Date.distantPast

    init(settings: @escaping () -> AppSettings) {
        self.settings = settings
    }

    func start() {
        startEventTap()
        startPasteboardMonitor()
    }

    func stop() {
        stopEventTap()
        pasteTimer.invalidate()
    }

    private func startPasteboardMonitor() {
        pasteTimer.invalidate()
        pasteTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let count = NSPasteboard.general.changeCount
            if count == self.lastPasteCount {
                return
            }
            self.lastPasteCount = count
            self.fireHint()
        }
        RunLoop.main.add(pasteTimer, forMode: .common)
    }

    private func startEventTap() {
        stopEventTap()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let user = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard type == .keyDown, let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let me = Unmanaged<InputSignalMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                me.handleEvent(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: user
        ) else {
            return
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = src
        if let src {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopEventTap() {
        if let src = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
    }

    private func handleEvent(_ event: CGEvent) {
        guard let ns = NSEvent(cgEvent: event) else {
            handleControlKey(event)
            return
        }
        if handleSelectionShortcut(ns) {
            return
        }
        guard let chars = ns.characters else {
            handleControlKey(event)
            return
        }
        onInputActivity()

        rawBuffer += chars
        keyBuffer += chars.lowercased()
        if keyBuffer.count > 1024 {
            keyBuffer.removeFirst(keyBuffer.count - 1024)
        }
        if rawBuffer.count > 1024 {
            rawBuffer.removeFirst(rawBuffer.count - 1024)
        }

        let s = settings()
        let typed = s.typedEnabled && s.typedEnd.isEmpty == false && keyBuffer.hasSuffix(s.typedEnd.lowercased())
        let spoken = s.spokenEnabled && s.spokenEnd.isEmpty == false && keyBuffer.hasSuffix(s.spokenEnd.lowercased())
        if typed {
            var local = s
            local.spokenEnabled = false
            let m = TriggerEngine.calcLatestTrigger(in: rawBuffer, settings: local, source: "keybuffer")
            if m.prompt.isEmpty == false && m.range.upperBound == rawBuffer.endIndex {
                let full = String(rawBuffer[m.range])
                let sig = "\(m.signature)|\(rawBuffer.count)"
                if sig != lastTypedSignature {
                    lastTypedSignature = sig
                    onTypedTrigger(m.prompt, full.count, sig)
                }
            }
        }
        if typed || spoken {
            fireHint()
        }
    }

    private func handleSelectionShortcut(_ event: NSEvent) -> Bool {
        let s = settings()
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags != s.rewriteShortcut.modifierFlags || event.keyCode != s.rewriteShortcut.keyCode {
            return false
        }
        let now = Date()
        if now.timeIntervalSince(lastSelectionShortcutAt) < 0.25 {
            return true
        }
        lastSelectionShortcutAt = now
        onSelectionShortcut()
        fireHint()
        return true
    }

    private func handleControlKey(_ event: CGEvent) {
        guard let ns = NSEvent(cgEvent: event) else {
            return
        }
        let code = ns.keyCode
        if code == 51 || code == 117 {
            if rawBuffer.isEmpty == false {
                rawBuffer.removeLast()
            }
            if keyBuffer.isEmpty == false {
                keyBuffer.removeLast()
            }
            return
        }
        if code == 53 || code == 36 {
            keyBuffer = ""
            rawBuffer = ""
            return
        }
    }

    private func fireHint() {
        let now = Date()
        if now.timeIntervalSince(lastHint) < 0.08 {
            return
        }
        lastHint = now
        onHint()
    }
}
