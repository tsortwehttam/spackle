import AppKit
import Carbon
import Foundation

final class ReplacementService {
    private struct SelectionSnapshot {
        var element: AXUIElement
        var id: String
        var offset: Int
        var length: Int
    }

    private let ax: AccessibilityService

    init(ax: AccessibilityService) {
        self.ax = ax
    }

    func replaceCurrentSelection(
        element: AXUIElement,
        response: String,
        useClipboardFallback: Bool,
        useSyntheticFallback: Bool
    ) -> Bool {
        _ = ax.focus(element)
        if ax.setSelectedText(element, text: response) {
            return true
        }
        if useClipboardFallback && replaceCurrentSelectionWithClipboard(element: element, response: response) {
            return true
        }
        if useSyntheticFallback {
            _ = ax.focus(element)
            postUnicode(response)
            return true
        }
        return false
    }

    func replace(
        element: AXUIElement,
        oldText: String,
        oldUTF16Base: Int,
        verifyExpected: Bool,
        triggerRange: Range<String.Index>,
        response: String,
        useClipboardFallback: Bool,
        useSyntheticFallback: Bool,
        preferAtomicValueReplace: Bool,
        allowNonAtomicFallback: Bool,
        restoreSelection: Bool
    ) -> Bool {
        let liveInfo = ax.calcElementTextInfo(element)
        let liveText = liveInfo.text
        let liveRange = calcLiveTriggerRange(
            oldText: oldText,
            triggerRange: triggerRange,
            liveText: liveText
        )

        let snapshot = calcActiveSelectionSnapshot()
        let fallbackStart = oldUTF16Base + oldText.utf16.distance(from: oldText.utf16.startIndex, to: triggerRange.lowerBound.samePosition(in: oldText.utf16) ?? oldText.utf16.startIndex)
        let fallbackEnd = oldUTF16Base + oldText.utf16.distance(from: oldText.utf16.startIndex, to: triggerRange.upperBound.samePosition(in: oldText.utf16) ?? oldText.utf16.startIndex)
        let liveStart: Int
        let liveEnd: Int
        if let liveRange,
           let lower = liveRange.lowerBound.samePosition(in: liveText.utf16),
           let upper = liveRange.upperBound.samePosition(in: liveText.utf16) {
            liveStart = liveInfo.utf16Base + liveText.utf16.distance(from: liveText.utf16.startIndex, to: lower)
            liveEnd = liveInfo.utf16Base + liveText.utf16.distance(from: liveText.utf16.startIndex, to: upper)
        } else {
            liveStart = fallbackStart
            liveEnd = fallbackEnd
        }
        let start = max(0, liveStart)
        let end = max(start, liveEnd)
        let length = end - start
        let inserted = response.utf16.count
        let replacedID = ax.calcElementID(element)
        let expectedText: String?
        if verifyExpected && liveInfo.isFullText, let liveRange {
            var expected = liveText
            expected.replaceSubrange(liveRange, with: response)
            expectedText = expected
        } else {
            expectedText = nil
        }

        if preferAtomicValueReplace && replaceWithWholeValue(element: element, expectedText: expectedText) {
            if restoreSelection {
                restoreActiveSelection(snapshot: snapshot, replacedID: replacedID, replacedOffset: start, replacedLength: length, insertedLength: inserted)
            }
            return true
        }
        if allowNonAtomicFallback == false {
            return false
        }
        if replaceWithAccessibilityRange(element: element, offset: start, length: length, response: response, expectedText: expectedText) {
            if restoreSelection {
                restoreActiveSelection(snapshot: snapshot, replacedID: replacedID, replacedOffset: start, replacedLength: length, insertedLength: inserted)
            }
            return true
        }
        if useClipboardFallback && replaceWithClipboardInjection(element: element, offset: start, length: length, response: response, expectedText: expectedText) {
            if restoreSelection {
                restoreActiveSelection(snapshot: snapshot, replacedID: replacedID, replacedOffset: start, replacedLength: length, insertedLength: inserted)
            }
            return true
        }
        if useSyntheticFallback && replaceWithSyntheticTyping(element: element, offset: start, length: length, response: response, expectedText: expectedText) {
            if restoreSelection {
                restoreActiveSelection(snapshot: snapshot, replacedID: replacedID, replacedOffset: start, replacedLength: length, insertedLength: inserted)
            }
            return true
        }
        return false
    }

    private func calcLiveTriggerRange(oldText: String, triggerRange: Range<String.Index>, liveText: String) -> Range<String.Index>? {
        if oldText == liveText {
            return triggerRange
        }
        let segment = String(oldText[triggerRange])
        if segment.isEmpty {
            return nil
        }
        return liveText.range(of: segment, options: .backwards)
    }

    private func replaceWithAccessibilityRange(element: AXUIElement, offset: Int, length: Int, response: String, expectedText: String?) -> Bool {
        if replaceSelectedText(element: element, offset: offset, length: length, response: response, expectedText: expectedText) {
            return true
        }

        let text = ax.calcElementText(element)
        guard text.isEmpty == false else {
            return false
        }
        guard let start = text.utf16.index(text.utf16.startIndex, offsetBy: offset, limitedBy: text.utf16.endIndex),
              let end = text.utf16.index(start, offsetBy: length, limitedBy: text.utf16.endIndex),
              let s = start.samePosition(in: text),
              let e = end.samePosition(in: text) else {
            return false
        }

        var newText = text
        newText.replaceSubrange(s..<e, with: response)
        if ax.setText(element, text: newText) == false {
            return false
        }
        return true
    }

    private func replaceWithWholeValue(element: AXUIElement, expectedText: String?) -> Bool {
        guard let expectedText else {
            return false
        }
        if ax.setText(element, text: expectedText) == false {
            return false
        }
        return waitForExpectedText(element: element, expectedText: expectedText)
    }

    private func replaceWithClipboardInjection(element: AXUIElement, offset: Int, length: Int, response: String, expectedText: String?) -> Bool {
        _ = ax.focus(element)
        if ax.setSelection(element, utf16Offset: offset, utf16Length: length) == false {
            return false
        }
        Thread.sleep(forTimeInterval: 0.02)
        if replaceSelectedText(element: element, offset: offset, length: length, response: response, expectedText: expectedText) {
            return true
        }

        let pb = NSPasteboard.general
        let backup = copyPasteboardItems(pb)
        pb.clearContents()
        pb.setString(response, forType: .string)

        postKeyTap(code: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        if waitForExpectedText(element: element, expectedText: expectedText) == false {
            restorePasteboard(pb, items: backup)
            return false
        }

        restorePasteboard(pb, items: backup)
        return true
    }

    private func replaceWithSyntheticTyping(element: AXUIElement, offset: Int, length: Int, response: String, expectedText: String?) -> Bool {
        _ = ax.focus(element)
        if ax.setSelection(element, utf16Offset: offset, utf16Length: length) == false {
            return false
        }
        Thread.sleep(forTimeInterval: 0.02)
        if replaceSelectedText(element: element, offset: offset, length: length, response: response, expectedText: expectedText) {
            return true
        }

        postKeyTap(code: CGKeyCode(kVK_Delete), flags: [])
        postUnicode(response)
        return waitForExpectedText(element: element, expectedText: expectedText)
    }

    private func replaceCurrentSelectionWithClipboard(element: AXUIElement, response: String) -> Bool {
        let pb = NSPasteboard.general
        let backup = copyPasteboardItems(pb)
        defer { restorePasteboard(pb, items: backup) }
        pb.clearContents()
        pb.setString(response, forType: .string)
        _ = ax.focus(element)
        postKeyTap(code: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        return true
    }

    private func replaceSelectedText(element: AXUIElement, offset: Int, length: Int, response: String, expectedText: String?) -> Bool {
        let delays: [TimeInterval] = [0.0, 0.02, 0.06]
        for delay in delays {
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            _ = ax.focus(element)
            if ax.setSelection(element, utf16Offset: offset, utf16Length: length) == false {
                continue
            }
            if ax.setSelectedText(element, text: response) {
                if waitForExpectedText(element: element, expectedText: expectedText) {
                    return true
                }
            }
        }
        return false
    }

    private func waitForExpectedText(element: AXUIElement, expectedText: String?) -> Bool {
        guard let expectedText else {
            return true
        }
        let delays: [TimeInterval] = [0.0, 0.02, 0.06, 0.12]
        for delay in delays {
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            if ax.calcElementText(element) == expectedText {
                return true
            }
        }
        return false
    }

    private func calcActiveSelectionSnapshot() -> SelectionSnapshot? {
        let focused = ax.calcFocusedElement()
        let id = ax.calcElementID(focused)
        guard let range = ax.calcSelection(focused), range.location >= 0, range.length >= 0 else {
            return nil
        }
        return SelectionSnapshot(
            element: focused,
            id: id,
            offset: range.location,
            length: range.length
        )
    }

    private func restoreActiveSelection(snapshot: SelectionSnapshot?, replacedID: String, replacedOffset: Int, replacedLength: Int, insertedLength: Int) {
        guard let snapshot else {
            return
        }
        let delta = insertedLength - replacedLength
        let corrected: Int
        if snapshot.id == replacedID {
            corrected = calcAdjustedOffset(
                offset: snapshot.offset,
                replacedOffset: replacedOffset,
                replacedLength: replacedLength,
                delta: delta
            )
        } else {
            corrected = snapshot.offset
        }
        let offset = max(0, corrected)
        let length = max(0, snapshot.length)
        _ = ax.setSelection(snapshot.element, utf16Offset: offset, utf16Length: length)

        let retries: [TimeInterval] = [0.05, 0.14]
        for delay in retries {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [ax, self] in
                if self.shouldRetrySelection(
                    snapshot: snapshot,
                    replacedID: replacedID,
                    replacedOffset: replacedOffset,
                    insertedLength: insertedLength,
                    targetOffset: offset,
                    targetLength: length
                ) == false {
                    return
                }
                _ = ax.setSelection(snapshot.element, utf16Offset: offset, utf16Length: length)
            }
        }
    }

    private func shouldRetrySelection(
        snapshot: SelectionSnapshot,
        replacedID: String,
        replacedOffset: Int,
        insertedLength: Int,
        targetOffset: Int,
        targetLength: Int
    ) -> Bool {
        if targetLength != 0 || snapshot.id != replacedID {
            return false
        }
        let wrong = replacedOffset + insertedLength
        if wrong == targetOffset {
            return false
        }
        guard let current = ax.calcSelection(snapshot.element), current.length == 0 else {
            return false
        }
        return current.location == wrong
    }

    private func calcAdjustedOffset(offset: Int, replacedOffset: Int, replacedLength: Int, delta: Int) -> Int {
        if offset <= replacedOffset {
            return offset
        }
        let replacedEnd = replacedOffset + replacedLength
        if offset <= replacedEnd {
            return replacedOffset + max(0, replacedLength + delta)
        }
        return offset + delta
    }

    private func postKeyTap(code: CGKeyCode, flags: CGEventFlags) {
        guard let src = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func postUnicode(_ text: String) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        for scalar in text.utf16 {
            var chars = [scalar]
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else {
                continue
            }
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func copyPasteboardItems(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        let items = pb.pasteboardItems ?? []
        return items.map { item in
            let clone = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    clone.setData(data, forType: type)
                }
            }
            return clone
        }
    }

    private func restorePasteboard(_ pb: NSPasteboard, items: [NSPasteboardItem]) {
        pb.clearContents()
        if items.isEmpty {
            return
        }
        pb.writeObjects(items)
    }
}
