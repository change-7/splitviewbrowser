import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum Layout {
    static let mobileMin: CGFloat = 360
    static let mobileMax: CGFloat = 430
    static let gutter: CGFloat = 10
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 8
    static let minimumWindowHeight: CGFloat = 520
}

struct ContentView: View {
    private static let defaultAnalysisPromptSelectionTag = "__default_analysis_prompt__"

    @EnvironmentObject private var appState: AppState
    @State private var isPromptRepositoryPresented = false
    @State private var isSettingsPresented = false
    @State private var isQuickComposePresented = false
    @State private var quickComposeText = ""
    @State private var quickComposeTargetPanels: Set<Int> = []
    @State private var quickComposeKnownPanelCount = 0
    @State private var collectionStatusMessage = ""
    @State private var collectionStatusIsError = false
    @State private var collectionStatusClearTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            horizontalPanelsView(proxy: proxy)
        }
        .background(
            WindowMinimumSizeAccessor(
                minWidth: minimumWindowSize.width,
                minHeight: minimumWindowSize.height,
                pendingPresetWindowSize: appState.pendingPresetWindowSize,
                onWindowContentSizeChanged: { size in
                    appState.syncActivePresetWindowSize(size)
                },
                onPendingPresetWindowSizeApplied: {
                    appState.consumePendingPresetWindowSize()
                }
            )
        )
        .frame(minWidth: minimumWindowSize.width, minHeight: minimumWindowSize.height)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("패널 수", selection: panelCountBinding) {
                    ForEach(AppState.minPanels ... AppState.maxPanels, id: \.self) { count in
                        Text("\(count)개").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 86)
                .help("Panel Count")
                .accessibilityLabel("패널 개수 선택")
            }
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 6) {
                    presetSelectionButton(
                        title: toolbarNonePresetTitle,
                        isSelected: appState.activePresetID == nil,
                        help: appState.activePresetID == nil ? "현재 선택됨: 프리셋 미선택" : "프리셋 미선택"
                    ) {
                        clearPresetSelectionFromToolbar()
                    }

                    ForEach(appState.presets, id: \ViewPreset.id) { (preset: ViewPreset) in
                        presetSelectionButton(
                            title: toolbarPresetTitle(for: preset),
                            isSelected: appState.activePresetID == preset.id,
                            help: appState.activePresetID == preset.id ? "현재 선택됨: \(preset.name)" : preset.name
                        ) {
                            applyPresetFromToolbar(preset)
                        }
                    }

                    Button {
                        addPresetFromToolbar()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .help("현재 창 상태를 프리셋으로 저장")
                    .accessibilityLabel("현재 상태를 프리셋으로 저장")
                }
            }

            ToolbarItem(placement: .automatic) {
                HStack(spacing: 6) {
                    Menu {
                        ForEach(0 ..< appState.panelCount, id: \.self) { index in
                            Button("분석 \(index + 1)") {
                                selectAnalysisTargetPanel(index)
                            }
                        }
                    } label: {
                        toolbarChipLabel(title: "분석 \(appState.analysisTargetPanelIndex + 1)", width: 92, showsChevron: true)
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                    .help("수집한 답변을 보낼 분석/정리 담당 패널")
                    .accessibilityLabel("분석 대상 패널 선택")

                    Menu {
                        Button("기본(내장)") {
                            appState.setSelectedAnalysisPromptID(nil)
                        }
                        ForEach(appState.savedPrompts, id: \SavedPrompt.id) { prompt in
                            Button(prompt.title) {
                                appState.setSelectedAnalysisPromptID(prompt.id)
                            }
                        }
                    } label: {
                        toolbarChipLabel(title: analysisPromptToolbarTitle, width: 128, showsChevron: true)
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                    .help("전송 시 앞부분에 고정으로 붙일 프롬프트 선택")
                    .accessibilityLabel("전송 기본 프롬프트 선택")

                    Button("전체 복사") {
                        triggerPageCopyForAllVisiblePanels()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .help("분석 대상 패널을 제외한 현재 보이는 모든 패널에서 최신 답변 복사 버튼 클릭")
                    .accessibilityLabel("전체 패널 최신 답변 복사")

                    Button {
                        appState.clearCollectedResponsesForVisiblePanels()
                        setCollectionStatus("수집 답변 비움", isError: false)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.visibleCollectedResponseCount == 0)
                    .help("현재 보이는 패널의 수집 답변 비우기")
                    .accessibilityLabel("수집 답변 비우기")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    isSettingsPresented = false
                    isPromptRepositoryPresented.toggle()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("Prompt Repository")
                .accessibilityLabel("프롬프트 저장소 열기")
                .popover(isPresented: $isPromptRepositoryPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    PromptRepositoryView()
                        .frame(minWidth: 680, minHeight: 700)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isPromptRepositoryPresented = false
                    isSettingsPresented = false
                    isQuickComposePresented = true
                } label: {
                    Image(systemName: "paperplane.circle")
                }
                .help("동시 입력/전송")
                .accessibilityLabel("동시 입력 전송 열기")
            }
        }
        .overlay(alignment: .topTrailing) {
            if !collectionStatusMessage.isEmpty {
                Text(collectionStatusMessage)
                    .font(.caption)
                    .foregroundStyle(collectionStatusIsError ? Color.red : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule(style: .continuous))
                    .padding(.top, 6)
                    .padding(.trailing, 12)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            quickComposeTargetBar
        }
        .onAppear {
            initializeQuickComposeTargetsIfNeeded()
        }
        .onChange(of: appState.panelCount) { newCount in
            normalizeQuickComposeTargets(for: newCount)
        }
        .onDisappear {
            collectionStatusClearTask?.cancel()
        }
        .popover(isPresented: $isQuickComposePresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            QuickComposePopoverView(
                text: $quickComposeText,
                selectedPanelIndices: $quickComposeTargetPanels,
                totalCount: appState.panelCount,
                onSubmit: sendQuickComposeTextToSelectedPanels,
                onClose: { isQuickComposePresented = false }
            )
            .frame(minWidth: 620, minHeight: 420)
        }
    }

    private var panelCountBinding: Binding<Int> {
        Binding(
            get: { appState.panelCount },
            set: { appState.setPanelCount($0) }
        )
    }

    private func serviceBinding(for index: Int) -> Binding<AIService> {
        Binding(
            get: { appState.service(at: index) },
            set: { appState.setService($0, at: index) }
        )
    }

    private var minimumPanelWidth: CGFloat {
        Layout.mobileMax
    }

    private func panelWidth(for windowWidth: CGFloat, columns: Int) -> CGFloat {
        guard columns > 0 else { return minimumPanelWidth }
        let available =
            windowWidth -
            (Layout.horizontalPadding * 2) -
            (CGFloat(max(columns - 1, 0)) * Layout.gutter)
        return max(minimumPanelWidth, available / CGFloat(columns))
    }

    private var minimumWindowSize: CGSize {
        CGSize(
            width: minimumWidth(forColumns: appState.panelCount),
            height: Layout.minimumWindowHeight
        )
    }

    private func minimumWidth(forColumns columns: Int) -> CGFloat {
        let contentWidth = (CGFloat(columns) * minimumPanelWidth) + (CGFloat(max(columns - 1, 0)) * Layout.gutter)
        return contentWidth + (Layout.horizontalPadding * 2)
    }

    private func horizontalPanelsView(proxy: GeometryProxy) -> some View {
        ScrollView(.horizontal) {
            let panelCount = appState.panelCount
            let currentPanelWidth = panelWidth(for: proxy.size.width, columns: panelCount)

            HStack(spacing: Layout.gutter) {
                ForEach(0 ..< panelCount, id: \.self) { index in
                    WebPanelView(
                        panelIndex: index,
                        service: serviceBinding(for: index),
                        availableServices: appState.services,
                        store: appState.webViewStore(for: index),
                        isAnalysisTarget: appState.analysisTargetPanelIndex == index,
                        onSetAnalysisTarget: {
                            selectAnalysisTargetPanel(index)
                        },
                        onSendCollectedResponsesToPanel: {
                            sendCollectedResponses(toPanel: index, updateAnalysisTarget: true)
                        },
                        onTriggerPageCopy: {
                            triggerLatestPageCopy(from: index)
                        }
                    )
                        .frame(width: currentPanelWidth)
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.top, Layout.topPadding)
            .padding(.bottom, Layout.bottomPadding)
            .frame(width: max(proxy.size.width, minimumWindowSize.width), alignment: .center)
        }
    }

    private func applyPresetFromToolbar(_ preset: ViewPreset) {
        appState.applyPreset(id: preset.id)
    }

    private func addPresetFromToolbar() {
        let windowSize = currentWindowContentSize()
        _ = appState.saveCurrentPresetWithAutoName(windowSize: windowSize)
    }

    private func clearPresetSelectionFromToolbar() {
        appState.clearActivePresetSelection()
    }

    private func triggerLatestPageCopy(from panelIndex: Int) {
        guard panelIndex >= 0, panelIndex < appState.panelCount else {
            setCollectionStatus("패널 인덱스가 유효하지 않습니다", isError: true)
            return
        }

        let store = appState.webViewStore(for: panelIndex)
        Task {
            let result = await store.triggerAssistantAnswerCopy(targetOffset: 0)
            switch result {
            case let .success(copyResult):
                if copyResult.clicked {
                    setCollectionStatus("패널 \(panelIndex + 1) 최신 답변 복사 버튼 클릭 완료", isError: false)
                } else {
                    setCollectionStatus("패널 \(panelIndex + 1) 복사 버튼 클릭 결과 확인 필요", isError: true)
                }
            case let .failure(error):
                setCollectionStatus("패널 \(panelIndex + 1) 복사 실패: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func triggerPageCopyForAllVisiblePanels() {
        let analysisTargetIndex = appState.analysisTargetPanelIndex
        let panelIndices = Array(0 ..< appState.panelCount).filter { $0 != analysisTargetIndex }
        guard !panelIndices.isEmpty else {
            setCollectionStatus("분석 패널을 제외하면 복사할 패널이 없습니다", isError: true)
            return
        }

        Task {
            var clickedCount = 0
            var failedCount = 0

            for panelIndex in panelIndices {
                let store = appState.webViewStore(for: panelIndex)
                let result = await store.triggerAssistantAnswerCopy(targetOffset: 0)
                switch result {
                case let .success(copyResult):
                    if copyResult.clicked {
                        clickedCount += 1
                    } else {
                        failedCount += 1
                    }
                case .failure:
                    failedCount += 1
                }
            }

            if failedCount == 0 {
                setCollectionStatus("전체 복사 버튼 클릭 완료: \(clickedCount)/\(panelIndices.count) 패널 (분석 패널 제외)", isError: false)
            } else {
                setCollectionStatus("전체 복사 일부 실패: 성공 \(clickedCount), 실패 \(failedCount) (분석 패널 제외)", isError: true)
            }
        }
    }

    private func selectAnalysisTargetPanel(_ panelIndex: Int) {
        appState.setAnalysisTargetPanelIndex(panelIndex)
        prepareAnalysisTargetComposer(panelIndex: panelIndex)
    }

    private func prepareAnalysisTargetComposer(panelIndex: Int) {
        guard panelIndex >= 0, panelIndex < appState.panelCount else {
            setCollectionStatus("분석 대상 패널이 유효하지 않습니다", isError: true)
            return
        }

        let targetStore = appState.webViewStore(for: panelIndex)
        Task {
            let result = await targetStore.prepareComposerForInput()
            switch result {
            case let .success(prepareResult):
                if prepareResult.focused {
                    setCollectionStatus("분석 패널 \(panelIndex + 1) 입력창 준비 완료", isError: false)
                } else {
                    setCollectionStatus("분석 패널 \(panelIndex + 1) 입력창 준비 결과 확인 필요", isError: true)
                }
            case let .failure(error):
                setCollectionStatus("분석 패널 \(panelIndex + 1) 입력창 준비 실패: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func sendCollectedResponses(toPanel panelIndex: Int, updateAnalysisTarget: Bool) {
        guard let prompt = appState.buildCollectedResponsesAnalysisPrompt() else {
            setCollectionStatus("전송할 수집 답변이 없습니다", isError: true)
            return
        }

        guard panelIndex >= 0, panelIndex < appState.panelCount else {
            setCollectionStatus("대상 패널이 유효하지 않습니다", isError: true)
            return
        }

        if updateAnalysisTarget {
            appState.setAnalysisTargetPanelIndex(panelIndex)
        }

        let targetStore = appState.webViewStore(for: panelIndex)
        Task {
            let result = await targetStore.sendTextToComposer(prompt, submit: true)
            switch result {
            case let .success(sendResult):
                if sendResult.submitted {
                    setCollectionStatus("패널 \(panelIndex + 1)에 입력 및 전송 완료", isError: false)
                } else if sendResult.inserted {
                    setCollectionStatus("패널 \(panelIndex + 1)에 입력 완료 (전송 버튼 미탐지)", isError: false)
                } else {
                    setCollectionStatus("패널 \(panelIndex + 1) 전송 결과 확인 필요", isError: true)
                }
            case let .failure(error):
                setCollectionStatus("패널 \(panelIndex + 1) 전송 실패: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func setCollectionStatus(_ message: String, isError: Bool) {
        collectionStatusMessage = message
        collectionStatusIsError = isError
        collectionStatusClearTask?.cancel()
        collectionStatusClearTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, collectionStatusMessage == message else { return }
            collectionStatusMessage = ""
        }
    }

    private var selectedQuickComposePanelIndices: [Int] {
        quickComposeTargetPanels
            .filter { $0 >= 0 && $0 < appState.panelCount }
            .sorted()
    }

    private var quickComposeTargetBar: some View {
        HStack(spacing: 10) {
            Button {
                isPromptRepositoryPresented = false
                isSettingsPresented = false
                isQuickComposePresented = true
            } label: {
                Label("입력창", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("동시 입력창 열기")

            Text("동시 입력/전송 대상")
                .font(.caption.weight(.semibold))

            Button("전체") {
                quickComposeTargetPanels = Set(0 ..< appState.panelCount)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("모든 패널 선택")

            Button("해제") {
                quickComposeTargetPanels.removeAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("패널 선택 해제")

            ForEach(0 ..< appState.panelCount, id: \.self) { index in
                Toggle("P\(index + 1)", isOn: quickComposeTargetBinding(for: index))
                    .toggleStyle(.checkbox)
                    .font(.caption2)
            }

            Spacer(minLength: 6)

            Button {
                isPromptRepositoryPresented = false
                isQuickComposePresented = false
                isSettingsPresented.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Settings")
            .accessibilityLabel("설정 열기")
            .popover(isPresented: $isSettingsPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                SettingsView()
                    .frame(width: 980, height: 680)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func quickComposeTargetBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { quickComposeTargetPanels.contains(index) },
            set: { isSelected in
                if isSelected {
                    quickComposeTargetPanels.insert(index)
                } else {
                    quickComposeTargetPanels.remove(index)
                }
            }
        )
    }

    private func initializeQuickComposeTargetsIfNeeded() {
        guard quickComposeKnownPanelCount == 0 else { return }
        quickComposeKnownPanelCount = appState.panelCount
        quickComposeTargetPanels = Set(0 ..< appState.panelCount)
    }

    private func normalizeQuickComposeTargets(for newCount: Int) {
        if quickComposeKnownPanelCount == 0 {
            quickComposeKnownPanelCount = newCount
        }

        var normalized = Set(quickComposeTargetPanels.filter { $0 >= 0 && $0 < newCount })
        if newCount > quickComposeKnownPanelCount {
            for index in quickComposeKnownPanelCount ..< newCount {
                normalized.insert(index)
            }
        }
        quickComposeTargetPanels = normalized
        quickComposeKnownPanelCount = newCount
    }

    private func sendQuickComposeTextToSelectedPanels() {
        let trimmed = quickComposeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setCollectionStatus("동시 전송할 내용을 입력하세요", isError: true)
            return
        }

        let targets = selectedQuickComposePanelIndices
        guard !targets.isEmpty else {
            setCollectionStatus("하단 체크박스에서 전송할 패널을 선택하세요", isError: true)
            return
        }

        Task {
            var submittedCount = 0
            var insertedOnlyCount = 0
            var failedCount = 0

            for panelIndex in targets {
                let store = appState.webViewStore(for: panelIndex)
                let result = await store.sendTextToComposer(trimmed, submit: true)
                switch result {
                case let .success(sendResult):
                    if sendResult.submitted {
                        submittedCount += 1
                    } else if sendResult.inserted {
                        insertedOnlyCount += 1
                    } else {
                        failedCount += 1
                    }
                case .failure:
                    failedCount += 1
                }
            }

            if failedCount == 0 {
                if insertedOnlyCount == 0 {
                    setCollectionStatus("동시 전송 완료: \(submittedCount)/\(targets.count) 패널", isError: false)
                } else {
                    setCollectionStatus("동시 입력 완료: 전송 \(submittedCount), 입력만 \(insertedOnlyCount)", isError: false)
                }
                quickComposeText = ""
                isQuickComposePresented = false
            } else {
                setCollectionStatus(
                    "일부 실패: 성공 전송 \(submittedCount), 입력만 \(insertedOnlyCount), 실패 \(failedCount)",
                    isError: true
                )
            }
        }
    }

    private func currentWindowContentSize() -> CGSize? {
        let window = preferredContentWindow()
        guard let window else { return nil }
        return window.contentRect(forFrameRect: window.frame).size
    }

    private func presetToolbarTitle(for preset: ViewPreset) -> String {
        if let index = appState.presets.firstIndex(where: { $0.id == preset.id }) {
            return "\(index + 1)"
        }
        return preset.name
    }

    private func toolbarPresetTitle(for preset: ViewPreset) -> String {
        let title = presetToolbarTitle(for: preset)
        if appState.activePresetID == preset.id {
            return "\(title) ✓"
        }
        return title
    }

    private var toolbarNonePresetTitle: String {
        appState.activePresetID == nil ? "없음 ✓" : "없음"
    }

    private var analysisPromptToolbarTitle: String {
        appState.selectedAnalysisPromptDisplayTitle
    }

    private func presetSelectionButton(
        title: String,
        isSelected: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            isSelected ? Color.secondary.opacity(0.55) : Color.secondary.opacity(0.25),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func toolbarChipLabel(title: String, width: CGFloat, showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

}
