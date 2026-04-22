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
        PlatformClipboard.writeString(text)
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
