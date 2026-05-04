import SwiftUI
import WebKit

struct WebPanelView: View {
    @EnvironmentObject private var appState: AppState
    let panelIndex: Int
    @Binding var service: AIService
    let availableServices: [AIService]
    @ObservedObject var store: WebViewStore
    let isAnalysisTarget: Bool
    let canClose: Bool
    let onSendCollectedResponsesToPanel: () -> Void
    let onTriggerPageCopy: () -> Void
    let onTriggerTemporaryChat: () -> Void
    let onClosePanel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            panelToolbar

            Divider()

            ZStack {
                WebViewContainer(webView: store.webView)

                if let issue = store.runtimeIssue {
                    runtimeIssueOverlay(issue)
                        .padding(12)
                }

                if let popupWebView = store.popupWebView {
                    popupWebViewOverlay(popupWebView)
                        .padding(18)
                }
            }

        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(panelBorderColor, lineWidth: panelBorderLineWidth)
        )
        .onAppear {
            store.goHomeIfNeeded(service: service)
        }
        .onChange(of: store.lastCopiedAssistantResponse?.id) { _ in
            collectDirectCopiedResponseIfAvailable()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("패널 \(panelIndex + 1)")
    }

    private var panelToolbar: some View {
        HStack(spacing: 8) {
            Picker("Service", selection: $service) {
                ForEach(availableServices) { item in
                    Text(item.title).tag(item)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(availableServices.isEmpty)
            .accessibilityLabel("서비스 선택")

            if store.isLoadingPage {
                ProgressView()
                    .controlSize(.small)
                    .help("Loading")
                    .accessibilityLabel("로딩 중")
            }

            Button(action: {
                store.goHome(service: service)
            }) {
                Image(systemName: "house")
            }
            .help("Home")
            .accessibilityLabel("홈")

            Button(action: store.reload) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")
            .accessibilityLabel("새로고침")

            Button(action: onSendCollectedResponsesToPanel) {
                Image(systemName: "paperplane")
                    .foregroundStyle(isAnalysisTarget ? Color.accentColor : Color.primary)
            }
            .help(isAnalysisTarget ? "수집 답변을 이 분석 패널로 입력/전송" : "이 패널을 분석 대상으로 지정하고 수집 답변 입력/전송")
            .accessibilityLabel(isAnalysisTarget ? "수집 답변을 이 분석 패널로 전송" : "이 패널을 분석 대상으로 지정하고 수집 답변 전송")

            Button(action: onTriggerPageCopy) {
                Image(systemName: "doc.on.doc")
            }
            .help("이 패널의 최신 답변 복사 버튼 클릭")
            .accessibilityLabel("이 패널 최신 답변 복사")

            if supportsTemporaryChat {
                Button(action: onTriggerTemporaryChat) {
                    TemporaryChatBadgeView(
                        isActive: showsTemporaryChatAsActive,
                        foreground: .primary,
                        activeColor: .red,
                        size: 15
                    )
                }
                .help(temporaryChatButtonHelp)
                .accessibilityLabel(temporaryChatAccessibilityLabel)
            }

            if canClose {
                Button(action: onClosePanel) {
                    Image(systemName: "xmark")
                }
                .help("이 패널 닫기")
                .accessibilityLabel("이 패널 닫기")
            }
        }
        .padding(8)
        .background(.bar)
    }

    private var panelBorderColor: Color {
        isAnalysisTarget ? Color.accentColor.opacity(0.95) : Color.secondary.opacity(0.25)
    }

    private var panelBorderLineWidth: CGFloat {
        isAnalysisTarget ? 2 : 1
    }

    private var supportsTemporaryChat: Bool {
        service.id == AIService.chatGPT.id || service.id == AIService.gemini.id || service.id == AIService.claude.id || service.id == AIService.grok.id
    }

    private var supportsReliableTemporaryChatState: Bool {
        service.id == AIService.chatGPT.id || service.id == AIService.gemini.id || service.id == AIService.claude.id || service.id == AIService.grok.id
    }

    private var showsTemporaryChatAsActive: Bool {
        supportsReliableTemporaryChatState && store.temporaryChatState.isActive
    }

    private var temporaryChatButtonHelp: String {
        if !supportsReliableTemporaryChatState {
            return "임시채팅"
        }

        switch store.temporaryChatState {
        case .active:
            return "임시채팅 활성 상태"
        case .inactive:
            return "임시채팅 시작"
        case .unknown:
            return "임시채팅 상태 확인 중"
        case .unavailable:
            return "임시채팅"
        }
    }

    private var temporaryChatAccessibilityLabel: String {
        if !supportsReliableTemporaryChatState {
            return "임시채팅"
        }

        switch store.temporaryChatState {
        case .active:
            return "임시채팅 활성 상태"
        case .inactive:
            return "임시채팅 시작"
        case .unknown:
            return "임시채팅 상태 확인 중"
        case .unavailable:
            return "임시채팅"
        }
    }

    private func runtimeIssueOverlay(_ issue: WebViewStore.RuntimeIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.headline)
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    store.dismissRuntimeIssue()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("닫기")
                .accessibilityLabel("오류 안내 닫기")
            }

            if let url = issue.urlString, !url.isEmpty {
                Text(url)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                if issue.isRecoverable {
                    Button("다시 시도") {
                        store.retryCurrentOrHome(service: service)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("다시 시도")
                }

                Button("홈으로") {
                    store.goHome(service: service)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("홈으로 이동")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary)
        )
        .shadow(radius: 6, y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func popupWebViewOverlay(_ popupWebView: WKWebView) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("로그인 창")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.dismissPopupWebView()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("로그인 창 닫기")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            WebViewContainer(webView: popupWebView)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func collectDirectCopiedResponseIfAvailable() {
        guard let copied = store.lastCopiedAssistantResponse else { return }
        appState.collectPanelResponse(
            panelIndex: panelIndex,
            service: service,
            text: copied.text
        )
    }
}
