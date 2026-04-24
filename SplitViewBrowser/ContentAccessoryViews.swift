import SwiftUI

private enum ToolbarControlMetrics {
    static let minHeight: CGFloat = 28
}

struct ToolbarChipPalette {
    let foreground: Color
    let fill: Color
    let border: Color

    static let neutral = ToolbarChipPalette(
        foreground: Color.primary,
        fill: Color(nsColor: .controlBackgroundColor),
        border: Color.secondary.opacity(0.25)
    )
}

struct ToolbarActionChipButton<Label: View>: View {
    let helpText: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let palette: ToolbarChipPalette
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(
        helpText: String,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        palette: ToolbarChipPalette = .neutral,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.helpText = helpText
        self.accessibilityLabel = accessibilityLabel
        self.isEnabled = isEnabled
        self.palette = palette
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(isEnabled ? palette.foreground : palette.foreground.opacity(0.45))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minHeight: ToolbarControlMetrics.minHeight)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ToolbarIconBadgeButton: View {
    let systemName: String
    let helpText: String
    let accessibilityLabel: String
    let palette: ToolbarChipPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.foreground)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(minHeight: ToolbarControlMetrics.minHeight)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct TemporaryChatBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tailWidth = rect.width * 0.18
        let tailHeight = rect.height * 0.2
        let bubbleRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        let radius = min(bubbleRect.width, bubbleRect.height) * 0.28

        var path = Path(roundedRect: bubbleRect, cornerRadius: radius)

        let tailTop = CGPoint(x: bubbleRect.midX - tailWidth * 0.55, y: bubbleRect.maxY)
        let tailTip = CGPoint(x: bubbleRect.midX - tailWidth * 0.05, y: rect.maxY)
        let tailBottom = CGPoint(x: bubbleRect.midX + tailWidth * 0.45, y: bubbleRect.maxY)

        path.move(to: tailTop)
        path.addLine(to: tailTip)
        path.addLine(to: tailBottom)
        path.closeSubpath()

        return path
    }
}

enum TemporaryChatBadgeState {
    case inactive
    case mixed
    case active
}

struct TemporaryChatBadgeView: View {
    let state: TemporaryChatBadgeState
    var foreground: Color = .primary
    var activeColor: Color = .red
    var size: CGFloat = 16

    init(
        state: TemporaryChatBadgeState,
        foreground: Color = .primary,
        activeColor: Color = .red,
        size: CGFloat = 16
    ) {
        self.state = state
        self.foreground = foreground
        self.activeColor = activeColor
        self.size = size
    }

    init(
        isActive: Bool,
        foreground: Color = .primary,
        activeColor: Color = .red,
        size: CGFloat = 16
    ) {
        self.init(
            state: isActive ? .active : .inactive,
            foreground: foreground,
            activeColor: activeColor,
            size: size
        )
    }

    var body: some View {
        ZStack {
            TemporaryChatBubbleShape()
                .fill(fillColor)

            TemporaryChatBubbleShape()
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round, dash: state == .inactive ? [2.2, 2.2] : [])
                )

            HStack(spacing: size * 0.1) {
                dot
                dot
                dot
            }
            .offset(y: -size * 0.08)
        }
        .frame(width: size * 1.15, height: size)
    }

    private var dot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: size * 0.12, height: size * 0.12)
    }

    private var fillColor: Color {
        switch state {
        case .active:
            return activeColor.opacity(0.9)
        case .mixed, .inactive:
            return .clear
        }
    }

    private var strokeColor: Color {
        switch state {
        case .active, .mixed:
            return activeColor
        case .inactive:
            return foreground.opacity(0.85)
        }
    }

    private var dotColor: Color {
        switch state {
        case .active:
            return .white
        case .mixed:
            return activeColor
        case .inactive:
            return foreground.opacity(0.9)
        }
    }
}

struct TwoPanelCrossSendControlView: View {
    let isInFlight: Bool
    let isFirstToSecondHighlighted: Bool
    let isSecondToFirstHighlighted: Bool
    let onFirstToSecond: () -> Void
    let onSecondToFirst: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            button(
                symbolName: "arrow.right.circle.fill",
                isHighlighted: isFirstToSecondHighlighted,
                helpText: "패널 1 최신 답변을 패널 2로 전송",
                action: onFirstToSecond
            )

            button(
                symbolName: "arrow.left.circle.fill",
                isHighlighted: isSecondToFirstHighlighted,
                helpText: "패널 2 최신 답변을 패널 1로 전송",
                action: onSecondToFirst
            )
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 5)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .zIndex(2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("2패널 교차 전송")
    }

    private func button(
        symbolName: String,
        isHighlighted: Bool,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(buttonForegroundColor(isHighlighted: isHighlighted))
        .background(
            Circle()
                .fill(buttonBackgroundColor(isHighlighted: isHighlighted))
        )
        .overlay(
            Circle()
                .stroke(buttonBorderColor(isHighlighted: isHighlighted), lineWidth: isHighlighted ? 1.2 : 1)
        )
        .disabled(isInFlight)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private func buttonForegroundColor(isHighlighted: Bool) -> Color {
        if isInFlight {
            return isHighlighted ? Color.accentColor.opacity(0.8) : Color.secondary
        }
        return isHighlighted ? Color.white : Color.accentColor
    }

    private func buttonBackgroundColor(isHighlighted: Bool) -> Color {
        if isHighlighted {
            return Color.accentColor.opacity(isInFlight ? 0.45 : 0.9)
        }
        return Color(nsColor: .windowBackgroundColor).opacity(0.94)
    }

    private func buttonBorderColor(isHighlighted: Bool) -> Color {
        if isHighlighted {
            return Color.accentColor.opacity(0.95)
        }
        return Color.secondary.opacity(0.24)
    }
}

struct QuickComposeTargetBarView: View {
    @Binding var selectedPanelIndices: Set<Int>
    let panelCount: Int
    let onOpenCompose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onOpenCompose()
            } label: {
                Label("입력창", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("동시 입력창 열기")

            Text("동시 입력/전송 대상")
                .font(.caption.weight(.semibold))

            Button("전체") {
                selectedPanelIndices = Set(0 ..< panelCount)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("모든 패널 선택")

            Button("해제") {
                selectedPanelIndices.removeAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("패널 선택 해제")

            ForEach(0 ..< panelCount, id: \.self) { index in
                Toggle("P\(index + 1)", isOn: panelSelectionBinding(for: index))
                    .toggleStyle(.checkbox)
                    .font(.caption2)
            }

            Spacer(minLength: 6)

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Settings")
            .accessibilityLabel("설정 열기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func panelSelectionBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { selectedPanelIndices.contains(index) },
            set: { isSelected in
                if isSelected {
                    selectedPanelIndices.insert(index)
                } else {
                    selectedPanelIndices.remove(index)
                }
            }
        )
    }
}
