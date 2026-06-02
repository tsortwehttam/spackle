import Combine
import SwiftUI

enum Language: String, CaseIterable, Identifiable, Codable {
    case en, zh
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zh: return "中文"
        }
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "SpackleLang")
            NotificationCenter.default.post(name: .SpackleLangDidChange, object: nil)
        }
    }

    private init() {
        language = Language(rawValue: UserDefaults.standard.string(forKey: "SpackleLang") ?? "") ?? .en
    }

    func tr(_ key: String) -> String {
        guard language == .zh else { return key }
        return Self.zhMap[key] ?? key
    }

    func tr(_ key: String, shortcut: String) -> String {
        tr(key).replacingOccurrences(of: "%@", with: shortcut)
    }

    static let zhMap: [String: String] = [
        "Settings": "设置",
        "Use AI to fill gaps in your writing anywhere on macOS.": "在 macOS 上任何地方用 AI 填补你的写作。",
        "How it Works": "使用方法",
        "Grant Accessibility": "授予辅助功能权限",
        "Granted": "已授权",
        "Required so Spackle can read and replace text in other apps.": "Spackle 需要此权限才能读取和替换其他应用中的文字。",
        "Choose your provider and model, then add your API key.": "选择 AI 供应商和模型，然后添加 API 密钥。",
        "API Key Set": "已设置 API 密钥",
        "Spackle is free software.": "Spackle 是免费软件。",
        "Leave us a tip": "给我们打赏",
        "Select text anywhere on your Mac, then press %@ to rewrite with AI.": "在 Mac 上任意位置选中文本，按 %@ 用 AI 改写。",
        "AI Provider": "AI 供应商",
        "Provider": "供应商",
        "OpenAI": "OpenAI",
        "Anthropic": "Anthropic",
        "OpenRouter": "OpenRouter",
        "Custom": "自定义",
        "Model": "模型",
        "API key": "API 密钥",
        "Base URL (e.g. http://localhost:1234/v1/chat/completions)": "基础地址（例如 http://localhost:1234/v1/chat/completions）",
        "Selection Rewrite": "选区改写",
        "Shortcut": "快捷键",
        "Typed Delimiters": "输入定界符",
        "Enable typed triggers": "启用输入触发",
        "Typed start": "起始定界符",
        "Typed end": "结束定界符",
        "Type a start and end delimiter in your text to trigger automatic replacement.": "在文本中输入起始和结束定界符，输入后自动触发 AI 改写。",
        "Spoken Delimiters": "语音定界符",
        "Enable spoken triggers": "启用语音触发",
        "Spoken start": "语音起始词",
        "Spoken end": "语音结束词",
        "If you're using dictation or transcription, spoken delimiters can trigger auto-replace.": "如果你在使用听写或语音转录，说出定界词即可触发自动替换。",
        "Rewrite Context": "改写上下文",
        "Chars before": "上文（字符数）",
        "Chars after": "下文（字符数）",
        "AI System Prompt": "AI 系统提示词",
        "Use {{SPACKLE_INPUT}} where the extracted text should be inserted.": "在需要插入提取文本的位置使用 {{SPACKLE_INPUT}}。",
        "Restore Default Prompt": "恢复默认提示词",
        "Behavior": "行为",
        "Trigger delay (ms)": "触发延迟（毫秒）",
        "Advanced": "高级",
        "Use clipboard fallback": "使用剪贴板回退",
        "Language": "语言",

        "Ready": "就绪",
        "Paused": "已暂停",
        "Accessibility Required": "需要辅助功能权限",
        "Spackling...": "处理中...",
        "About & Settings": "关于与设置",
        "Quit": "退出",
        "Resume Listening": "恢复监听",
        "Pause Listening": "暂停监听",
        "Select text first": "请先选择文本",
        "Canceled": "已取消",
        "API key missing": "缺少 API 密钥",
        "Request failed": "请求失败",

        "Privacy": "隐私",
        "Terms": "条款",

        // Tooltips
        "Choose the AI provider that processes your text.": "选择处理你的文本的 AI 供应商。要使用本地模型，请选择「自定义」并填写地址。",
        "The specific AI model to use. Type any model name for custom providers.": "要使用的具体 AI 模型。自定义供应商可手动输入模型名。",
        "Your API key for the selected provider.": "所选供应商的 API 密钥。",
        "Keyboard shortcut to rewrite the selected text in place.": "改写选中文本的快捷键。",
        "Wrap your prompt in delimiters (e.g. <<prompt>>) in any text field to trigger AI rewriting.": "用定界符包裹提示词（例如 <<帮我润色>>），Spackle 会自动替换定界符之间的内容。",
        "When using dictation, say the start and end words to trigger AI rewriting.": "使用听写时，说出起始词和结束词来触发 AI 改写。",
        "Send surrounding text as context for better AI results.": "将选中文本前后的内容也发送给 AI，帮助 AI 理解上下文以获得更好的改写效果。",
        "After typing the closing delimiter, wait this long before triggering. Prevents false triggers.": "输入结束定界符后等待多久再触发。稍长的延迟可以防止打字过程中的误触发。",
        "If direct text replacement fails (common in Electron apps), fall back to clipboard paste.": "如果直接替换文本失败（常见于 Electron 应用，如 VSCode），使用剪贴板粘贴作为兜底方案。",
        "Switch between English and Chinese.": "在英文和中文界面之间切换。",
    ]
}

extension Notification.Name {
    static let SpackleLangDidChange = Notification.Name("SpackleLangDidChange")
}
