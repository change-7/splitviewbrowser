import AppKit
import SwiftUI

struct QuickComposePopoverView: View {
    @Binding var text: String
    @Binding var selectedPanelIndices: Set<Int>
    let totalCount: Int
    let supportsTemporaryChat: (Int) -> Bool
    let storeForPanel: (Int) -> WebViewStore
    let onToggleTemporaryChat: (Int) -> Void
    let onSubmit: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("동시 입력/전송")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("닫기")
                .accessibilityLabel("동시 입력 전송 닫기")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("선택 \(selectedCount)/\(totalCount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selectedCount > 0 ? Color.accentColor : .secondary)
                        Spacer(minLength: 8)
                        Button("전체") {
                            selectedPanelIndices = Set(0 ..< totalCount)
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
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(0 ..< totalCount, id: \.self) { index in
                                Toggle("P\(index + 1)", isOn: panelSelectionBinding(for: index))
                                    .toggleStyle(.checkbox)
                                    .font(.caption2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 2)
            } label: {
                Text("전송 대상 패널")
                    .font(.caption.weight(.semibold))
            }
            .controlSize(.small)

            if !temporaryChatPanelIndices.isEmpty {
                GroupBox {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(temporaryChatPanelIndices, id: \.self) { index in
                                QuickComposeTemporaryChatButton(
                                    panelIndex: index,
                                    store: storeForPanel(index),
                                    onToggle: { onToggleTemporaryChat(index) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("패널별 임시채팅")
                        .font(.caption.weight(.semibold))
                }
                .controlSize(.small)
            }

            ZStack(alignment: .topLeading) {
                SubmitAwareTextEditor(text: $text, onSubmit: onSubmit, shouldAutoFocus: true)
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("여기에 입력하세요 (Enter 줄바꿈, Shift+Enter 전송)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Text("Enter: 줄바꿈 · Shift+Enter: 선택 패널에 동시 입력+전송")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text("대상 \(selectedCount)/\(totalCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selectedCount > 0 ? Color.accentColor : .secondary)

                Button("전송") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCount == 0)
                .accessibilityLabel("동시 입력 전송")
            }
        }
        .padding(14)
        .onAppear {
            normalizeSelections()
        }
        .onChange(of: totalCount) { _ in
            normalizeSelections()
        }
    }

    private var selectedCount: Int {
        selectedPanelIndices.filter { $0 >= 0 && $0 < totalCount }.count
    }

    private var temporaryChatPanelIndices: [Int] {
        Array(0 ..< totalCount).filter(supportsTemporaryChat)
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

    private func normalizeSelections() {
        selectedPanelIndices = Set(selectedPanelIndices.filter { $0 >= 0 && $0 < totalCount })
    }
}

private struct QuickComposeTemporaryChatButton: View {
    let panelIndex: Int
    @ObservedObject var store: WebViewStore
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Text("P\(panelIndex + 1)")
                    .font(.caption.weight(.semibold))
                TemporaryChatBadgeView(
                    state: store.temporaryChatState.isActive ? .active : .inactive,
                    foreground: .primary,
                    activeColor: .red,
                    size: 14
                )
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("패널 \(panelIndex + 1) 임시채팅 켜기/끄기")
        .accessibilityLabel("패널 \(panelIndex + 1) 임시채팅 켜기 끄기")
    }
}

private struct SubmitAwareTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let shouldAutoFocus: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, shouldAutoFocus: shouldAutoFocus)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        let textView = SubmitAwareTextView(frame: .zero)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.font = .systemFont(ofSize: 13)
        textView.drawsBackground = true
        textView.delegate = context.coordinator
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 150)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.onSubmit = { context.coordinator.onSubmit() }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        DispatchQueue.main.async {
            context.coordinator.focusIfNeeded()
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.shouldAutoFocus = shouldAutoFocus
        guard let textView = context.coordinator.textView else { return }
        textView.onSubmit = { context.coordinator.onSubmit() }
        context.coordinator.syncTextFromModelIfNeeded()
        DispatchQueue.main.async {
            context.coordinator.focusIfNeeded()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var shouldAutoFocus: Bool
        private var didAutoFocus = false
        private var isApplyingModelUpdate = false
        private var lastSelectedRanges: [NSValue] = []
        weak var textView: SubmitAwareTextView?

        init(text: Binding<String>, onSubmit: @escaping () -> Void, shouldAutoFocus: Bool) {
            _text = text
            self.onSubmit = onSubmit
            self.shouldAutoFocus = shouldAutoFocus
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isApplyingModelUpdate else { return }
            lastSelectedRanges = textView.selectedRanges
            text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            lastSelectedRanges = textView.selectedRanges
        }

        func focusIfNeeded() {
            guard shouldAutoFocus else { return }
            guard !didAutoFocus else { return }
            guard let textView, let window = textView.window else { return }
            if window.makeFirstResponder(textView) {
                didAutoFocus = true
            }
        }

        func syncTextFromModelIfNeeded() {
            guard let textView else { return }
            guard !textView.hasMarkedText() else { return }
            guard textView.string != text else { return }

            let isActivelyEditing = textView.window?.firstResponder === textView
            guard !isActivelyEditing else { return }

            let clampedRanges = clampedSelectedRanges(for: text)
            isApplyingModelUpdate = true
            textView.string = text
            textView.selectedRanges = clampedRanges
            lastSelectedRanges = clampedRanges
            isApplyingModelUpdate = false
        }

        private func clampedSelectedRanges(for text: String) -> [NSValue] {
            let length = text.utf16.count
            let sourceRanges = lastSelectedRanges.isEmpty ? [NSValue(range: NSRange(location: length, length: 0))] : lastSelectedRanges

            return sourceRanges.map { value in
                let range = value.rangeValue
                let location = min(max(range.location, 0), length)
                let maxLength = max(length - location, 0)
                let clampedLength = min(max(range.length, 0), maxLength)
                return NSValue(range: NSRange(location: location, length: clampedLength))
            }
        }
    }
}

private final class SubmitAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        guard isReturn else {
            super.keyDown(with: event)
            return
        }

        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) {
            super.keyDown(with: event)
        } else if modifiers.contains(.shift) {
            onSubmit?()
        } else {
            insertNewline(nil)
        }
    }
}
