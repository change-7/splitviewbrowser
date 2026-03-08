import Foundation

enum WebViewHostFixCatalog {
    static func hidesOuterVerticalScroller(for host: String) -> Bool {
        isChatGPTHost(host)
    }

    static func layoutFixScript(for host: String) -> String? {
        guard isChatGPTHost(host) else { return nil }
        return chatGPTLayoutFixScript
    }

    private static func isChatGPTHost(_ host: String) -> Bool {
        host.contains("openai.com") || host.contains("chatgpt.com")
    }

    private static let chatGPTLayoutFixScript = """
    (() => {
      const styleId = "__splitViewChatGPTLayoutFix";
      let style = document.getElementById(styleId);
      if (!style) {
        style = document.createElement("style");
        style.id = styleId;
        (document.head || document.documentElement).appendChild(style);
      }

      style.textContent = `
        html, body {
          width: 100% !important;
          height: 100% !important;
          min-height: 0 !important;
          max-width: 100% !important;
          overflow: hidden !important;
        }

        #__next,
        main,
        [role="main"] {
          width: 100% !important;
          height: 100% !important;
          min-height: 0 !important;
          max-width: 100% !important;
        }

        main,
        [role="main"],
        [data-testid*="conversation"],
        [class*="overflow-auto"],
        [class*="overflow-y-auto"] {
          scrollbar-width: none !important;
        }

        main::-webkit-scrollbar,
        [role="main"]::-webkit-scrollbar,
        [data-testid*="conversation"]::-webkit-scrollbar,
        [class*="overflow-auto"]::-webkit-scrollbar,
        [class*="overflow-y-auto"]::-webkit-scrollbar {
          width: 0 !important;
          height: 0 !important;
          display: none !important;
        }
      `;
    })();
    """
}
