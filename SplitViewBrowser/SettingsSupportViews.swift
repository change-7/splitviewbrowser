import AppKit
import SwiftUI

struct DiagnosticsSectionView: View {
    @ObservedObject private var appLogger = AppLogger.shared
    @State private var diagnosticsExpanded = false

    var body: some View {
        GroupBox("Diagnostics") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button("Copy Logs") {
                        copyDiagnosticsLogs()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("로그 복사")

                    Button("Clear Logs") {
                        appLogger.clear()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("로그 지우기")

                    Spacer()

                    Text("\(appLogger.entries.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(appLogger.entries.suffix(80)) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(entry.level.rawValue)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(logLevelColor(entry.level))
                                        Text(entry.category)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(entry.repeatCount > 1 ? "\(entry.message) (x\(entry.repeatCount))" : entry.message)
                                        .font(.caption2.monospaced())
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                } label: {
                    Text("Recent App Logs")
                }
            }
            .padding(.top, 4)
        }
    }

    private func copyDiagnosticsLogs() {
        let text = appLogger.joinedText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func logLevelColor(_ level: AppLogger.Level) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

struct AutoCopyProfileEditorRow: View {
    @EnvironmentObject private var appState: AppState
    let service: AIService

    @State private var supportLevel: AutoCopySupportLevel = .unsupported
    @State private var composerSelectorsText = ""
    @State private var sendSelectorsText = ""
    @State private var sendPatternText = ""
    @State private var enableEnterKey = true
    @State private var hasLoaded = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.title)
                    Text(service.urlString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Picker("지원 상태", selection: $supportLevel) {
                    ForEach(AutoCopySupportLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
                .onChange(of: supportLevel) { _ in saveProfile() }
                .accessibilityLabel("\(service.title) 자동복사 지원 상태")

                Button {
                    resetProfile()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .help("Reset to defaults")
                .accessibilityLabel("\(service.title) 자동복사 설정 초기화")
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("입력창 선택자 (쉼표 구분, 비우면 기본값 사용)", text: $composerSelectorsText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveProfile() }

                    TextField("전송 버튼 선택자 (쉼표 구분, 비우면 기본값 사용)", text: $sendSelectorsText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveProfile() }

                    TextField("전송 버튼 감지 패턴(정규식, 비우면 기본값 사용)", text: $sendPatternText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveProfile() }

                    Toggle("Enter 전송 감지 사용", isOn: $enableEnterKey)
                        .toggleStyle(.checkbox)
                        .onChange(of: enableEnterKey) { _ in saveProfile() }

                    HStack {
                        Spacer()
                        Button("저장") {
                            saveProfile()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(isExpanded ? "세부 설정 접기" : "세부 설정 펼치기")
                    .font(.caption)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .onAppear {
            loadProfile()
        }
        .onChange(of: service.id) { _ in
            hasLoaded = false
            loadProfile()
        }
    }

    private func loadProfile() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let profile = appState.autoCopyProfile(for: service)
        supportLevel = profile.supportLevel
        composerSelectorsText = (profile.composerSelectors ?? []).joined(separator: ", ")
        sendSelectorsText = (profile.sendButtonSelectors ?? []).joined(separator: ", ")
        sendPatternText = profile.sendPattern ?? ""
        enableEnterKey = profile.enableEnterKey ?? AutoCopyCatalog.defaultConfiguration(for: service).rule?.enableEnterKey ?? true
    }

    private func saveProfile() {
        let composerSelectors = splitSelectors(from: composerSelectorsText)
        let sendSelectors = splitSelectors(from: sendSelectorsText)
        let sendPattern = sendPatternText.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = AutoCopySiteProfile(
            supportLevel: supportLevel,
            composerSelectors: composerSelectors,
            sendButtonSelectors: sendSelectors,
            sendPattern: sendPattern.isEmpty ? nil : sendPattern,
            enableEnterKey: enableEnterKey
        )
        appState.updateAutoCopyProfile(for: service.id, profile: profile)
    }

    private func resetProfile() {
        appState.resetAutoCopyProfile(for: service.id)
        hasLoaded = false
        loadProfile()
    }

    private func splitSelectors(from text: String) -> [String]? {
        let values = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }
}
