import AppKit
import Carbon
import Foundation

enum ProviderKind: String, CaseIterable, Identifiable, Codable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case openRouter = "OpenRouter"
    case custom = "Custom"

    var id: String { rawValue }
}

struct ShortcutBinding: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifierFlags: UInt

    static let defaultShortcut = ShortcutBinding(
        keyCode: UInt16(kVK_ANSI_I),
        modifierFlags: NSEvent.ModifierFlags([.command, .option, .control]).rawValue
    )

    var asModifierFlags: NSEvent.ModifierFlags { .init(rawValue: modifierFlags) }

    var displayName: String {
        var result = ""
        let flags = asModifierFlags
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += calcKeyName(for: keyCode)
        return result
    }


}

private let specialKeyNames: [UInt16: String] = [
    36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
    63: "fn", 76: "↩", 96: "F5", 97: "F6", 98: "F7",
    99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
    107: "F14", 109: "F10", 111: "F12", 113: "F15",
    114: "⌦", 115: "↖", 116: "⇞", 117: "⌦", 119: "↘",
    120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→",
    125: "↓", 126: "↑",
]

private func calcKeyName(for keyCode: UInt16) -> String {
    if let sym = specialKeyNames[keyCode] { return sym }

    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return "(\(keyCode))"
    }
    let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue()
    let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var charCount = 0
    let err = UCKeyTranslate(
        keyLayout, keyCode, UInt16(kUCKeyActionDisplay),
        0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState, 4, &charCount, &chars
    )
    if err == noErr, charCount > 0 {
        return String(String.UnicodeScalarView(chars[..<charCount].compactMap { Unicode.Scalar($0) })).uppercased()
    }
    return "(\(keyCode))"
}

enum IndicatorPlacement: String, CaseIterable, Identifiable, Codable {
    case caret = "Near Caret"
    case menuBar = "Near Menu Bar"

    var id: String { rawValue }
}

struct AppSettings: Codable {
    static let inputPlaceholder = "{{SPACKLE_INPUT}}"

    var provider: ProviderKind
    var model: String
    var customBaseURL: String

    var typedStart: String
    var typedEnd: String
    var spokenStart: String
    var spokenEnd: String

    var typedEnabled: Bool
    var spokenEnabled: Bool
    var disabledApps: [String]
    var sendContext: Bool
    var contextBeforeChars: Int
    var contextAfterChars: Int
    var triggerDelayMs: Int
    var systemPromptTemplate: String
    var useClipboardFallback: Bool
    var indicatorPlacement: IndicatorPlacement
    var rewriteShortcut: ShortcutBinding
    var apiKey: String

    static let `default` = AppSettings(
        provider: .openAI,
        model: "",
        customBaseURL: "",
        typedStart: "<<",
        typedEnd: ">>",
        spokenStart: "spackle start",
        spokenEnd: "spackle stop",
        typedEnabled: false,
        spokenEnabled: false,
        disabledApps: [],
        sendContext: false,
        contextBeforeChars: 200,
        contextAfterChars: 200,
        triggerDelayMs: 300,
        systemPromptTemplate: """
Rewrite the INPUT to fill in the content between the delimiters DELIM_L and DELIM_R. Focus on what should go between DELIM_L and DELIM_R, and use the rest only as context to match language, tone, style, format, and syntax.

INPUT:
\(AppSettings.inputPlaceholder)

Return only what should go between DELIM_L and DELIM_R:
""",
        useClipboardFallback: true,
        indicatorPlacement: .menuBar,
        rewriteShortcut: .defaultShortcut,
        apiKey: ""
    )

    init(
        provider: ProviderKind,
        model: String,
        customBaseURL: String,
        typedStart: String,
        typedEnd: String,
        spokenStart: String,
        spokenEnd: String,
        typedEnabled: Bool,
        spokenEnabled: Bool,
        disabledApps: [String],
        sendContext: Bool,
        contextBeforeChars: Int,
        contextAfterChars: Int,
        triggerDelayMs: Int,
        systemPromptTemplate: String,
        useClipboardFallback: Bool,
        indicatorPlacement: IndicatorPlacement,
        rewriteShortcut: ShortcutBinding,
        apiKey: String = ""
    ) {
        self.provider = provider
        self.model = model
        self.customBaseURL = customBaseURL
        self.typedStart = typedStart
        self.typedEnd = typedEnd
        self.spokenStart = spokenStart
        self.spokenEnd = spokenEnd
        self.typedEnabled = typedEnabled
        self.spokenEnabled = spokenEnabled
        self.disabledApps = disabledApps
        self.sendContext = sendContext
        self.contextBeforeChars = max(0, contextBeforeChars)
        self.contextAfterChars = max(0, contextAfterChars)
        self.triggerDelayMs = max(0, triggerDelayMs)
        self.systemPromptTemplate = systemPromptTemplate
        self.useClipboardFallback = useClipboardFallback
        self.indicatorPlacement = indicatorPlacement
        self.rewriteShortcut = rewriteShortcut
        self.apiKey = apiKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        self.init(
            provider: try c.decodeIfPresent(ProviderKind.self, forKey: .provider) ?? d.provider,
            model: try c.decodeIfPresent(String.self, forKey: .model) ?? d.model,
            customBaseURL: try c.decodeIfPresent(String.self, forKey: .customBaseURL) ?? d.customBaseURL,
            typedStart: try c.decodeIfPresent(String.self, forKey: .typedStart) ?? d.typedStart,
            typedEnd: try c.decodeIfPresent(String.self, forKey: .typedEnd) ?? d.typedEnd,
            spokenStart: try c.decodeIfPresent(String.self, forKey: .spokenStart) ?? d.spokenStart,
            spokenEnd: try c.decodeIfPresent(String.self, forKey: .spokenEnd) ?? d.spokenEnd,
            typedEnabled: try c.decodeIfPresent(Bool.self, forKey: .typedEnabled) ?? d.typedEnabled,
            spokenEnabled: try c.decodeIfPresent(Bool.self, forKey: .spokenEnabled) ?? d.spokenEnabled,
            disabledApps: try c.decodeIfPresent([String].self, forKey: .disabledApps) ?? d.disabledApps,
            sendContext: try c.decodeIfPresent(Bool.self, forKey: .sendContext) ?? d.sendContext,
            contextBeforeChars: try c.decodeIfPresent(Int.self, forKey: .contextBeforeChars) ?? d.contextBeforeChars,
            contextAfterChars: try c.decodeIfPresent(Int.self, forKey: .contextAfterChars) ?? d.contextAfterChars,
            triggerDelayMs: try c.decodeIfPresent(Int.self, forKey: .triggerDelayMs) ?? d.triggerDelayMs,
            systemPromptTemplate: try c.decodeIfPresent(String.self, forKey: .systemPromptTemplate) ?? d.systemPromptTemplate,
            useClipboardFallback: try c.decodeIfPresent(Bool.self, forKey: .useClipboardFallback) ?? d.useClipboardFallback,
            indicatorPlacement: try c.decodeIfPresent(IndicatorPlacement.self, forKey: .indicatorPlacement) ?? d.indicatorPlacement,
            rewriteShortcut: try c.decodeIfPresent(ShortcutBinding.self, forKey: .rewriteShortcut) ?? d.rewriteShortcut,
            apiKey: try c.decodeIfPresent(String.self, forKey: .apiKey) ?? d.apiKey
        )
    }
}

struct TriggerMatch: Equatable {
    var prompt: String
    var range: Range<String.Index>
    var signature: String
}

struct TriggerEngine {
    static func calcLatestTrigger(in text: String, settings: AppSettings, source: String) -> TriggerMatch {
        if settings.typedEnabled {
            let typed = calcTypedTrigger(
                in: text,
                start: settings.typedStart,
                end: settings.typedEnd,
                source: source
            )
            if typed.prompt.isEmpty == false {
                return typed
            }
        }

        if settings.spokenEnabled {
            let spoken = calcSpokenTrigger(
                in: text,
                start: settings.spokenStart,
                end: settings.spokenEnd,
                source: source
            )
            if spoken.prompt.isEmpty == false {
                return spoken
            }
        }

        return TriggerMatch(prompt: "", range: text.startIndex..<text.startIndex, signature: "")
    }

    private static func calcTypedTrigger(in text: String, start: String, end: String, source: String) -> TriggerMatch {
        if start.isEmpty || end.isEmpty {
            return TriggerMatch(prompt: "", range: text.startIndex..<text.startIndex, signature: "")
        }
        if start == end {
            return TriggerMatch(prompt: "", range: text.startIndex..<text.startIndex, signature: "")
        }

        guard let fullRange = calcLatestClosedTypedRange(in: text, start: start, end: end) else {
            return TriggerMatch(prompt: "", range: text.startIndex..<text.startIndex, signature: "")
        }

        let startEnd = text.range(of: start, range: fullRange.lowerBound..<fullRange.upperBound)!
        let endStart = text.range(of: end, options: .backwards, range: fullRange.lowerBound..<fullRange.upperBound)!
        let inner = text[startEnd.upperBound..<endStart.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if inner.isEmpty {
            return TriggerMatch(prompt: "", range: text.startIndex..<text.startIndex, signature: "")
        }

        let key = "\(source)|typed|\(text.distance(from: text.startIndex, to: fullRange.lowerBound))|\(text.distance(from: text.startIndex, to: fullRange.upperBound))|\(inner)"
        return TriggerMatch(prompt: inner, range: fullRange, signature: key)
    }

    private static func calcSpokenTrigger(in text: String, start: String, end: String, source: String) -> TriggerMatch {
        let s = start.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let e = end.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty || e.isEmpty {
            return TriggerMatch(prompt: "", range: text.startIndex..<text.startIndex, signature: "")
        }

        let lower = text.lowercased()
        guard let endRange = calcLastBoundedRange(in: lower, token: e) else {
            return TriggerMatch(prompt: "", range: text.startIndex..<text.startIndex, signature: "")
        }

        let prefix = lower[..<endRange.lowerBound]
        guard let startRange = calcLastBoundedRange(in: String(prefix), token: s) else {
            return TriggerMatch(prompt: "", range: text.startIndex..<text.startIndex, signature: "")
        }

        let inner = text[startRange.upperBound..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if inner.isEmpty {
            return TriggerMatch(prompt: "", range: text.startIndex..<text.startIndex, signature: "")
        }

        let fullRange = startRange.lowerBound..<endRange.upperBound
        let key = "\(source)|spoken|\(text.distance(from: text.startIndex, to: fullRange.lowerBound))|\(text.distance(from: text.startIndex, to: fullRange.upperBound))|\(inner)"
        return TriggerMatch(prompt: inner, range: fullRange, signature: key)
    }

    private static func calcLastBoundedRange(in text: String, token: String) -> Range<String.Index>? {
        var scan = text.startIndex..<text.endIndex
        var last: Range<String.Index>?

        while let found = text.range(of: token, options: [], range: scan) {
            if isBounded(in: text, range: found) {
                last = found
            }
            scan = found.upperBound..<text.endIndex
        }

        return last
    }

    private static func isBounded(in text: String, range: Range<String.Index>) -> Bool {
        let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : " "
        let after = range.upperBound < text.endIndex ? text[range.upperBound] : " "
        return isWordChar(before) == false && isWordChar(after) == false
    }

    private static func isWordChar(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
    }

    private static func calcLatestClosedTypedRange(in text: String, start: String, end: String) -> Range<String.Index>? {
        enum TokenKind {
            case start
            case end
        }

        var scan = text.startIndex
        var starts: [Range<String.Index>] = []
        var latest: Range<String.Index>?

        while scan < text.endIndex {
            let window = scan..<text.endIndex
            let nextStart = text.range(of: start, range: window)
            let nextEnd = text.range(of: end, range: window)

            let kind: TokenKind
            let token: Range<String.Index>

            if let s = nextStart, let e = nextEnd {
                if s.lowerBound <= e.lowerBound {
                    kind = .start
                    token = s
                } else {
                    kind = .end
                    token = e
                }
            } else if let s = nextStart {
                kind = .start
                token = s
            } else if let e = nextEnd {
                kind = .end
                token = e
            } else {
                break
            }

            switch kind {
            case .start:
                starts.append(token)
            case .end:
                if let open = starts.popLast() {
                    latest = open.lowerBound..<token.upperBound
                }
            }

            scan = token.upperBound
        }

        return latest
    }
}
