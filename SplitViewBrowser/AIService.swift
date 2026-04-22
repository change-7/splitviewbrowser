import Foundation

struct AIService: Identifiable, Codable, Hashable {
    static let chatGPT = AIService(
        id: "builtin-chatgpt",
        title: "ChatGPT",
        urlString: "https://chatgpt.com/",
        isBuiltIn: true
    )
    static let gemini = AIService(
        id: "builtin-gemini",
        title: "Gemini",
        urlString: "https://gemini.google.com/",
        isBuiltIn: true
    )
    static let perplexity = AIService(
        id: "builtin-perplexity",
        title: "Perplexity",
        urlString: "https://www.perplexity.ai/",
        isBuiltIn: true
    )
    static let claude = AIService(
        id: "builtin-claude",
        title: "Claude",
        urlString: "https://claude.ai/new",
        isBuiltIn: true
    )
    static let grok = AIService(
        id: "builtin-grok",
        title: "Grok",
        urlString: "https://grok.com/",
        isBuiltIn: true
    )
    static let builtInServices: [AIService] = [.chatGPT, .gemini, .perplexity, .claude, .grok]

    let id: String
    let title: String
    let urlString: String
    let isBuiltIn: Bool

    var homeURL: URL {
        URL(string: urlString) ?? URL(string: "https://chatgpt.com/")!
    }

    var authRedirectHostSuffixes: [String] {
        switch id {
        case AIService.perplexity.id:
            return trustedHostSuffixes + ["pplx.ai"]
        case AIService.grok.id:
            return trustedHostSuffixes + ["twitter.com", "t.co"]
        default:
            return trustedHostSuffixes
        }
    }

    var trustedHostSuffixes: [String] {
        switch id {
        case AIService.chatGPT.id:
            // ChatGPT account flows can bounce through Google-hosted OAuth pages
            // before returning to OpenAI. Keep those redirects inside the same
            // WKWebView session so the final callback can resolve correctly.
            return [
                "chatgpt.com",
                "openai.com",
                "google.com",
                "googleusercontent.com",
                "gstatic.com"
            ]
        case AIService.gemini.id:
            return ["gemini.google.com", "google.com"]
        case AIService.perplexity.id:
            // Perplexity Google sign-in often navigates the main frame directly
            // into Google's OAuth flow instead of keeping everything in a popup.
            return [
                "perplexity.ai",
                "accounts.google.com",
                "myaccount.google.com",
                "google.com",
                "googleusercontent.com",
                "googleapis.com",
                "gstatic.com"
            ]
        case AIService.claude.id:
            // Claude sometimes redirects through auth or Cloudflare challenge hosts
            // before returning to claude.ai. Keep those checks inside the panel so
            // the verification can complete in the same WKWebView session.
            return [
                "claude.ai",
                "anthropic.com",
                "challenges.cloudflare.com",
                "accounts.google.com",
                "oauth.googleusercontent.com",
                "myaccount.google.com"
            ]
        case AIService.grok.id:
            // Grok can also redirect the current page into Google's hosted
            // account chooser before returning through x.com / x.ai.
            return [
                "grok.com",
                "x.ai",
                "x.com",
                "accounts.google.com",
                "myaccount.google.com",
                "google.com",
                "googleusercontent.com",
                "googleapis.com",
                "gstatic.com"
            ]
        default:
            guard let host = homeURL.host?.lowercased(), !host.isEmpty else { return [] }
            return [host]
        }
    }

    func trustsHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        return trustedHostSuffixes.contains { suffix in
            normalizedHost == suffix || normalizedHost.hasSuffix(".\(suffix)")
        }
    }

    func trustsAuthRedirectHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        return authRedirectHostSuffixes.contains { suffix in
            normalizedHost == suffix || normalizedHost.hasSuffix(".\(suffix)")
        }
    }

    static func defaultPanelServiceIDs(count: Int) -> [String] {
        guard count > 0, !builtInServices.isEmpty else { return [] }
        return (0 ..< count).map { index in
            builtInServices[index % builtInServices.count].id
        }
    }

    static func legacyID(from value: String) -> String? {
        switch value {
        case "chatgpt":
            return AIService.chatGPT.id
        case "gemini":
            return AIService.gemini.id
        case "perplexity":
            return AIService.perplexity.id
        case "claude":
            return AIService.claude.id
        case "grok":
            return AIService.grok.id
        default:
            return nil
        }
    }

    static func normalizeURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        components.scheme = scheme
        return components.url?.absoluteString
    }
}
