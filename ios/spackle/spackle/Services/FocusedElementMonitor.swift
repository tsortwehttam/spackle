import ApplicationServices
import Foundation

struct FocusSnapshot {
    var element: AXUIElement
    var elementID: String
    var text: String
    var utf16Base: Int
    var isFullText: Bool
}

final class FocusedElementMonitor {
    private let ax: AccessibilityService
    private var timer = Timer()
    private var lastID = ""
    private var lastText = ""
    private var lastProbeID = ""

    var onTextChange: (FocusSnapshot) -> Void = { _ in }
    var onProbe: (AXUIElement, String) -> Void = { _, _ in }

    init(ax: AccessibilityService) {
        self.ax = ax
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer.invalidate()
    }

    func reset() {
        lastID = ""
        lastText = ""
    }

    func pollNow() {
        tick()
    }

    private func tick() {
        let focused = ax.calcFocusedElement()
        let focusedID = ax.calcElementID(focused)
        if focusedID != lastProbeID {
            lastProbeID = focusedID
            onProbe(focused, ax.calcFocusedDiagnostics().replacingOccurrences(of: "Focused element diagnostics", with: "Live focus diagnostics"))
        }

        guard let el = ax.calcEditableElement(startingAt: focused) else {
            return
        }
        let id = ax.calcElementID(el)
        if id != lastID {
            lastID = id
            lastText = ""
        }

        let info = ax.calcElementTextInfo(el)
        let text = info.text
        if text.isEmpty || text == lastText {
            return
        }
        lastText = text
        onTextChange(FocusSnapshot(element: el, elementID: id, text: text, utf16Base: info.utf16Base, isFullText: info.isFullText))
    }
}
