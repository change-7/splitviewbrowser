import Foundation

enum AutoCopySupportLevel: String, Codable, CaseIterable, Identifiable {
    case supported
    case limited
    case unsupported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supported:
            return "지원"
        case .limited:
            return "제한적"
        case .unsupported:
            return "미지원"
        }
    }
}

struct AutoCopyRule: Codable, Hashable {
    var composerSelectors: [String]
    var sendButtonSelectors: [String]
    var sendPattern: String
    var enableEnterKey: Bool
}

struct AutoCopySiteProfile: Codable, Hashable {
    var supportLevel: AutoCopySupportLevel
    var composerSelectors: [String]?
    var sendButtonSelectors: [String]?
    var sendPattern: String?
    var enableEnterKey: Bool?

    init(
        supportLevel: AutoCopySupportLevel,
        composerSelectors: [String]? = nil,
        sendButtonSelectors: [String]? = nil,
        sendPattern: String? = nil,
        enableEnterKey: Bool? = nil
    ) {
        self.supportLevel = supportLevel
        self.composerSelectors = composerSelectors
        self.sendButtonSelectors = sendButtonSelectors
        self.sendPattern = sendPattern
        self.enableEnterKey = enableEnterKey
    }

    func resolved(over defaults: AutoCopyRule?) -> AutoCopyResolvedConfiguration {
        guard supportLevel != .unsupported else {
            return AutoCopyResolvedConfiguration(supportLevel: .unsupported, rule: nil)
        }

        guard let defaults else {
            return AutoCopyResolvedConfiguration(supportLevel: supportLevel, rule: nil)
        }

        var merged = defaults
        let deduplicated = { (values: [String]) -> [String] in
            var seen = Set<String>()
            return values.compactMap { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let key = trimmed.lowercased()
                guard !seen.contains(key) else { return nil }
                seen.insert(key)
                return trimmed
            }
        }

        if let composerSelectors, !composerSelectors.isEmpty {
            merged.composerSelectors = deduplicated(composerSelectors + merged.composerSelectors)
        }
        if let sendButtonSelectors, !sendButtonSelectors.isEmpty {
            merged.sendButtonSelectors = deduplicated(sendButtonSelectors + merged.sendButtonSelectors)
        }
        if let sendPattern, !sendPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.sendPattern = sendPattern
        }
        if let enableEnterKey {
            merged.enableEnterKey = enableEnterKey
        }

        return AutoCopyResolvedConfiguration(supportLevel: supportLevel, rule: merged)
    }
}

struct AutoCopyResolvedConfiguration: Hashable {
    var supportLevel: AutoCopySupportLevel
    var rule: AutoCopyRule?
}

enum AutoCopyCatalog {
    private static let defaultSendPattern = "send|submit|ask|arrow up|전송|보내기|질문|제출"

    static func defaultConfiguration(for service: AIService) -> AutoCopyResolvedConfiguration {
        let host = service.homeURL.host?.lowercased() ?? ""

        if host.contains("openai.com") {
            return AutoCopyResolvedConfiguration(
                supportLevel: .supported,
                rule: AutoCopyRule(
                    composerSelectors: [
                        "textarea#prompt-textarea",
                        "div#prompt-textarea[contenteditable='true']",
                        "textarea[data-id='root']",
                        "textarea[placeholder*='message' i]",
                        "div[contenteditable='true'][role='textbox']",
                        "[role='textbox'][aria-multiline='true']"
                    ],
                    sendButtonSelectors: [
                        "button#composer-submit-button",
                        "button[data-testid='send-button']",
                        "button[aria-label*='Send' i]",
                        "button[type='submit']"
                    ],
                    sendPattern: defaultSendPattern,
                    enableEnterKey: true
                )
            )
        }

        if host.contains("perplexity.ai") {
            return AutoCopyResolvedConfiguration(
                supportLevel: .supported,
                rule: AutoCopyRule(
                    composerSelectors: [
                        "div#ask-input[contenteditable='true']",
                        "textarea[placeholder*='Ask' i]",
                        "textarea",
                        "div[contenteditable='true'][role='textbox']",
                        "div[contenteditable='true']"
                    ],
                    sendButtonSelectors: [
                        "button[aria-label*='제출' i]",
                        "button[aria-label*='Submit' i]",
                        "button[aria-label*='Ask' i]",
                        "button[type='submit']"
                    ],
                    sendPattern: defaultSendPattern,
                    enableEnterKey: true
                )
            )
        }

        if host.contains("gemini.google.com") {
            return AutoCopyResolvedConfiguration(
                supportLevel: .limited,
                rule: AutoCopyRule(
                    composerSelectors: [
                        "rich-textarea div[contenteditable='true']",
                        "div.ql-editor[contenteditable='true']",
                        "div[contenteditable='true'][role='textbox']",
                        "div[contenteditable='true']",
                        "textarea"
                    ],
                    sendButtonSelectors: [
                        "button[aria-label*='메시지 보내기' i]",
                        "button[aria-label*='Send' i]",
                        "button[aria-label*='Gemini' i]",
                        "button[type='submit']"
                    ],
                    sendPattern: defaultSendPattern,
                    enableEnterKey: true
                )
            )
        }

        if host.contains("grok.com") {
            return AutoCopyResolvedConfiguration(
                supportLevel: .supported,
                rule: AutoCopyRule(
                    composerSelectors: [
                        "div.tiptap.ProseMirror[contenteditable='true']",
                        "textarea[placeholder*='Ask' i]",
                        "textarea[placeholder*='anything' i]",
                        "textarea[placeholder*='Grok' i]",
                        "textarea[aria-label*='Grok' i]",
                        "textarea[aria-label*='message' i]",
                        "textarea",
                        "div[contenteditable='true'][role='textbox']",
                        "div[contenteditable='true']"
                    ],
                    sendButtonSelectors: [
                        "button[data-testid*='send']",
                        "button[aria-label*='Send' i]",
                        "button[aria-label*='Submit' i]",
                        "button[title*='Send' i]",
                        "button[type='submit']"
                    ],
                    sendPattern: defaultSendPattern,
                    enableEnterKey: true
                )
            )
        }

        return AutoCopyResolvedConfiguration(
            supportLevel: .unsupported,
            rule: nil
        )
    }

    static func defaultProfile(for service: AIService) -> AutoCopySiteProfile {
        let config = defaultConfiguration(for: service)
        return AutoCopySiteProfile(supportLevel: config.supportLevel)
    }
}
