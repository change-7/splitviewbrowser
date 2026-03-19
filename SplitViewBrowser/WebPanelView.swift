import SwiftUI

struct WebPanelView: View {
    @EnvironmentObject private var appState: AppState
    let panelIndex: Int
    @Binding var service: AIService
    let availableServices: [AIService]
    @ObservedObject var store: WebViewStore
    let isAnalysisTarget: Bool
    let onSetAnalysisTarget: () -> Void
    let onSendCollectedResponsesToPanel: () -> Void
    let onTriggerPageCopy: () -> Void

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
        .onChange(of: service) { newService in
            store.goHome(service: newService)
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

            Button(action: onSetAnalysisTarget) {
                Image(systemName: "scope")
                    .foregroundStyle(isAnalysisTarget ? Color.accentColor : Color.primary)
            }
            .help(isAnalysisTarget ? "현재 분석 대상 패널" : "이 패널을 분석 대상 패널로 지정")
            .accessibilityLabel(isAnalysisTarget ? "분석 대상 패널(선택됨)" : "분석 대상 패널로 지정")

            Button(action: onSendCollectedResponsesToPanel) {
                Image(systemName: "paperplane")
                    .foregroundStyle(isAnalysisTarget ? Color.accentColor : Color.primary)
            }
            .help("수집 답변을 이 패널로 입력/전송")
            .accessibilityLabel("이 패널로 수집 답변 전송")

            Button(action: onTriggerPageCopy) {
                Image(systemName: "doc.on.doc")
            }
            .help("이 패널의 최신 답변 복사 버튼 클릭")
            .accessibilityLabel("이 패널 최신 답변 복사")

            Button(action: store.reload) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")
            .accessibilityLabel("새로고침")

            Button(action: {
                store.goHome(service: service)
            }) {
                Image(systemName: "house")
            }
            .help("Home")
            .accessibilityLabel("홈")
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

    private func collectDirectCopiedResponseIfAvailable() {
        guard let copied = store.lastCopiedAssistantResponse else { return }
        appState.collectPanelResponse(
            panelIndex: panelIndex,
            service: service,
            sourceURLString: copied.urlString,
            text: copied.text
        )
    }
}
