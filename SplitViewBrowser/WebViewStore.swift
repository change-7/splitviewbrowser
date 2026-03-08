import AppKit
import Foundation
import WebKit

@MainActor
final class WebViewStore: NSObject, ObservableObject {
    static let copyOnSendMessageName = "splitViewCopyOnSend"
    static let answerCopyCaptureMessageName = "splitViewAnswerCopyCapture"
    private static let sharedWebsiteDataStore = WKWebsiteDataStore.default()

    struct RuntimeIssue: Identifiable, Hashable {
        enum Kind: String, Hashable {
            case loadFailed
            case processTerminated
        }

        let id = UUID()
        let kind: Kind
        let title: String
        let message: String
        let urlString: String?
        let isRecoverable: Bool
    }

    private struct AutoCopyPagePayload: Codable {
        var enabled: Bool
        var supportLevel: AutoCopySupportLevel
        var rule: AutoCopyRule?
    }

    struct ComposerSendResult: Hashable {
        let inserted: Bool
        let submitted: Bool
        let message: String
    }

    struct ComposerPrepareResult: Hashable {
        let focused: Bool
        let message: String
    }

    struct AnswerCopyClickResult: Hashable {
        let clicked: Bool
        let targetOffset: Int
        let message: String
    }

    private struct ComposerSendThrottle: Hashable {
        let text: String
        let submit: Bool
        let timestamp: Date
    }

    struct AssistantCopiedResponse: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let urlString: String?
        let capturedAt: Date
    }

    let webView: WKWebView

    @Published private(set) var copyOnSendEnabled = true
    @Published private(set) var currentURLString = ""
    @Published private(set) var isLoadingPage = false
    @Published private(set) var runtimeIssue: RuntimeIssue?
    @Published private(set) var autoCopySupportLevel: AutoCopySupportLevel = .unsupported
    @Published private(set) var lastCopiedAssistantResponse: AssistantCopiedResponse?

    var isAutoCopySupported: Bool {
        autoCopySupportLevel != .unsupported
    }

    private var hasLoadedHome = false
    private var observations: [NSKeyValueObservation] = []
    private let navigationProxy = NavigationProxy()
    private let copyOnSendBridge = CopyOnSendBridge()
    private let answerCopyCaptureBridge = AnswerCopyCaptureBridge()
    private let logger = AppLogger.shared
    private var hasPreparedForRelease = false
    private var autoCopyConfiguration = AutoCopyResolvedConfiguration(supportLevel: .unsupported, rule: nil)
    private var currentService: AIService?
    private var lastComposerSendThrottle: ComposerSendThrottle?
    private var lastAppliedAutoCopyPayloadSignature: String?
    private weak var cachedEmbeddedScrollView: NSScrollView?

    override init() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        configuration.websiteDataStore = Self.sharedWebsiteDataStore

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        configureWebViewScrollBehavior()

        copyOnSendBridge.handleText = { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(trimmed, forType: .string)
        }
        answerCopyCaptureBridge.handlePayload = { [weak self] payloadJSON in
            guard let self else { return }
            struct Payload: Decodable {
                let text: String?
                let url: String?
                let host: String?
                let fallbackClipboard: Bool?
            }

            guard let data = payloadJSON.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                return
            }

            let host = (payload.host ?? "").lowercased()
            let trimmed = (payload.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let preferClipboard = host.contains("gemini.google.com") || host.contains("grok.com")

            if preferClipboard {
                self.captureCopiedAnswerFromClipboard(
                    urlString: payload.url,
                    host: payload.host,
                    fallbackText: trimmed.isEmpty ? nil : trimmed
                )
                return
            }

            if !trimmed.isEmpty {
                self.publishCopiedAssistantResponse(text: trimmed, urlString: payload.url, source: "dom")
                return
            }

            if payload.fallbackClipboard == true {
                self.captureCopiedAnswerFromClipboard(urlString: payload.url, host: payload.host, fallbackText: nil)
            }
        }

        contentController.add(copyOnSendBridge, name: Self.copyOnSendMessageName)
        contentController.add(answerCopyCaptureBridge, name: Self.answerCopyCaptureMessageName)
        contentController.addUserScript(
            WKUserScript(
                source: Self.copyOnSendScriptSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        navigationProxy.openExternal = { url in
            NSWorkspace.shared.open(url)
        }
        navigationProxy.didStartNavigation = { [weak self] url in
            guard let self else { return }
            self.isLoadingPage = true
            self.runtimeIssue = nil
            self.currentURLString = url?.absoluteString ?? self.currentURLString
            self.lastAppliedAutoCopyPayloadSignature = nil
        }
        navigationProxy.didCommitNavigation = { [weak self] url in
            guard let self else { return }
            self.currentURLString = url?.absoluteString ?? self.currentURLString
        }
        navigationProxy.didFinishNavigation = { [weak self] in
            guard let self else { return }
            self.isLoadingPage = false
            self.runtimeIssue = nil
            self.configureWebViewScrollBehavior()
            self.applyHostLayoutFixes()
            self.syncAutoCopySettingsToPage()
        }
        navigationProxy.didFailNavigation = { [weak self] url, error in
            self?.handleNavigationError(url: url, error: error)
        }
        navigationProxy.didTerminateContentProcess = { [weak self] in
            self?.handleContentProcessTermination()
        }

        webView.navigationDelegate = navigationProxy
        webView.uiDelegate = navigationProxy

        observeNavigationState()
    }

    private func publishCopiedAssistantResponse(text: String, urlString: String?, source: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lastCopiedAssistantResponse = AssistantCopiedResponse(
            text: trimmed,
            urlString: urlString,
            capturedAt: Date()
        )
        logger.log(.info, category: "Collection", "Detected page answer copy via \(source) (\(trimmed.count) chars)")
    }

    private func captureCopiedAnswerFromClipboard(
        urlString: String?,
        host: String?,
        fallbackText: String?
    ) {
        if publishCopiedAnswerFromClipboardIfAvailable(urlString: urlString) {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for attempt in 0..<4 {
                let delay = 0.12 + (Double(attempt) * 0.08)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if self.publishCopiedAnswerFromClipboardIfAvailable(urlString: urlString) {
                    return
                }
            }

            if let fallbackText, !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.publishCopiedAssistantResponse(text: fallbackText, urlString: urlString, source: "dom-fallback")
                return
            }
            self.logger.log(.warning, category: "Collection", "Clipboard fallback failed for host \(host ?? "unknown")")
        }
    }

    @discardableResult
    private func publishCopiedAnswerFromClipboardIfAvailable(urlString: String?) -> Bool {
        let clipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clipboardText.isEmpty else { return false }
        publishCopiedAssistantResponse(text: clipboardText, urlString: urlString, source: "clipboard")
        return true
    }

    private static func encodePayloadJSONString<T: Encodable>(_ payload: T) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func goHomeIfNeeded(service: AIService) {
        guard !hasLoadedHome else { return }
        goHome(service: service)
    }

    func goHome(service: AIService) {
        currentService = service
        hasLoadedHome = true
        clearRuntimeIssue()
        isLoadingPage = true
        currentURLString = service.homeURL.absoluteString
        logger.log(.info, category: "WebView", "Load home: \(service.title)")
        webView.load(URLRequest(url: service.homeURL))
    }

    func reload() {
        clearRuntimeIssue()
        isLoadingPage = true
        webView.reload()
    }

    func retryCurrentOrHome(service: AIService) {
        clearRuntimeIssue()
        if let url = webView.url {
            isLoadingPage = true
            currentURLString = url.absoluteString
            webView.load(URLRequest(url: url))
            return
        }
        goHome(service: service)
    }

    func dismissRuntimeIssue() {
        runtimeIssue = nil
    }

    func setAutoCopyConfiguration(_ configuration: AutoCopyResolvedConfiguration) {
        guard autoCopyConfiguration != configuration else { return }
        autoCopyConfiguration = configuration
        autoCopySupportLevel = configuration.supportLevel
        syncAutoCopySettingsToPage()
    }

    func setCopyOnSendEnabled(_ enabled: Bool) {
        guard copyOnSendEnabled != enabled else { return }
        copyOnSendEnabled = enabled
        syncAutoCopySettingsToPage()
    }

    func prepareForRelease() {
        guard !hasPreparedForRelease else { return }
        hasPreparedForRelease = true
        lastAppliedAutoCopyPayloadSignature = nil
        cachedEmbeddedScrollView = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.copyOnSendMessageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.answerCopyCaptureMessageName)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        observations.removeAll()
        logger.log(.info, category: "WebView", "Prepared web view store for release")
    }

    func sendTextToComposer(_ text: String, submit: Bool, completion: @escaping (Result<ComposerSendResult, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let error = NSError(
                domain: "SplitViewBrowser.WebViewStore",
                code: 1100,
                userInfo: [NSLocalizedDescriptionKey: "전송할 텍스트가 비어 있습니다."]
            )
            completion(.failure(error))
            return
        }

        let now = Date()
        if let last = lastComposerSendThrottle,
           last.text == trimmed,
           last.submit == submit,
           now.timeIntervalSince(last.timestamp) < 0.5
        {
            logger.log(.info, category: "Collection", "Skipped duplicate send request within throttle window")
            completion(.success(ComposerSendResult(inserted: true, submitted: false, message: "중복 전송 요청 무시")))
            return
        }
        lastComposerSendThrottle = ComposerSendThrottle(text: trimmed, submit: submit, timestamp: now)
        evaluateComposerSend(text: trimmed, submit: submit, completion: completion)
    }

    func prepareComposerForInput(completion: @escaping (Result<ComposerPrepareResult, Error>) -> Void) {
        struct PreparePayload: Encodable {
            let rule: AutoCopyRule?
        }

        let payload = PreparePayload(rule: autoCopyConfiguration.rule)
        guard let json = Self.encodePayloadJSONString(payload) else {
            let error = NSError(
                domain: "SplitViewBrowser.WebViewStore",
                code: 1104,
                userInfo: [NSLocalizedDescriptionKey: "입력창 준비 payload 생성에 실패했습니다."]
            )
            completion(.failure(error))
            return
        }

        let js = Self.composerPrepareScript(payloadJSON: json)
        webView.evaluateJavaScript(js) { [weak self] value, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.logger.log(.warning, category: "Collection", "Failed to execute prepare script: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                guard let resultJSON = value as? String,
                      let data = resultJSON.data(using: .utf8) else {
                    let error = NSError(
                        domain: "SplitViewBrowser.WebViewStore",
                        code: 1105,
                        userInfo: [NSLocalizedDescriptionKey: "입력창 준비 결과를 읽을 수 없습니다."]
                    )
                    completion(.failure(error))
                    return
                }

                struct Payload: Decodable {
                    let ok: Bool
                    let focused: Bool?
                    let reason: String?
                    let message: String?
                }

                do {
                    let payload = try JSONDecoder().decode(Payload.self, from: data)
                    guard payload.ok else {
                        let error = NSError(
                            domain: "SplitViewBrowser.WebViewStore",
                            code: 1106,
                            userInfo: [NSLocalizedDescriptionKey: payload.reason ?? "입력창을 찾지 못했습니다."]
                        )
                        completion(.failure(error))
                        return
                    }

                    completion(
                        .success(
                            ComposerPrepareResult(
                                focused: payload.focused ?? false,
                                message: payload.message ?? "입력창 준비 완료"
                            )
                        )
                    )
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func sendTextToComposer(_ text: String, submit: Bool) async -> Result<ComposerSendResult, Error> {
        await withCheckedContinuation { continuation in
            sendTextToComposer(text, submit: submit) { result in
                continuation.resume(returning: result)
            }
        }
    }

    func submitPreparedComposer(completion: @escaping (Result<ComposerSendResult, Error>) -> Void) {
        evaluateComposerSend(text: nil, submit: true, completion: completion)
    }

    func submitPreparedComposer() async -> Result<ComposerSendResult, Error> {
        await withCheckedContinuation { continuation in
            submitPreparedComposer { result in
                continuation.resume(returning: result)
            }
        }
    }

    func prepareComposerForInput() async -> Result<ComposerPrepareResult, Error> {
        await withCheckedContinuation { continuation in
            prepareComposerForInput { result in
                continuation.resume(returning: result)
            }
        }
    }

    func triggerAssistantAnswerCopy(
        targetOffset: Int = 0,
        completion: @escaping (Result<AnswerCopyClickResult, Error>) -> Void
    ) {
        triggerAssistantAnswerCopy(targetOffset: max(0, targetOffset), retryCount: 0, completion: completion)
    }

    func triggerAssistantAnswerCopy(targetOffset: Int = 0) async -> Result<AnswerCopyClickResult, Error> {
        await withCheckedContinuation { continuation in
            triggerAssistantAnswerCopy(targetOffset: targetOffset) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func triggerAssistantAnswerCopy(
        targetOffset: Int,
        retryCount: Int,
        completion: @escaping (Result<AnswerCopyClickResult, Error>) -> Void
    ) {
        struct CopyPayload: Encodable {
            let targetOffset: Int
        }

        let payload = CopyPayload(targetOffset: targetOffset)
        guard let json = Self.encodePayloadJSONString(payload) else {
            let error = NSError(
                domain: "SplitViewBrowser.WebViewStore",
                code: 1110,
                userInfo: [NSLocalizedDescriptionKey: "복사 payload 생성에 실패했습니다."]
            )
            completion(.failure(error))
            return
        }

        let js = Self.answerCopyButtonScript(payloadJSON: json)
        webView.evaluateJavaScript(js) { [weak self] value, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.logger.log(.warning, category: "Collection", "Failed to execute copy-button script: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                guard let resultJSON = value as? String,
                      let data = resultJSON.data(using: .utf8) else {
                    let error = NSError(
                        domain: "SplitViewBrowser.WebViewStore",
                        code: 1111,
                        userInfo: [NSLocalizedDescriptionKey: "복사 실행 결과를 읽을 수 없습니다."]
                    )
                    completion(.failure(error))
                    return
                }

                struct Payload: Decodable {
                    let ok: Bool
                    let clicked: Bool?
                    let targetOffset: Int?
                    let message: String?
                    let reason: String?
                    let retry: Bool?
                    let capturedText: String?
                    let url: String?
                }

                do {
                    let payload = try JSONDecoder().decode(Payload.self, from: data)
                    guard payload.ok else {
                        if payload.retry == true, retryCount < 1 {
                            self.logger.log(
                                .info,
                                category: "Collection",
                                "Copy-button script requested retry (attempt \(retryCount + 1))"
                            )
                            Task { @MainActor [weak self] in
                                try? await Task.sleep(nanoseconds: 200_000_000)
                                guard !Task.isCancelled else { return }
                                self?.triggerAssistantAnswerCopy(
                                    targetOffset: targetOffset,
                                    retryCount: retryCount + 1,
                                    completion: completion
                                )
                            }
                            return
                        }
                        let error = NSError(
                            domain: "SplitViewBrowser.WebViewStore",
                            code: 1112,
                            userInfo: [NSLocalizedDescriptionKey: payload.reason ?? "복사 버튼을 찾지 못했습니다."]
                        )
                        completion(.failure(error))
                        return
                    }

                    let directCapturedText = (payload.capturedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !directCapturedText.isEmpty {
                        let sourceURL = payload.url ?? self.webView.url?.absoluteString
                        self.publishCopiedAssistantResponse(
                            text: directCapturedText,
                            urlString: sourceURL,
                            source: "dom-direct"
                        )
                    }

                    completion(
                        .success(
                            AnswerCopyClickResult(
                                clicked: payload.clicked ?? false,
                                targetOffset: payload.targetOffset ?? targetOffset,
                                message: payload.message ?? "복사 버튼 클릭 완료"
                            )
                        )
                    )
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private func evaluateComposerSend(
        text: String?,
        submit: Bool,
        isSubmitRetry: Bool = false,
        completion: @escaping (Result<ComposerSendResult, Error>) -> Void
    ) {
        struct InjectPayload: Encodable {
            let text: String?
            let submit: Bool
            let rule: AutoCopyRule?
        }

        let payload = InjectPayload(text: text, submit: submit, rule: autoCopyConfiguration.rule)
        guard let json = Self.encodePayloadJSONString(payload) else {
            let error = NSError(
                domain: "SplitViewBrowser.WebViewStore",
                code: 1101,
                userInfo: [NSLocalizedDescriptionKey: "전송 payload 생성에 실패했습니다."]
            )
            completion(.failure(error))
            return
        }

        let js = Self.composerSendScript(payloadJSON: json)
        webView.evaluateJavaScript(js) { [weak self] value, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    let nsError = error as NSError
                    let detailKeys = [
                        "WKJavaScriptExceptionMessage",
                        "WKJavaScriptExceptionLineNumber",
                        "WKJavaScriptExceptionColumnNumber",
                        "WKJavaScriptExceptionSourceURL"
                    ]
                    let detail = detailKeys.compactMap { key -> String? in
                        guard let value = nsError.userInfo[key] else { return nil }
                        return "\(key)=\(value)"
                    }.joined(separator: " | ")

                    if detail.isEmpty {
                        self.logger.log(.warning, category: "Collection", "Failed to execute send script: \(error.localizedDescription)")
                    } else {
                        self.logger.log(
                            .warning,
                            category: "Collection",
                            "Failed to execute send script: \(error.localizedDescription) | \(detail)"
                        )
                    }
                    completion(.failure(error))
                    return
                }

                guard let resultJSON = value as? String,
                      let data = resultJSON.data(using: .utf8) else {
                    let error = NSError(
                        domain: "SplitViewBrowser.WebViewStore",
                        code: 1102,
                        userInfo: [NSLocalizedDescriptionKey: "전송 결과를 읽을 수 없습니다."]
                    )
                    completion(.failure(error))
                    return
                }

                struct Payload: Decodable {
                    let ok: Bool
                    let inserted: Bool?
                    let submitted: Bool?
                    let reason: String?
                    let message: String?
                    let stack: String?
                }

                do {
                    let payload = try JSONDecoder().decode(Payload.self, from: data)
                    guard payload.ok else {
                        if let reason = payload.reason, !reason.isEmpty {
                            self.logger.log(.warning, category: "Collection", "Send script reason: \(reason)")
                        }
                        if let stack = payload.stack, !stack.isEmpty {
                            self.logger.log(.warning, category: "Collection", "Send script detail: \(stack)")
                        }
                        let error = NSError(
                            domain: "SplitViewBrowser.WebViewStore",
                            code: 1103,
                            userInfo: [NSLocalizedDescriptionKey: payload.reason ?? "입력/전송에 실패했습니다."]
                        )
                        completion(.failure(error))
                        return
                    }

                    let result = ComposerSendResult(
                        inserted: payload.inserted ?? false,
                        submitted: payload.submitted ?? false,
                        message: payload.message ?? "완료"
                    )

                    if submit, !isSubmitRetry, result.inserted, !result.submitted {
                        self.retryDeferredComposerSubmit(completion: completion)
                        return
                    }

                    self.logger.log(
                        .info,
                        category: "Collection",
                        "Composer send result inserted=\(result.inserted) submitted=\(result.submitted)"
                    )
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private func retryDeferredComposerSubmit(
        attempt: Int = 0,
        completion: @escaping (Result<ComposerSendResult, Error>) -> Void
    ) {
        let retryDelays: [UInt64] = [180_000_000, 360_000_000, 700_000_000]
        guard attempt < retryDelays.count else {
            completion(
                .success(
                    ComposerSendResult(
                        inserted: true,
                        submitted: false,
                        message: "입력 완료 (전송 버튼 지연 활성화로 제출 실패)"
                    )
                )
            )
            return
        }

        let delay = retryDelays[attempt]
        logger.log(.info, category: "Collection", "Retrying delayed submit attempt \(attempt + 1)")

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }

            self.evaluateComposerSend(text: nil, submit: true, isSubmitRetry: true) { result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch result {
                    case let .success(retryResult):
                        if retryResult.submitted {
                            completion(
                                .success(
                                    ComposerSendResult(
                                        inserted: true,
                                        submitted: true,
                                        message: retryResult.message
                                    )
                                )
                            )
                        } else {
                            self.retryDeferredComposerSubmit(attempt: attempt + 1, completion: completion)
                        }
                    case .failure:
                        self.retryDeferredComposerSubmit(attempt: attempt + 1, completion: completion)
                    }
                }
            }
        }
    }

    private func clearRuntimeIssue() {
        runtimeIssue = nil
    }

    private func handleNavigationError(url: URL?, error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }

        isLoadingPage = false
        currentURLString = url?.absoluteString ?? currentURLString
        runtimeIssue = RuntimeIssue(
            kind: .loadFailed,
            title: "페이지를 불러오지 못했습니다",
            message: nsError.localizedDescription,
            urlString: url?.absoluteString,
            isRecoverable: true
        )
        logger.log(.warning, category: "WebView", "Load failed: \(url?.absoluteString ?? "unknown") - \(nsError.localizedDescription)")
    }

    private func handleContentProcessTermination() {
        isLoadingPage = false
        runtimeIssue = RuntimeIssue(
            kind: .processTerminated,
            title: "웹뷰 프로세스가 종료되었습니다",
            message: "메모리 압박 또는 사이트 스크립트 문제로 종료될 수 있습니다. 다시 시도하면 복구될 수 있습니다.",
            urlString: currentURLString.isEmpty ? nil : currentURLString,
            isRecoverable: true
        )
        logger.log(.warning, category: "WebView", "Web content process terminated")
    }

    private func observeNavigationState() {
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.currentURLString = webView.url?.absoluteString ?? ""
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.isLoadingPage = webView.isLoading
                }
            }
        ]
    }

    private func configureWebViewScrollBehavior() {
        guard let scrollView = resolvedEmbeddedScrollView() else { return }
        let host = webView.url?.host?.lowercased() ?? ""
        let hidesVerticalScroller = WebViewHostFixCatalog.hidesOuterVerticalScroller(for: host)
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = !hidesVerticalScroller
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = NSScroller.Style.overlay
        scrollView.horizontalScrollElasticity = NSScrollView.Elasticity.none
        scrollView.verticalScrollElasticity = hidesVerticalScroller ? NSScrollView.Elasticity.none : NSScrollView.Elasticity.automatic
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.scrollerInsets = NSEdgeInsetsZero
    }

    private func resolvedEmbeddedScrollView() -> NSScrollView? {
        if let cachedEmbeddedScrollView {
            return cachedEmbeddedScrollView
        }
        let scrollView = embeddedScrollView(in: webView)
        cachedEmbeddedScrollView = scrollView
        return scrollView
    }

    private func embeddedScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = embeddedScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }

    private func applyHostLayoutFixes() {
        guard let host = webView.url?.host?.lowercased(), !host.isEmpty else { return }
        guard let js = WebViewHostFixCatalog.layoutFixScript(for: host) else { return }
        webView.evaluateJavaScript(js) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.logger.log(
                    .warning,
                    category: "WebView",
                    "Failed to apply ChatGPT layout fix: \(error.localizedDescription)"
                )
            }
        }
    }

    private func syncAutoCopySettingsToPage() {
        let host = webView.url?.host ?? ""
        guard !host.isEmpty else { return }

        let payload = AutoCopyPagePayload(
            enabled: copyOnSendEnabled,
            supportLevel: autoCopyConfiguration.supportLevel,
            rule: autoCopyConfiguration.rule
        )
        guard let json = Self.encodePayloadJSONString(payload) else {
            return
        }

        let signature = "\(host)|\(json)"
        guard lastAppliedAutoCopyPayloadSignature != signature else { return }
        lastAppliedAutoCopyPayloadSignature = signature

        let js = """
        (() => {
          const payload = \(json);
          try {
            localStorage.setItem("split-view-copy-on-send-enabled:" + location.hostname, payload.enabled ? "1" : "0");
          } catch (_) {}
          if (typeof window.__splitViewApplyAutoCopyConfig === "function") {
            window.__splitViewApplyAutoCopyConfig(payload);
          }
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] _, error in
            guard error != nil else { return }
            Task { @MainActor [weak self] in
                self?.lastAppliedAutoCopyPayloadSignature = nil
            }
        }
    }

}

private final class NavigationProxy: NSObject, WKNavigationDelegate, WKUIDelegate {
    var openExternal: ((URL) -> Void)?
    var didStartNavigation: ((URL?) -> Void)?
    var didCommitNavigation: ((URL?) -> Void)?
    var didFinishNavigation: (() -> Void)?
    var didFailNavigation: ((URL?, Error) -> Void)?
    var didTerminateContentProcess: (() -> Void)?

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let shouldOpenExternally =
            navigationAction.navigationType == .linkActivated ||
            navigationAction.targetFrame == nil

        if shouldOpenExternally {
            openExternal?(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            openExternal?(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        didStartNavigation?(webView.url)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        didCommitNavigation?(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishNavigation?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        didFailNavigation?(webView.url, error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        didFailNavigation?(webView.url, error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        didTerminateContentProcess?()
    }
}

private final class CopyOnSendBridge: NSObject, WKScriptMessageHandler {
    var handleText: ((String) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        handleText?(text)
    }
}

private final class AnswerCopyCaptureBridge: NSObject, WKScriptMessageHandler {
    var handlePayload: ((String) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let payload = message.body as? String else { return }
        handlePayload?(payload)
    }
}
