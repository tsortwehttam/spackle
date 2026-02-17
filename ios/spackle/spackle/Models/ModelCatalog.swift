import Foundation

enum ModelCatalog {
    static let openAI = [
        "gpt-5.2",
        "gpt-5.2-pro",
        "gpt-5.2-codex",
        "gpt-5.2-chat-latest",
        "gpt-5-mini",
        "gpt-5-nano",
        "gpt-4.1"
    ]

    static let anthropic = [
        "claude-sonnet-4-5-20250929",
        "claude-haiku-4-5-20251001",
        "claude-opus-4-5-20251101",
        "claude-sonnet-4-5",
        "claude-haiku-4-5",
        "claude-opus-4-5"
    ]

    static let openRouterPopular = [
        "minimax/minimax-m2.5",
        "moonshotai/kimi-k2.5",
        "google/gemini-3-flash-preview",
        "deepseek/deepseek-v3.2",
        "z-ai/glm-5",
        "anthropic/claude-sonnet-4.5",
        "x-ai/grok-4.1-fast",
        "anthropic/claude-opus-4.6"
    ]

    static func calcOptions(provider: ProviderKind) -> [String] {
        switch provider {
        case .openAI:
            return openAI
        case .anthropic:
            return anthropic
        case .openRouter:
            return openRouterPopular
        case .custom:
            return []
        }
    }
}
