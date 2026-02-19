import AppKit
import ApplicationServices
import Carbon
import Combine
import Foundation
import SwiftUI

enum EngineState: String {
    case idle = "Idle"
    case awaiting = "AwaitingResponse"
    case replacing = "Replacing"
    case paused = "Paused"
}

@MainActor
final class AppController: NSObject, ObservableObject {
    var selectionRewriteShortcut: String { settings.rewriteShortcut.displayName }

    @Published var state: EngineState = .idle
    @Published var statusText = "Idle"
    @Published var hasAccessibility = false
    @Published var settings = AppSettings.default

    var apiKey: String {
        get { settings.apiKey }
        set { settings.apiKey = newValue }
    }

    private let settingsStore = SettingsStore()
    private let ax = AccessibilityService()
    private let llm = LLMClient()
    private let toast = ToastService()
    private let replacement: ReplacementService
    private let settingsWindow = SettingsWindowController()
    private(set) var statusItem: NSStatusItem!

    private var monitor: FocusedElementMonitor
    private var signals: InputSignalMonitor
    private var escLocal: Any = NSObject()
    private var escGlobal: Any = NSObject()
    private var currentTask = Task<Void, Never> {}
    private var pendingTriggerTask = Task<Void, Never> {}
    private var pendingTriggerSignature = ""
    private var lastTrigger = ""
    private var activeRequestID = UUID()
    private var lastInputActivity = Date.distantPast
    private var suppressUntil = Date.distantPast
    private var lastFallbackSignature = ""
    private var pendingFallbackTask = Task<Void, Never> {}
    private var lastProbeReport = ""
    private var bag = Set<AnyCancellable>()

    override init() {
        replacement = ReplacementService(ax: ax)
        monitor = FocusedElementMonitor(ax: ax)
        signals = InputSignalMonitor(settings: { .default })
        super.init()

        monitor.onTextChange = { [weak self] snapshot in
            guard let self else { return }
            Task { @MainActor in
                self.handleSnapshot(snapshot)
            }
        }
        monitor.onProbe = { [weak self] _, report in
            Task { @MainActor in
                self?.cacheProbeReport(report)
            }
        }
        signals.onHint = { [weak self] in
            Task { @MainActor in
                self?.monitor.pollNow()
            }
        }
        signals.onInputActivity = { [weak self] in
            Task { @MainActor in
                self?.lastInputActivity = Date()
            }
        }
        signals.onTypedTrigger = { [weak self] prompt, fullCount, signature in
            Task { @MainActor in
                self?.handleKeyStreamTypedTrigger(prompt: prompt, fullCharCount: fullCount, signature: signature)
            }
        }
        signals.onSelectionShortcut = { [weak self] in
            Task { @MainActor in
                self?.rewriteSelectionNow()
            }
        }

        settings = settingsStore.getSettings()
        if settings.provider == .custom {
            settings.provider = .openAI
            settings.customBaseURL = ""
            settingsStore.setSettings(settings)
        }
        if settings.spokenStart == "prompt" && settings.spokenEnd == "done" {
            settings.spokenStart = AppSettings.default.spokenStart
            settings.spokenEnd = AppSettings.default.spokenEnd
            settingsStore.setSettings(settings)
        }
        if settings.spokenStart == AppSettings.default.spokenStart && settings.spokenEnd == "spackle end" {
            settings.spokenEnd = AppSettings.default.spokenEnd
            settingsStore.setSettings(settings)
        }
        signals = InputSignalMonitor(settings: { [weak self] in
            self?.settings ?? .default
        })
        signals.onHint = { [weak self] in
            Task { @MainActor in
                self?.monitor.pollNow()
            }
        }
        signals.onInputActivity = { [weak self] in
            Task { @MainActor in
                self?.lastInputActivity = Date()
            }
        }
        signals.onTypedTrigger = { [weak self] prompt, fullCount, signature in
            Task { @MainActor in
                self?.handleKeyStreamTypedTrigger(prompt: prompt, fullCharCount: fullCount, signature: signature)
            }
        }
        signals.onSelectionShortcut = { [weak self] in
            Task { @MainActor in
                self?.rewriteSelectionNow()
            }
        }
        hasAccessibility = ax.isTrusted(prompt: false)
        if hasAccessibility {
            start()
        }
        setupStatusItem()
        bindEscCancel()
        bindAutosave()
        showAboutOnFirstLaunch()
    }

    var canRun: Bool {
        hasAccessibility && state != .paused
    }

    func start() {
        if hasAccessibility == false {
            return
        }
        if state != .paused {
            state = .idle
            statusText = "Active"
        }
        monitor.start()
        signals.start()
    }

    func pause() {
        cancelPendingTrigger()
        cancelPendingFallback()
        state = .paused
        statusText = "Paused"
        monitor.stop()
        signals.stop()
    }

    func resume() {
        if hasAccessibility == false {
            return
        }
        state = .idle
        statusText = "Active"
        monitor.start()
        signals.start()
    }

    func refreshAccessibility() {
        let trusted = ax.isTrusted(prompt: false)
        if trusted != hasAccessibility {
            hasAccessibility = trusted
            if trusted {
                start()
            }
        }
    }

    func requestAccessibility() {
        _ = ax.isTrusted(prompt: true)
        pollAccessibility(attemptsRemaining: 15)
    }

    private func pollAccessibility(attemptsRemaining: Int) {
        if attemptsRemaining <= 0 { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.hasAccessibility = self.ax.isTrusted(prompt: false)
            if self.hasAccessibility {
                self.start()
            } else {
                self.pollAccessibility(attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }

    func saveSettings() {
        settingsStore.setSettings(settings)
    }

    func showAbout() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settingsWindow.show(ctl: self)
        }
    }

    func copyFocusedDiagnostics() {
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
        let report = """
        app=\(appName)
        bundle=\(bundle)
        time=\(Date())

        \(ax.calcFocusedDiagnostics())
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(report, forType: .string)
        showToast(message: "Copied AX diagnostics", ttl: 1.2, element: nil)
    }

    func copyLastProbeDiagnostics() {
        guard lastProbeReport.isEmpty == false else {
            showToast(message: "No probe yet", ttl: 1.0, element: nil)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lastProbeReport, forType: .string)
        showToast(message: "Copied last AX probe", ttl: 1.2, element: nil)
    }

    func cancelGeneration() {
        if state != .awaiting {
            return
        }
        activeRequestID = UUID()
        currentTask.cancel()
        cancelPendingFallback()
        llm.cancel()
        toast.hideNow()
        state = .idle
        statusText = "Active"
        showToast(message: "Canceled", ttl: 1.0, element: nil)
    }

    func rewriteSelectionNow() {
        if hasAccessibility == false {
            toast.show(message: "Please grant accessibility", ttl: 3.0, pinToMenuBar: true)
            return
        }
        if canRun == false || state != .idle || Date() < suppressUntil {
            return
        }
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if bundle == Bundle.main.bundleIdentifier || settings.disabledApps.contains(bundle) {
            return
        }
        guard let element = ax.calcFocusedEditableElement() else {
            rewriteSelectionWithoutAX(expectedBundle: bundle)
            return
        }
        let info = ax.calcElementTextInfo(element)
        let selection = ax.calcSelection(element)
        // If AX can't read text, the element is likely unusable
        // (e.g. Electron apps where AX is partially broken). Fall back to
        // the non-AX path which uses clipboard copy/paste.
        let axSelectedText = ax.calcSelectedText(element)
        if info.text.isEmpty && axSelectedText.isEmpty {
            rewriteSelectionWithoutAX(expectedBundle: bundle)
            return
        }
        let selectedRange: Range<String.Index>?
        if let selection, selection.location >= 0, selection.length > 0 {
            selectedRange = calcSelectionRangeInText(
                text: info.text,
                utf16Base: info.utf16Base,
                selection: selection
            )
        } else {
            selectedRange = nil
        }
        var prompt = axSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty, let selectedRange {
            prompt = String(info.text[selectedRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if prompt.isEmpty {
            prompt = calcCopiedSelectionText().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if prompt.isEmpty {
            showToast(message: "Select text first", ttl: 1.0, element: element)
            return
        }

        let requestID = beginAwaitingRequest()
        let input: String
        if let selectedRange {
            let beforeCount = max(0, settings.contextBeforeChars)
            let afterCount = max(0, settings.contextAfterChars)
            let before = calcLeftContext(text: info.text, end: selectedRange.lowerBound, count: beforeCount)
            let after = calcRightContext(text: info.text, start: selectedRange.upperBound, count: afterCount)
            input = "\(before)DELIM_L\(prompt)DELIM_R\(after)"
        } else {
            input = "DELIM_L\(prompt)DELIM_R"
        }
        let systemPrompt = calcSystemPrompt(input: input)
        let oldText = info.text
        let oldUTF16Base = info.utf16Base
        let verifyExpected = info.isFullText

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.llm.calcCompletion(
                    settings: self.settings,
                    apiKey: self.apiKey,
                    systemPrompt: systemPrompt
                )
                if Task.isCancelled || self.activeRequestID != requestID {
                    return
                }
                if let selectedRange {
                    await self.applyResponseWhenIdle(
                        requestID: requestID,
                        element: element,
                        oldText: oldText,
                        oldUTF16Base: oldUTF16Base,
                        verifyExpected: verifyExpected,
                        triggerRange: selectedRange,
                        response: response
                    )
                } else {
                    await self.applyCurrentSelectionResponseWhenIdle(
                        requestID: requestID,
                        element: element,
                        response: response
                    )
                }
            } catch {
                await MainActor.run {
                    if self.activeRequestID != requestID {
                        return
                    }
                    self.state = .idle
                    self.statusText = "Active"
                    self.toast.hideNow()
                    self.showToast(message: self.calcRequestErrorMessage(error), ttl: 1.5, element: element)
                }
            }
        }
    }

    private func rewriteSelectionWithoutAX(expectedBundle: String) {
        let prompt = calcCopiedSelectionText().trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty {
            showToast(message: "Select text first", ttl: 1.0, element: nil)
            return
        }
        let requestID = beginAwaitingRequest()
        let input = "DELIM_L\(prompt)DELIM_R"
        let systemPrompt = calcSystemPrompt(input: input)

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.llm.calcCompletion(
                    settings: self.settings,
                    apiKey: self.apiKey,
                    systemPrompt: systemPrompt
                )
                if Task.isCancelled || self.activeRequestID != requestID {
                    return
                }
                await self.applySelectionPasteResponseWhenIdle(
                    requestID: requestID,
                    expectedBundle: expectedBundle,
                    response: response
                )
            } catch {
                await MainActor.run {
                    if self.activeRequestID != requestID {
                        return
                    }
                    self.state = .idle
                    self.statusText = "Active"
                    self.toast.hideNow()
                    self.showToast(message: self.calcRequestErrorMessage(error), ttl: 1.5, element: nil)
                }
            }
        }
    }

    private func handleSnapshot(_ snapshot: FocusSnapshot) {
        if canRun == false || state == .awaiting || state == .replacing {
            if canRun == false {
                cancelPendingTrigger()
            }
            return
        }
        if Date() < suppressUntil {
            return
        }

        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if bundle == Bundle.main.bundleIdentifier {
            cancelPendingTrigger()
            return
        }
        if settings.disabledApps.contains(bundle) {
            cancelPendingTrigger()
            return
        }

        let match = TriggerEngine.calcLatestTrigger(in: snapshot.text, settings: settings, source: snapshot.elementID)
        if match.prompt.isEmpty {
            cancelPendingTrigger()
            return
        }
        if match.signature == lastTrigger || match.signature == pendingTriggerSignature {
            return
        }

        scheduleTrigger(snapshot: snapshot, match: match)
    }

    private func scheduleTrigger(snapshot: FocusSnapshot, match: TriggerMatch) {
        cancelPendingTrigger()
        let ms = max(0, settings.triggerDelayMs)
        if ms == 0 {
            runTrigger(snapshot: snapshot, match: match)
            return
        }

        pendingTriggerSignature = match.signature
        pendingTriggerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            guard let self else { return }
            if Task.isCancelled {
                return
            }
            self.firePendingTrigger(expectedSource: snapshot.elementID, expectedSignature: match.signature)
        }
    }

    private func firePendingTrigger(expectedSource: String, expectedSignature: String) {
        if canRun == false || state == .awaiting || state == .replacing {
            cancelPendingTrigger()
            return
        }

        guard let el = ax.calcFocusedEditableElement() else {
            cancelPendingTrigger()
            return
        }
        let id = ax.calcElementID(el)
        if id != expectedSource {
            cancelPendingTrigger()
            return
        }
        let info = ax.calcElementTextInfo(el)
        let text = info.text
        let match = TriggerEngine.calcLatestTrigger(in: text, settings: settings, source: id)
        if match.prompt.isEmpty || match.signature != expectedSignature {
            cancelPendingTrigger()
            return
        }
        lastTrigger = match.signature
        pendingTriggerSignature = ""
        let requestID = beginAwaitingRequest()

        let promptInput = calcPromptInput(text: text, match: match)
        let systemPrompt = calcSystemPrompt(input: promptInput)
        let element = el
        let oldText = text
        let oldUTF16Base = info.utf16Base
        let verifyExpected = info.isFullText

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.llm.calcCompletion(settings: self.settings, apiKey: self.apiKey, systemPrompt: systemPrompt)
                if Task.isCancelled {
                    return
                }
                if self.activeRequestID != requestID {
                    return
                }
                await self.applyResponseWhenIdle(
                    requestID: requestID,
                    element: element,
                    oldText: oldText,
                    oldUTF16Base: oldUTF16Base,
                    verifyExpected: verifyExpected,
                    triggerRange: match.range,
                    response: response
                )
            } catch {
                await MainActor.run {
                    if self.activeRequestID != requestID {
                        return
                    }
                    self.state = .idle
                    self.statusText = "Active"
                    self.toast.hideNow()
                    self.showToast(message: self.calcRequestErrorMessage(error), ttl: 1.5, element: element)
                }
            }
        }
    }

    private func runTrigger(snapshot: FocusSnapshot, match: TriggerMatch) {
        firePendingTrigger(expectedSource: snapshot.elementID, expectedSignature: match.signature)
    }

    private func handleKeyStreamTypedTrigger(prompt: String, fullCharCount: Int, signature: String) {
        if canRun == false || state != .idle || prompt.isEmpty {
            return
        }
        if Date() < suppressUntil || signature == lastFallbackSignature {
            return
        }
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if bundle == Bundle.main.bundleIdentifier || settings.disabledApps.contains(bundle) {
            return
        }
        // Schedule as a delayed fallback so the AX-based trigger path can try first.
        // Apps with good AX support (TextEdit, Notes, etc.) will handle the trigger
        // via the normal path within the triggerDelay window, setting state to .awaiting.
        // Apps with poor AX text access (VSCode, Electron apps) won't, and this
        // fallback will fire using keystroke-based replacement instead.
        pendingFallbackTask.cancel()
        let capturedPrompt = prompt
        let capturedFullCount = fullCharCount
        let capturedSignature = signature
        let capturedBundle = bundle
        let delayNs = UInt64(max(settings.triggerDelayMs + 200, 500)) * 1_000_000
        pendingFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard let self else { return }
            if Task.isCancelled { return }
            self.fireKeyStreamFallback(
                prompt: capturedPrompt,
                fullCharCount: capturedFullCount,
                signature: capturedSignature,
                bundle: capturedBundle
            )
        }
    }

    private func fireKeyStreamFallback(prompt: String, fullCharCount: Int, signature: String, bundle: String) {
        if canRun == false || state != .idle {
            return
        }
        if Date() < suppressUntil || signature == lastFallbackSignature {
            return
        }
        let currentBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if currentBundle != bundle {
            return
        }
        lastFallbackSignature = signature
        let requestID = beginAwaitingRequest()
        let input = "DELIM_L\(prompt)DELIM_R"
        let systemPrompt = calcSystemPrompt(input: input)

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.llm.calcCompletion(settings: self.settings, apiKey: self.apiKey, systemPrompt: systemPrompt)
                if Task.isCancelled || self.activeRequestID != requestID {
                    return
                }
                await self.applyKeyStreamResponseWhenIdle(
                    requestID: requestID,
                    expectedBundle: bundle,
                    deleteCount: fullCharCount,
                    response: response
                )
            } catch {
                await MainActor.run {
                    if self.activeRequestID != requestID {
                        return
                    }
                    self.state = .idle
                    self.statusText = "Active"
                    self.toast.hideNow()
                    self.showToast(message: self.calcRequestErrorMessage(error), ttl: 1.5, element: nil)
                }
            }
        }
    }

    private func calcRequestErrorMessage(_ error: Error) -> String {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "API key missing"
        }
        if let llmError = error as? LLMClientError, llmError == .invalidConfig {
            return "Request config invalid"
        }
        return "Request failed"
    }

    private func beginAwaitingRequest() -> UUID {
        cancelPendingFallback()
        state = .awaiting
        statusText = "AwaitingResponse"
        let requestID = UUID()
        activeRequestID = requestID
        if settings.indicatorPlacement == .menuBar {
            toast.show(message: "Spackling...", ttl: 0, pinToMenuBar: true)
        }
        return requestID
    }

    private func applyResponseWhenIdle(
        requestID: UUID,
        element: AXUIElement,
        oldText: String,
        oldUTF16Base: Int,
        verifyExpected: Bool,
        triggerRange: Range<String.Index>,
        response: String
    ) async {
        let idleThreshold: TimeInterval = 0.16
        let maxWait: TimeInterval = 1.2
        let start = Date()
        while Date().timeIntervalSince(lastInputActivity) < idleThreshold && Date().timeIntervalSince(start) < maxWait {
            if Task.isCancelled || activeRequestID != requestID {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if Task.isCancelled || activeRequestID != requestID {
            return
        }
        applyResponse(
            element: element,
            oldText: oldText,
            oldUTF16Base: oldUTF16Base,
            verifyExpected: verifyExpected,
            triggerRange: triggerRange,
            response: response
        )
    }

    private func applyKeyStreamResponseWhenIdle(
        requestID: UUID,
        expectedBundle: String,
        deleteCount: Int,
        response: String
    ) async {
        let idleThreshold: TimeInterval = 0.16
        let maxWait: TimeInterval = 1.2
        let start = Date()
        while Date().timeIntervalSince(lastInputActivity) < idleThreshold && Date().timeIntervalSince(start) < maxWait {
            if Task.isCancelled || activeRequestID != requestID {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if Task.isCancelled || activeRequestID != requestID {
            return
        }
        let liveBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if liveBundle != expectedBundle {
            state = .idle
            statusText = "Active"
            toast.hideNow()
            showToast(message: "Skipped (focus changed)", ttl: 1.0, element: nil)
            return
        }
        applyKeyStreamReplacement(deleteCount: max(0, deleteCount), response: calcSanitizedResponse(response))
    }

    private func applyCurrentSelectionResponseWhenIdle(
        requestID: UUID,
        element: AXUIElement,
        response: String
    ) async {
        let idleThreshold: TimeInterval = 0.16
        let maxWait: TimeInterval = 1.2
        let start = Date()
        while Date().timeIntervalSince(lastInputActivity) < idleThreshold && Date().timeIntervalSince(start) < maxWait {
            if Task.isCancelled || activeRequestID != requestID {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if Task.isCancelled || activeRequestID != requestID {
            return
        }
        applyCurrentSelectionResponse(element: element, response: response)
    }

    private func applySelectionPasteResponseWhenIdle(
        requestID: UUID,
        expectedBundle: String,
        response: String
    ) async {
        let idleThreshold: TimeInterval = 0.16
        let maxWait: TimeInterval = 1.2
        let start = Date()
        while Date().timeIntervalSince(lastInputActivity) < idleThreshold && Date().timeIntervalSince(start) < maxWait {
            if Task.isCancelled || activeRequestID != requestID {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if Task.isCancelled || activeRequestID != requestID {
            return
        }
        let liveBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if liveBundle != expectedBundle {
            state = .idle
            statusText = "Active"
            toast.hideNow()
            showToast(message: "Skipped (focus changed)", ttl: 1.0, element: nil)
            return
        }
        applySelectionPasteResponse(response: response)
    }

    private func applyResponse(
        element: AXUIElement,
        oldText: String,
        oldUTF16Base: Int,
        verifyExpected: Bool,
        triggerRange: Range<String.Index>,
        response: String
    ) {
        state = .replacing
        statusText = "Replacing"
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let isMessages = bundle == "com.apple.MobileSMS"
        let allowClipboard = settings.useClipboardFallback
        let allowSynthetic = isMessages == false
        let preferAtomic = isMessages
        let allowNonAtomicFallback = isMessages == false
        let restoreSelection = isMessages == false
        let clean = calcSanitizedResponse(response)
        let ok = replacement.replace(
            element: element,
            oldText: oldText,
            oldUTF16Base: oldUTF16Base,
            verifyExpected: verifyExpected,
            triggerRange: triggerRange,
            response: clean,
            useClipboardFallback: allowClipboard,
            useSyntheticFallback: allowSynthetic,
            preferAtomicValueReplace: preferAtomic,
            allowNonAtomicFallback: allowNonAtomicFallback,
            restoreSelection: restoreSelection
        )
        toast.hideNow()
        if ok {
        } else {
            showToast(message: "Replace failed", ttl: 1.5, element: element)
        }

        suppressUntil = Date().addingTimeInterval(0.45)
        state = .idle
        statusText = "Active"
    }

    private func applyKeyStreamReplacement(deleteCount: Int, response: String) {
        state = .replacing
        statusText = "Replacing"
        for _ in 0..<deleteCount {
            postKeyTap(code: CGKeyCode(kVK_Delete), flags: [])
        }
        Thread.sleep(forTimeInterval: 0.05)
        // Use clipboard paste for reliability in apps without AX support (e.g. VSCode).
        // Synthetic character-by-character typing can be unreliable in Electron apps.
        let pb = NSPasteboard.general
        let backup = copyPasteboardItems(pb)
        pb.clearContents()
        pb.setString(response, forType: .string)
        postKeyTap(code: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        Thread.sleep(forTimeInterval: 0.05)
        restorePasteboard(pb, items: backup)
        toast.hideNow()
        suppressUntil = Date().addingTimeInterval(0.45)
        state = .idle
        statusText = "Active"
    }

    private func applyCurrentSelectionResponse(element: AXUIElement, response: String) {
        state = .replacing
        statusText = "Replacing"
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let isMessages = bundle == "com.apple.MobileSMS"
        let clean = calcSanitizedResponse(response)
        let ok = replacement.replaceCurrentSelection(
            element: element,
            response: clean,
            useClipboardFallback: settings.useClipboardFallback,
            useSyntheticFallback: isMessages == false
        )
        toast.hideNow()
        if ok == false {
            showToast(message: "Replace failed", ttl: 1.5, element: element)
        }
        suppressUntil = Date().addingTimeInterval(0.45)
        state = .idle
        statusText = "Active"
    }

    private func applySelectionPasteResponse(response: String) {
        state = .replacing
        statusText = "Replacing"
        let clean = calcSanitizedResponse(response)
        if clean.isEmpty {
            toast.hideNow()
            suppressUntil = Date().addingTimeInterval(0.45)
            state = .idle
            statusText = "Active"
            return
        }
        // Use clipboard paste — synthetic character-by-character typing
        // doesn't work in Electron apps like VSCode.
        let pb = NSPasteboard.general
        let backup = copyPasteboardItems(pb)
        pb.clearContents()
        pb.setString(clean, forType: .string)
        postKeyTap(code: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        // Give Electron/Chromium apps time to process the paste before restoring clipboard
        Thread.sleep(forTimeInterval: 0.3)
        restorePasteboard(pb, items: backup)
        toast.hideNow()
        suppressUntil = Date().addingTimeInterval(0.45)
        state = .idle
        statusText = "Active"
    }

    private func showToast(message: String, ttl: TimeInterval, element: AXUIElement?) {
        let point = element.flatMap { ax.calcCaretPoint($0) }
        toast.show(
            message: message,
            ttl: ttl,
            point: point,
            pinToMenuBar: settings.indicatorPlacement == .menuBar
        )
    }

    private func calcPromptInput(text: String, match: TriggerMatch) -> String {
        let beforeCount = max(0, settings.contextBeforeChars)
        let afterCount = max(0, settings.contextAfterChars)

        let before = calcLeftContext(text: text, end: match.range.lowerBound, count: beforeCount)
        let after = calcRightContext(text: text, start: match.range.upperBound, count: afterCount)
        return "\(before)DELIM_L\(match.prompt)DELIM_R\(after)"
    }

    private func cacheProbeReport(_ report: String) {
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
        lastProbeReport = """
        app=\(appName)
        bundle=\(bundle)
        time=\(Date())

        \(report)
        """
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

    private func calcSystemPrompt(input: String) -> String {
        let template = settings.systemPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if template.isEmpty {
            return AppSettings.default.systemPromptTemplate.replacingOccurrences(of: AppSettings.inputPlaceholder, with: input)
        }
        if template.contains(AppSettings.inputPlaceholder) {
            return template.replacingOccurrences(of: AppSettings.inputPlaceholder, with: input)
        }
        return "\(template)\n\n\(AppSettings.inputPlaceholder)"
            .replacingOccurrences(of: AppSettings.inputPlaceholder, with: input)
    }

    private func calcLeftContext(text: String, end: String.Index, count: Int) -> String {
        if count <= 0 {
            return ""
        }
        let left = text[..<end]
        let offset = min(count, left.count)
        let start = left.index(left.endIndex, offsetBy: -offset)
        return String(left[start..<left.endIndex])
    }

    private func calcRightContext(text: String, start: String.Index, count: Int) -> String {
        if count <= 0 {
            return ""
        }
        let right = text[start...]
        let offset = min(count, right.count)
        let end = right.index(right.startIndex, offsetBy: offset)
        return String(right[right.startIndex..<end])
    }

    private func calcSanitizedResponse(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return ""
        }

        if let extracted = calcDelimitedPayload(in: text, left: "DELIM_L", right: "DELIM_R") {
            text = extracted
        } else if let extracted = calcDelimitedPayload(in: text, left: settings.typedStart, right: settings.typedEnd) {
            text = extracted
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func calcDelimitedPayload(in text: String, left: String, right: String) -> String? {
        if left.isEmpty || right.isEmpty {
            return nil
        }
        guard let l = text.range(of: left), let r = text.range(of: right, options: .backwards), l.upperBound <= r.lowerBound else {
            return nil
        }
        let inner = text[l.upperBound..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if inner.isEmpty {
            return nil
        }
        return inner
    }

    private func calcSelectionRangeInText(text: String, utf16Base: Int, selection: CFRange) -> Range<String.Index>? {
        let total = text.utf16.count
        let start = selection.location - utf16Base
        if start < 0 || start > total {
            return nil
        }
        let end = min(total, start + selection.length)
        let utf16 = text.utf16
        guard let startUTF16 = utf16.index(utf16.startIndex, offsetBy: start, limitedBy: utf16.endIndex),
              let endUTF16 = utf16.index(utf16.startIndex, offsetBy: end, limitedBy: utf16.endIndex),
              let lower = startUTF16.samePosition(in: text),
              let upper = endUTF16.samePosition(in: text) else {
            return nil
        }
        return lower..<upper
    }

    private func calcCopiedSelectionText() -> String {
        let pb = NSPasteboard.general
        let backup = copyPasteboardItems(pb)
        let originalCount = pb.changeCount
        postKeyTap(code: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        Thread.sleep(forTimeInterval: 0.05)
        let copied: String
        if pb.changeCount != originalCount {
            copied = pb.string(forType: .string) ?? ""
        } else {
            copied = ""
        }
        restorePasteboard(pb, items: backup)
        return copied
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

    private func bindEscCancel() {
        escLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelGeneration()
            }
            return event
        } ?? NSObject()

        escGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.cancelGeneration()
                }
            }
        } ?? NSObject()
    }

    private func cancelPendingTrigger() {
        pendingTriggerTask.cancel()
        pendingTriggerSignature = ""
    }

    private func cancelPendingFallback() {
        pendingFallbackTask.cancel()
    }

    private let statusMenu = NSMenu()

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(named: "MenuBarIcon")
        button.image?.isTemplate = true
        statusItem.menu = statusMenu
        statusMenu.delegate = self
        toast.statusItem = statusItem
    }

    fileprivate func rebuildStatusMenu() {
        statusMenu.removeAllItems()

        let statusTitle = calcMenuStatusText()
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        statusMenu.addItem(statusItem)

        if hasAccessibility {
            if settings.typedEnabled {
                let toggleTitle = state == .paused ? "Resume Listening" : "Pause Listening"
                let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(togglePauseResume), keyEquivalent: "")
                toggleItem.target = self
                statusMenu.addItem(toggleItem)
            }

            let rewriteTitle = "Rewrite Selection (\(settings.rewriteShortcut.displayName))"
            let rewriteItem = NSMenuItem(title: rewriteTitle, action: #selector(rewriteSelectionMenuAction), keyEquivalent: "")
            rewriteItem.target = self
            statusMenu.addItem(rewriteItem)
        }

        let settingsItem = NSMenuItem(title: "About & Settings", action: #selector(showAboutMenuAction), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitMenuAction), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    private func calcMenuStatusText() -> String {
        if state == .awaiting || state == .replacing {
            return "Spackling..."
        }
        if state == .paused {
            return "Paused"
        }
        if hasAccessibility == false {
            return "Accessibility Required"
        }
        return "Ready"
    }

    @objc private func togglePauseResume() {
        if state == .paused {
            resume()
        } else {
            pause()
        }
    }

    @objc private func rewriteSelectionMenuAction() {
        rewriteSelectionNow()
    }

    @objc private func showAboutMenuAction() {
        showAbout()
    }

    @objc private func quitMenuAction() {
        NSApp.terminate(nil)
    }

    private func showAboutOnFirstLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showAbout()
        }
    }

    private func bindAutosave() {
        $settings
            .dropFirst()
            .sink { [weak self] value in
                var copy = value
                copy.sendContext = copy.contextBeforeChars > 0 || copy.contextAfterChars > 0
                self?.settingsStore.setSettings(copy)
            }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.settingsStore.setSettings(self.settings)
            }
            .store(in: &bag)
    }
}

extension AppController: NSMenuDelegate {
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            refreshAccessibility()
            rebuildStatusMenu()
        }
    }
}
