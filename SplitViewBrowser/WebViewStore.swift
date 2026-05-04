import AppKit
import Foundation
import WebKit

@MainActor
final class WebViewStore: NSObject, ObservableObject {
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

    struct TemporaryChatClickResult: Hashable {
        let clicked: Bool
        let message: String
    }

    enum TemporaryChatState: Hashable {
        case unavailable
        case inactive
        case active
        case unknown

        var isActive: Bool {
            if case .active = self { return true }
            return false
        }
    }

    private struct ComposerSendThrottle: Hashable {
        let text: String
        let submit: Bool
        let timestamp: Date
    }

    struct AssistantCopiedResponse: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let capturedAt: Date
    }

    let webView: WKWebView

    @Published private(set) var currentURLString = ""
    @Published private(set) var isLoadingPage = false
    @Published private(set) var runtimeIssue: RuntimeIssue?
    @Published private(set) var lastCopiedAssistantResponse: AssistantCopiedResponse?
    @Published private(set) var temporaryChatState: TemporaryChatState = .unavailable
    @Published private(set) var popupWebView: WKWebView?

    private var hasLoadedHome = false
    private var observations: [NSKeyValueObservation] = []
    private let navigationProxy = NavigationProxy()
    private let popupNavigationProxy = NavigationProxy()
    private let answerCopyCaptureBridge = AnswerCopyCaptureBridge()
    private let logger = AppLogger.shared
    private var hasPreparedForRelease = false
    private var currentService: AIService?
    private var lastComposerSendThrottle: ComposerSendThrottle?
    private weak var cachedEmbeddedScrollView: NSScrollView?
    private var pendingClipboardBaselineChangeCount: Int?
    private var temporaryChatStateRefreshTask: Task<Void, Never>?
    private var inferredGeminiTemporaryChatActive = false
    private var isPanelActive = true

    override init() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        configuration.websiteDataStore = Self.sharedWebsiteDataStore

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        configureWebViewScrollBehavior()

        answerCopyCaptureBridge.handlePayload = { [weak self] payloadJSON in
            guard let self else { return }
            struct Payload: Decodable {
                let text: String?
                let host: String?
            }

            guard let data = payloadJSON.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                return
            }

            let host = (payload.host ?? "").lowercased()
            let trimmed = (payload.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.captureCopiedAnswerFromClipboard(
                host: host.isEmpty ? nil : payload.host,
                fallbackText: trimmed.isEmpty ? nil : trimmed
            )
        }

        contentController.add(answerCopyCaptureBridge, name: Self.answerCopyCaptureMessageName)
        contentController.addUserScript(
            WKUserScript(
                source: Self.answerCopyCaptureScriptSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        navigationProxy.openExternal = { url in
            PlatformURLOpener.open(url)
        }
        navigationProxy.shouldAllowInAppNavigation = { [weak self] url, navigationAction in
            self?.shouldAllowInAppNavigation(to: url, navigationAction: navigationAction) ?? false
        }
        navigationProxy.canOpenExternally = { url in
            Self.canOpenExternally(url)
        }
        navigationProxy.didStartNavigation = { [weak self] url in
            guard let self else { return }
            self.isLoadingPage = true
            self.runtimeIssue = nil
            self.currentURLString = url?.absoluteString ?? self.currentURLString
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
            if self.currentService?.id == AIService.chatGPT.id || self.currentService?.id == AIService.claude.id {
                self.refreshTemporaryChatStateIfSupported()
                self.startTemporaryChatStatePollingIfNeeded()
            } else if self.currentService?.id == AIService.gemini.id {
                self.temporaryChatState = .inactive
                self.temporaryChatStateRefreshTask?.cancel()
                self.temporaryChatStateRefreshTask = nil
            }
        }
        navigationProxy.didFailNavigation = { [weak self] url, error in
            self?.handleNavigationError(url: url, error: error)
        }
        navigationProxy.didTerminateContentProcess = { [weak self] in
            self?.handleContentProcessTermination()
        }

        popupNavigationProxy.openExternal = { url in
            PlatformURLOpener.open(url)
        }
        popupNavigationProxy.shouldAllowInAppNavigation = { [weak self] url, navigationAction in
            self?.shouldAllowInAppNavigation(to: url, navigationAction: navigationAction) ?? false
        }
        popupNavigationProxy.canOpenExternally = { url in
            Self.canOpenExternally(url)
        }
        popupNavigationProxy.didFailNavigation = { [weak self] url, error in
            self?.handleNavigationError(url: url, error: error)
        }
        popupNavigationProxy.didCloseWebView = { [weak self] closedWebView in
            guard let self else { return }
            if self.popupWebView === closedWebView {
                self.popupWebView = nil
            }
        }
        navigationProxy.createInAppPopupWebView = { [weak self] configuration in
            guard let self else {
                return WKWebView(frame: .zero, configuration: configuration)
            }
            let popup = self.makePopupWebView(configuration: configuration)
            self.popupWebView = popup
            return popup
        }

        webView.navigationDelegate = navigationProxy
        webView.uiDelegate = navigationProxy

        observeNavigationState()
    }

    private static func canOpenExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https", "mailto", "tel":
            return true
        default:
            return false
        }
    }

    private func shouldAllowInAppNavigation(to url: URL, navigationAction: WKNavigationAction) -> Bool {
        if url.scheme?.lowercased() == "about" {
            return true
        }

        switch navigationAction.navigationType {
        case .backForward, .reload:
            return true
        default:
            break
        }

        guard let host = url.host?.lowercased(), let currentService else {
            return false
        }

        return currentService.trustsHost(host)
    }

    private func publishCopiedAssistantResponse(text: String, source: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingClipboardBaselineChangeCount = nil

        lastCopiedAssistantResponse = AssistantCopiedResponse(
            text: trimmed,
            capturedAt: Date()
        )
        logger.log(.info, category: "Collection", "Detected page answer copy via \(source) (\(trimmed.count) chars)")
    }

    private func captureCopiedAnswerFromClipboard(
        host: String?,
        fallbackText: String?
    ) {
        if publishCopiedAnswerFromClipboardIfAvailable() {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for attempt in 0..<4 {
                let delay = 0.12 + (Double(attempt) * 0.08)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if self.publishCopiedAnswerFromClipboardIfAvailable() {
                    return
                }
            }

            if let fallbackText, !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.publishCopiedAssistantResponse(text: fallbackText, source: "dom-fallback")
                return
            }
            self.pendingClipboardBaselineChangeCount = nil
            self.logger.log(.warning, category: "Collection", "Clipboard fallback failed for host \(host ?? "unknown")")
        }
    }

    @discardableResult
    private func publishCopiedAnswerFromClipboardIfAvailable() -> Bool {
        if let baseline = pendingClipboardBaselineChangeCount,
           PlatformClipboard.changeCount <= baseline
        {
            return false
        }

        let clipboardText = PlatformClipboard.readString()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clipboardText.isEmpty else { return false }
        publishCopiedAssistantResponse(text: clipboardText, source: "clipboard")
        return true
    }

    private static func encodePayloadJSONString<T: Encodable>(_ payload: T) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private var currentComposerAutomationRule: ComposerAutomationRule? {
        guard let currentService else { return nil }
        return ComposerAutomationCatalog.defaultRule(for: currentService)
    }

    func goHomeIfNeeded(service: AIService) {
        guard !hasLoadedHome else { return }
        goHome(service: service)
    }

    func goHome(service: AIService) {
        currentService = service
        hasLoadedHome = true
        clearRuntimeIssue()
        inferredGeminiTemporaryChatActive = false
        temporaryChatState = Self.supportsTemporaryChat(service: service) ? .inactive : .unavailable
        if Self.supportsTemporaryChat(service: service) {
            startTemporaryChatStatePollingIfNeeded()
        } else {
            temporaryChatStateRefreshTask?.cancel()
            temporaryChatStateRefreshTask = nil
        }
        isLoadingPage = true
        currentURLString = service.homeURL.absoluteString
        logger.log(.info, category: "WebView", "Load home: \(service.title)")
        webView.load(URLRequest(url: service.homeURL))
    }

    func setPanelActive(_ isActive: Bool) {
        guard !hasPreparedForRelease else { return }
        guard isPanelActive != isActive else { return }

        isPanelActive = isActive
        if isActive {
            startTemporaryChatStatePollingIfNeeded()
        } else {
            temporaryChatStateRefreshTask?.cancel()
            temporaryChatStateRefreshTask = nil
        }
    }

    func reload() {
        clearRuntimeIssue()
        if let currentService, Self.supportsTemporaryChat(service: currentService) {
            temporaryChatState = currentService.id == AIService.gemini.id
                ? (inferredGeminiTemporaryChatActive ? .active : .inactive)
                : .unknown
            startTemporaryChatStatePollingIfNeeded()
        } else {
            temporaryChatStateRefreshTask?.cancel()
            temporaryChatStateRefreshTask = nil
        }
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

    func dismissPopupWebView() {
        popupWebView?.stopLoading()
        popupWebView?.navigationDelegate = nil
        popupWebView?.uiDelegate = nil
        popupWebView = nil
    }

    private func makePopupWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = popupNavigationProxy
        popup.uiDelegate = popupNavigationProxy
        return popup
    }

    func prepareForRelease() {
        guard !hasPreparedForRelease else { return }
        hasPreparedForRelease = true
        cachedEmbeddedScrollView = nil
        inferredGeminiTemporaryChatActive = false
        temporaryChatState = .unavailable
        temporaryChatStateRefreshTask?.cancel()
        temporaryChatStateRefreshTask = nil
        popupWebView?.stopLoading()
        popupWebView?.navigationDelegate = nil
        popupWebView?.uiDelegate = nil
        popupWebView = nil
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
            let rule: ComposerAutomationRule?
        }

        let payload = PreparePayload(rule: currentComposerAutomationRule)
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

    func triggerTemporaryChat(completion: @escaping (Result<TemporaryChatClickResult, Error>) -> Void) {
        triggerTemporaryChat(retryCount: 0, completion: completion)
    }

    func triggerTemporaryChat() async -> Result<TemporaryChatClickResult, Error> {
        await withCheckedContinuation { continuation in
            triggerTemporaryChat { result in
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

        pendingClipboardBaselineChangeCount = PlatformClipboard.changeCount
        let js = Self.answerCopyButtonScript(payloadJSON: json)
        webView.evaluateJavaScript(js) { [weak self] value, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.pendingClipboardBaselineChangeCount = nil
                    self.logger.log(.warning, category: "Collection", "Failed to execute copy-button script: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                guard let resultJSON = value as? String,
                      let data = resultJSON.data(using: .utf8) else {
                    self.pendingClipboardBaselineChangeCount = nil
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
                        self.pendingClipboardBaselineChangeCount = nil
                        completion(.failure(error))
                        return
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

    private func triggerTemporaryChat(
        retryCount: Int,
        completion: @escaping (Result<TemporaryChatClickResult, Error>) -> Void
    ) {
        let js = Self.temporaryChatButtonScriptSource
        webView.evaluateJavaScript(js) { [weak self] value, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.logger.log(.warning, category: "WebView", "Failed to execute temp-chat script: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                guard let resultJSON = value as? String,
                      let data = resultJSON.data(using: .utf8) else {
                    let error = NSError(
                        domain: "SplitViewBrowser.WebViewStore",
                        code: 1113,
                        userInfo: [NSLocalizedDescriptionKey: "임시채팅 실행 결과를 읽을 수 없습니다."]
                    )
                    completion(.failure(error))
                    return
                }

                struct Payload: Decodable {
                    let ok: Bool
                    let clicked: Bool?
                    let message: String?
                    let reason: String?
                    let retry: Bool?
                }

                do {
                    let payload = try JSONDecoder().decode(Payload.self, from: data)
                    guard payload.ok else {
                        if payload.retry == true, retryCount < 2 {
                            Task { @MainActor [weak self] in
                                try? await Task.sleep(nanoseconds: 250_000_000)
                                guard !Task.isCancelled else { return }
                                self?.triggerTemporaryChat(retryCount: retryCount + 1, completion: completion)
                            }
                            return
                        }

                        let error = NSError(
                            domain: "SplitViewBrowser.WebViewStore",
                            code: 1114,
                            userInfo: [NSLocalizedDescriptionKey: payload.reason ?? "임시채팅 버튼을 찾지 못했습니다."]
                        )
                        completion(.failure(error))
                        return
                    }

                    completion(
                        .success(
                            TemporaryChatClickResult(
                                clicked: payload.clicked ?? false,
                                message: payload.message ?? "임시채팅 버튼 클릭 완료"
                            )
                        )
                    )
                    if payload.clicked == true {
                        if self.currentService?.id == AIService.gemini.id {
                            self.inferredGeminiTemporaryChatActive.toggle()
                            self.temporaryChatState = self.inferredGeminiTemporaryChatActive ? .active : .inactive
                            self.scheduleTemporaryChatStateRefresh()
                        } else {
                            self.temporaryChatState = .unknown
                            self.scheduleTemporaryChatStateRefresh()
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private static func supportsTemporaryChat(service: AIService) -> Bool {
        service.id == AIService.chatGPT.id || service.id == AIService.gemini.id || service.id == AIService.claude.id || service.id == AIService.grok.id
    }

    private func refreshTemporaryChatStateIfSupported() {
        guard let currentService, Self.supportsTemporaryChat(service: currentService) else {
            temporaryChatState = .unavailable
            return
        }

        let isGeminiService = currentService.id == AIService.gemini.id

        let js = Self.temporaryChatStateScriptSource
        webView.evaluateJavaScript(js) { [weak self] value, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error != nil {
                    if isGeminiService {
                        self.temporaryChatState = self.inferredGeminiTemporaryChatActive ? .active : .inactive
                    } else if self.temporaryChatState == .unavailable || self.temporaryChatState == .unknown {
                        self.temporaryChatState = .inactive
                    }
                    return
                }

                guard let resultJSON = value as? String,
                      let data = resultJSON.data(using: .utf8) else {
                    return
                }

                struct Payload: Decodable {
                    let supported: Bool
                    let active: Bool?
                }

                guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                    return
                }

                guard payload.supported else {
                    if isGeminiService {
                        self.inferredGeminiTemporaryChatActive = false
                    }
                    self.temporaryChatState = .unavailable
                    return
                }

                if isGeminiService {
                    if let active = payload.active {
                        self.inferredGeminiTemporaryChatActive = active
                    }
                    self.temporaryChatState = self.inferredGeminiTemporaryChatActive ? .active : .inactive
                } else if let active = payload.active {
                    self.temporaryChatState = active ? .active : .inactive
                } else {
                    self.temporaryChatState = .unknown
                }
            }
        }
    }

    func refreshTemporaryChatStateNow() {
        refreshTemporaryChatStateIfSupported()
    }

    private func scheduleTemporaryChatStateRefresh() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled, self.isPanelActive else { return }
            self.refreshTemporaryChatStateIfSupported()
        }
    }

    private func startTemporaryChatStatePollingIfNeeded() {
        guard isPanelActive else {
            temporaryChatStateRefreshTask?.cancel()
            temporaryChatStateRefreshTask = nil
            return
        }

        guard let currentService, Self.supportsTemporaryChat(service: currentService), !hasPreparedForRelease else {
            temporaryChatStateRefreshTask?.cancel()
            temporaryChatStateRefreshTask = nil
            return
        }

        guard currentService.id == AIService.chatGPT.id
            || currentService.id == AIService.gemini.id
            || currentService.id == AIService.claude.id
            || currentService.id == AIService.grok.id else {
            temporaryChatStateRefreshTask?.cancel()
            temporaryChatStateRefreshTask = nil
            return
        }

        temporaryChatStateRefreshTask?.cancel()
        temporaryChatStateRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                guard let currentService = self.currentService,
                      Self.supportsTemporaryChat(service: currentService),
                      !self.hasPreparedForRelease else {
                    return
                }
                self.refreshTemporaryChatStateIfSupported()
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
            let rule: ComposerAutomationRule?
        }

        let payload = InjectPayload(text: text, submit: submit, rule: currentComposerAutomationRule)
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

}

private final class NavigationProxy: NSObject, WKNavigationDelegate, WKUIDelegate {
    var openExternal: ((URL) -> Void)?
    var shouldAllowInAppNavigation: ((URL, WKNavigationAction) -> Bool)?
    var canOpenExternally: ((URL) -> Bool)?
    var createInAppPopupWebView: ((WKWebViewConfiguration) -> WKWebView)?
    var didStartNavigation: ((URL?) -> Void)?
    var didCommitNavigation: ((URL?) -> Void)?
    var didFinishNavigation: (() -> Void)?
    var didFailNavigation: ((URL?, Error) -> Void)?
    var didTerminateContentProcess: (() -> Void)?
    var didCloseWebView: ((WKWebView) -> Void)?

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if shouldAllowInAppNavigation?(url, navigationAction) == true {
            decisionHandler(.allow)
            return
        }

        if canOpenExternally?(url) == true {
            openExternal?(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if shouldAllowInAppNavigation?(url, navigationAction) == true {
                return createInAppPopupWebView?(configuration)
            }

            if canOpenExternally?(url) == true {
                openExternal?(url)
            }
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        didCloseWebView?(webView)
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

private final class AnswerCopyCaptureBridge: NSObject, WKScriptMessageHandler {
    var handlePayload: ((String) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let payload = message.body as? String else { return }
        handlePayload?(payload)
    }
}
