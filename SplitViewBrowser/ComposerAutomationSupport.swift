import Foundation

struct ComposerAutomationRule: Codable, Hashable {
    var composerSelectors: [String]
    var sendButtonSelectors: [String]
    var sendPattern: String
    var enableEnterKey: Bool
}

enum ComposerAutomationCatalog {
    private static let defaultSendPattern = "send|submit|ask|arrow up|전송|보내기|질문|제출"

    static func defaultRule(for service: AIService) -> ComposerAutomationRule? {
        let host = service.homeURL.host?.lowercased() ?? ""

        if host.contains("openai.com") || host.contains("chatgpt.com") {
            return ComposerAutomationRule(
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
        }

        if host.contains("perplexity.ai") {
            return ComposerAutomationRule(
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
        }

        if host.contains("gemini.google.com") {
            return ComposerAutomationRule(
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
        }

        if host.contains("grok.com") {
            return ComposerAutomationRule(
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
        }

        return nil
    }
}
