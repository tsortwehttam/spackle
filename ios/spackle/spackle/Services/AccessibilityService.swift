import ApplicationServices
import AppKit
import Foundation

struct ElementTextInfo {
    var text: String
    var utf16Base: Int
    var isFullText: Bool
}

final class AccessibilityService {
    private let manualAccessibilityAttribute = "AXManualAccessibility" as CFString

    func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let opts = [key: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
    }

    func calcFocusedElement() -> AXUIElement {
        let system = AXUIElementCreateSystemWide()
        if let focused = copyElementAttribute(system, attr: kAXFocusedUIElementAttribute as CFString).value {
            return focused
        }
        if let app = copyElementAttribute(system, attr: kAXFocusedApplicationAttribute as CFString).value,
           let focused = copyElementAttribute(app, attr: kAXFocusedUIElementAttribute as CFString).value {
            return focused
        }
        if let app = calcFrontmostApplicationElement(),
           let focused = copyElementAttribute(app, attr: kAXFocusedUIElementAttribute as CFString).value {
            return focused
        }
        if let app = calcFrontmostApplicationElement(), enableManualAccessibility(app) == .success {
            if let focused = copyElementAttribute(system, attr: kAXFocusedUIElementAttribute as CFString).value {
                return focused
            }
            if let focused = copyElementAttribute(app, attr: kAXFocusedUIElementAttribute as CFString).value {
                return focused
            }
        }
        return system
    }

    func calcFocusedEditableElement() -> AXUIElement? {
        calcEditableElement(startingAt: calcFocusedElement())
    }

    func calcFocusedDiagnostics() -> String {
        let system = AXUIElementCreateSystemWide()
        let stepA = copyElementAttribute(system, attr: kAXFocusedUIElementAttribute as CFString)
        let stepBApp = copyElementAttribute(system, attr: kAXFocusedApplicationAttribute as CFString)
        let stepBFocused = stepBApp.value.flatMap { copyElementAttribute($0, attr: kAXFocusedUIElementAttribute as CFString).value }
        let frontApp = calcFrontmostApplicationElement()
        let stepCFocused = frontApp.flatMap { copyElementAttribute($0, attr: kAXFocusedUIElementAttribute as CFString).value }
        let manualErr = frontApp.map(enableManualAccessibility) ?? .failure
        let manualEnabled = manualErr == .success
        let stepDFocused = frontApp.flatMap { copyElementAttribute($0, attr: kAXFocusedUIElementAttribute as CFString).value }
        let target = stepA.value ?? stepBFocused ?? stepCFocused ?? stepDFocused ?? system

        var base = calcDiagnostics(start: target, title: "Focused element diagnostics")
        base += "\n\nfocusResolution: system.focusedUI=\(stepA.error.rawValue)"
        base += " system.focusedApp=\(stepBApp.error.rawValue)"
        let stepBFocusedErr = stepBApp.value.map { copyElementAttribute($0, attr: kAXFocusedUIElementAttribute as CFString).error.rawValue } ?? -1
        base += " focusedApp.focusedUI=\(stepBFocusedErr)"
        if let frontApp {
            let stepCFocusedErr = copyElementAttribute(frontApp, attr: kAXFocusedUIElementAttribute as CFString).error.rawValue
            base += " frontApp.focusedUI=\(stepCFocusedErr)"
            let stepDFocusedErr = copyElementAttribute(frontApp, attr: kAXFocusedUIElementAttribute as CFString).error.rawValue
            base += " manualAccessibility=\(manualEnabled) manualAccessibilityErr=\(manualErr.rawValue) retry.frontApp.focusedUI=\(stepDFocusedErr)"
        } else {
            base += " frontApp.focusedUI=-1 manualAccessibility=false manualAccessibilityErr=-1 retry.frontApp.focusedUI=-1"
        }
        return base
    }

    func calcDiagnostics(start: AXUIElement, title: String = "Element diagnostics") -> String {
        let editable = calcEditableElement(startingAt: start)
        var lines: [String] = []
        lines.append(title)
        lines.append("focusedID=\(calcElementID(start))")
        lines.append("editableFound=\(editable != nil)")
        lines.append("")
        lines.append(contentsOf: calcDiagnosticsChain(start: start))
        return lines.joined(separator: "\n")
    }

    func calcEditableElement(startingAt el: AXUIElement) -> AXUIElement? {
        var node: AXUIElement? = el
        for _ in 0..<8 {
            guard let current = node else {
                return nil
            }
            if isEditable(current) && isSecure(current) == false {
                return current
            }
            node = calcParent(current)
        }
        return nil
    }

    func calcElementText(_ el: AXUIElement) -> String {
        calcElementTextInfo(el).text
    }

    func calcElementTextInfo(_ el: AXUIElement) -> ElementTextInfo {
        if let value = copyStringAttribute(el, attr: kAXValueAttribute as CFString), value.isEmpty == false {
            return ElementTextInfo(text: value, utf16Base: 0, isFullText: true)
        }
        if let value = copyAttributedStringAttribute(el, attr: kAXValueAttribute as CFString), value.isEmpty == false {
            return ElementTextInfo(text: value, utf16Base: 0, isFullText: true)
        }
        if let count = calcCharacterCount(el), count > 0, let value = calcStringForRange(el, location: 0, length: count), value.isEmpty == false {
            return ElementTextInfo(text: value, utf16Base: 0, isFullText: true)
        }
        if let range = calcVisibleRange(el), range.length > 0, let value = calcStringForRange(el, location: range.location, length: range.length), value.isEmpty == false {
            return ElementTextInfo(text: value, utf16Base: max(0, range.location), isFullText: false)
        }
        return ElementTextInfo(text: "", utf16Base: 0, isFullText: false)
    }

    func isEditable(_ el: AXUIElement) -> Bool {
        if isAttributeSettable(el, attr: kAXValueAttribute as CFString) {
            return true
        }
        if isAttributeSettable(el, attr: kAXSelectedTextAttribute as CFString) {
            return true
        }
        if isAttributeSettable(el, attr: kAXSelectedTextRangeAttribute as CFString) {
            return true
        }
        return false
    }

    func isSecure(_ el: AXUIElement) -> Bool {
        var role: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        if err != AXError.success {
            return false
        }
        let value = role as? String ?? ""
        return value == "AXSecureTextField"
    }

    func calcElementID(_ el: AXUIElement) -> String {
        "\(CFHash(el))"
    }

    func setText(_ el: AXUIElement, text: String) -> Bool {
        let err = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, text as CFTypeRef)
        return err == .success
    }

    func setCursor(_ el: AXUIElement, utf16Offset: Int) {
        var range = CFRange(location: utf16Offset, length: 0)
        guard let value = AXValueCreate(.cfRange, &range) else {
            return
        }
        AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, value)
    }

    func setSelection(_ el: AXUIElement, utf16Offset: Int, utf16Length: Int) -> Bool {
        var range = CFRange(location: utf16Offset, length: utf16Length)
        guard let value = AXValueCreate(.cfRange, &range) else {
            return false
        }
        let err = AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, value)
        return err == .success
    }

    func setSelectedText(_ el: AXUIElement, text: String) -> Bool {
        let err = AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return err == .success
    }

    func calcSelection(_ el: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &value)
        if err != .success {
            return nil
        }
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let v = value as! AXValue
        var range = CFRange()
        if AXValueGetValue(v, .cfRange, &range) == false {
            return nil
        }
        return range
    }

    func calcSelectedText(_ el: AXUIElement) -> String {
        if let value = copyStringAttribute(el, attr: kAXSelectedTextAttribute as CFString), value.isEmpty == false {
            return value
        }
        if let value = copyAttributedStringAttribute(el, attr: kAXSelectedTextAttribute as CFString), value.isEmpty == false {
            return value
        }
        return ""
    }

    func focus(_ el: AXUIElement) -> Bool {
        let err = AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return err == .success
    }

    func calcCaretPoint(_ el: AXUIElement) -> CGPoint? {
        var selected: CFTypeRef?
        let selectedErr = AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &selected)
        if selectedErr != .success {
            return nil
        }
        guard let selected, CFGetTypeID(selected) == AXValueGetTypeID() else {
            return nil
        }
        let selectedValue = selected as! AXValue

        var range = CFRange()
        let ok = AXValueGetValue(selectedValue, .cfRange, &range)
        if ok == false {
            return nil
        }

        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return nil
        }
        var boundsRef: CFTypeRef?
        let boundsErr = AXUIElementCopyParameterizedAttributeValue(
            el,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsRef
        )
        if boundsErr != .success {
            return nil
        }
        guard let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else {
            return nil
        }
        let boundsValue = boundsRef as! AXValue

        var rect = CGRect.zero
        let rectOK = AXValueGetValue(boundsValue, .cgRect, &rect)
        if rectOK == false || rect.isNull || rect.isInfinite {
            return nil
        }
        return CGPoint(x: rect.midX, y: rect.minY)
    }

    private func calcParent(_ el: AXUIElement) -> AXUIElement? {
        copyElementAttribute(el, attr: kAXParentAttribute as CFString).value
    }

    private func copyElementAttribute(_ el: AXUIElement, attr: CFString) -> (value: AXUIElement?, error: AXError) {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, attr, &value)
        if err != .success {
            return (nil, err)
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return (nil, .attributeUnsupported)
        }
        return (unsafeBitCast(value, to: AXUIElement.self), .success)
    }

    private func calcFrontmostApplicationElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func enableManualAccessibility(_ app: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(app, manualAccessibilityAttribute, kCFBooleanTrue)
    }

    private func calcDiagnosticsChain(start el: AXUIElement) -> [String] {
        var out: [String] = []
        var node: AXUIElement? = el
        for depth in 0..<8 {
            guard let current = node else {
                break
            }
            out.append(calcDiagnosticsLine(el: current, depth: depth))
            node = calcParent(current)
        }
        return out
    }

    private func calcDiagnosticsLine(el: AXUIElement, depth: Int) -> String {
        let role = copyStringAttribute(el, attr: kAXRoleAttribute as CFString) ?? "-"
        let subrole = copyStringAttribute(el, attr: kAXSubroleAttribute as CFString) ?? "-"
        let id = calcElementID(el)
        let editable = isEditable(el)
        let secure = isSecure(el)
        let valueSettable = isAttributeSettable(el, attr: kAXValueAttribute as CFString)
        let selectedTextSettable = isAttributeSettable(el, attr: kAXSelectedTextAttribute as CFString)
        let selectionSettable = isAttributeSettable(el, attr: kAXSelectedTextRangeAttribute as CFString)
        let value = copyStringAttribute(el, attr: kAXValueAttribute as CFString) ?? ""
        let attributedValue = copyAttributedStringAttribute(el, attr: kAXValueAttribute as CFString) ?? ""
        let chars = calcCharacterCount(el) ?? -1
        let visible = calcVisibleRange(el) ?? CFRange(location: -1, length: -1)
        let textInfo = calcElementTextInfo(el)
        let selection = calcSelection(el) ?? CFRange(location: -1, length: -1)
        return "[\(depth)] role=\(role) subrole=\(subrole) id=\(id) editable=\(editable) secure=\(secure) settable(value=\(valueSettable),selectedText=\(selectedTextSettable),selection=\(selectionSettable)) valueLen=\(value.count) attrValueLen=\(attributedValue.count) charCount=\(chars) visible=(\(visible.location),\(visible.length)) selection=(\(selection.location),\(selection.length)) textLen=\(textInfo.text.count) textBase=\(textInfo.utf16Base) fullText=\(textInfo.isFullText)"
    }

    private func isAttributeSettable(_ el: AXUIElement, attr: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        let err = AXUIElementIsAttributeSettable(el, attr, &settable)
        if err != .success {
            return false
        }
        return settable.boolValue
    }

    private func copyStringAttribute(_ el: AXUIElement, attr: CFString) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, attr, &value)
        if err != .success {
            return nil
        }
        return value as? String
    }

    private func copyAttributedStringAttribute(_ el: AXUIElement, attr: CFString) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, attr, &value)
        if err != .success {
            return nil
        }
        return (value as? NSAttributedString)?.string
    }

    private func calcCharacterCount(_ el: AXUIElement) -> Int? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, kAXNumberOfCharactersAttribute as CFString, &value)
        if err != .success {
            return nil
        }
        if let n = value as? NSNumber {
            return n.intValue
        }
        return nil
    }

    private func calcVisibleRange(_ el: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, kAXVisibleCharacterRangeAttribute as CFString, &value)
        if err != .success {
            return nil
        }
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let v = value as! AXValue
        var range = CFRange()
        if AXValueGetValue(v, .cfRange, &range) == false {
            return nil
        }
        return range
    }

    private func calcStringForRange(_ el: AXUIElement, location: Int, length: Int) -> String? {
        var range = CFRange(location: location, length: length)
        guard let axRange = AXValueCreate(.cfRange, &range) else {
            return nil
        }
        var out: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            el,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &out
        )
        if err != .success {
            return nil
        }
        return out as? String
    }
}
