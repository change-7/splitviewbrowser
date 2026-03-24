import AppKit
import SwiftUI

private enum Layout {
    static let mobileMin: CGFloat = 360
    static let mobileMax: CGFloat = 430
    static let gutter: CGFloat = 10
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 8
    static let minimumWindowHeight: CGFloat = 520
}

private enum TwoPanelCrossSendDirection: Hashable {
    case firstToSecond
    case secondToFirst
}

struct ContentView: View {
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
    @State private var isTwoPanelCrossSendInFlight = false
    @State private var lastTwoPanelCrossSendDirection: TwoPanelCrossSendDirection?

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
            topToolbarContent
        }
        .overlay(alignment: .topTrailing) {
            if !collectionStatusMessage.isEmpty {
                Text(collectionStatusMessage)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(collectionStatusIsError ? Color.red : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule(style: .continuous))
                    .padding(.top, -22)
                    .padding(.trailing, 4)
                    .help(collectionStatusMessage)
                    .accessibilityLabel(collectionStatusMessage)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            QuickComposeTargetBarView(
                selectedPanelIndices: $quickComposeTargetPanels,
                panelCount: appState.panelCount,
                onOpenCompose: {
                    isPromptRepositoryPresented = false
                    isSettingsPresented = false
                    isQuickComposePresented = true
                },
                onOpenSettings: {
                    isPromptRepositoryPresented = false
                    isQuickComposePresented = false
                    isSettingsPresented.toggle()
                }
            )
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
        .popover(isPresented: $isSettingsPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            SettingsView()
                .frame(width: 980, height: 680)
        }
    }

    private var panelCountBinding: Binding<Int> {
        Binding(
            get: { appState.panelCount },
            set: { appState.setPanelCount($0) }
        )
    }

    @ToolbarContentBuilder
    private var topToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ToolbarIconBadgeButton(
                systemName: "house",
                helpText: "현재 보이는 모든 패널을 각 서비스 홈으로 이동",
                accessibilityLabel: "전체 패널 홈 이동",
                palette: .neutral,
                action: {
                    goHomeForAllVisiblePanels()
                }
            )
        }
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
        ToolbarItem(placement: .navigation) {
            presetToolbarGroupView
        }
        ToolbarItem(placement: .navigation) {
            ToolbarActionChipButton(
                helpText: "분석 대상 패널을 제외한 현재 보이는 모든 패널에서 최신 답변 복사 버튼 클릭",
                accessibilityLabel: "전체 패널 최신 답변 복사",
                palette: .neutral,
                action: {
                    triggerPageCopyForAllVisiblePanels()
                }
            ) {
                Text("전체 복사")
            }
        }
        ToolbarItem(placement: .navigation) {
            ToolbarIconBadgeButton(
                systemName: "square.and.pencil",
                helpText: "Prompt Repository",
                accessibilityLabel: "프롬프트 저장소 열기",
                palette: .neutral,
                action: {
                    isQuickComposePresented = false
                    isSettingsPresented = false
                    isPromptRepositoryPresented.toggle()
                }
            )
            .popover(isPresented: $isPromptRepositoryPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                PromptRepositoryView()
                    .frame(minWidth: 680, minHeight: 700)
            }
        }
        ToolbarItem(placement: .navigation) {
            ToolbarIconBadgeButton(
                systemName: "paperplane.circle",
                helpText: "동시 입력/전송",
                accessibilityLabel: "동시 입력 전송 열기",
                palette: .neutral,
                action: {
                    isPromptRepositoryPresented = false
                    isSettingsPresented = false
                    isQuickComposePresented = true
                }
            )
        }
        ToolbarItem(placement: .navigation) {
            ToolbarActionChipButton(
                helpText: "현재 보이는 패널의 수집 답변 비우기",
                accessibilityLabel: "수집 답변 비우기",
                isEnabled: appState.visibleCollectedResponseCount > 0,
                palette: .neutral,
                action: {
                    appState.clearCollectedResponsesForVisiblePanels()
                    setCollectionStatus("수집 답변 비움", isError: false)
                }
            ) {
                Image(systemName: "trash")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            ToolbarActionChipButton(
                helpText: "패널 추가",
                accessibilityLabel: "패널 추가",
                isEnabled: appState.panelCount < AppState.maxPanels,
                palette: .neutral,
                action: {
                    addPanelFromToolbar()
                }
            ) {
                Image(systemName: "plus.rectangle.on.rectangle")
            }
        }
    }

    private var presetToolbarGroupView: some View {
        HStack(spacing: 4) {
            toolbarPresetButton(
                title: toolbarNonePresetTitle,
                isSelected: appState.activePresetID == nil,
                helpText: appState.activePresetID == nil ? "현재 선택됨: 프리셋 미선택" : "프리셋 미선택",
                action: clearPresetSelectionFromToolbar
            )

            ForEach(appState.presets, id: \ViewPreset.id) { (preset: ViewPreset) in
                toolbarPresetButton(
                    title: toolbarPresetTitle(for: preset),
                    isSelected: appState.activePresetID == preset.id,
                    helpText: appState.activePresetID == preset.id ? "현재 선택됨: \(preset.name)" : preset.name,
                    action: { applyPresetFromToolbar(preset) }
                )
            }

            toolbarAddPresetButton
                .padding(.leading, -2)
        }
    }

    private func toolbarPresetButton(
        title: String,
        isSelected: Bool,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minHeight: 24)
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var toolbarAddPresetButton: some View {
        Button {
            addPresetFromToolbar()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minHeight: 24)
        }
        .buttonStyle(.plain)
        .help("현재 창 상태를 프리셋으로 저장")
        .accessibilityLabel("현재 상태를 프리셋으로 저장")
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

            ZStack {
                HStack(spacing: Layout.gutter) {
                    ForEach(0 ..< panelCount, id: \.self) { index in
                        WebPanelView(
                            panelIndex: index,
                            service: serviceBinding(for: index),
                            availableServices: appState.services,
                            store: appState.webViewStore(for: index),
                            isAnalysisTarget: appState.analysisTargetPanelIndex == index,
                            canClose: appState.panelCount > AppState.minPanels,
                            onSendCollectedResponsesToPanel: {
                                sendCollectedResponses(toPanel: index, updateAnalysisTarget: true)
                            },
                            onTriggerPageCopy: {
                                triggerLatestPageCopy(from: index)
                            },
                            onTriggerTemporaryChat: {
                                triggerTemporaryChat(for: index)
                            },
                            onClosePanel: {
                                closePanel(at: index)
                            }
                        )
                            .id(panelViewIdentity(for: index))
                            .frame(width: currentPanelWidth)
                    }
                }

                if shouldShowTwoPanelCrossSendControl {
                    TwoPanelCrossSendControlView(
                        isInFlight: isTwoPanelCrossSendInFlight,
                        isFirstToSecondHighlighted: lastTwoPanelCrossSendDirection == .firstToSecond,
                        isSecondToFirstHighlighted: lastTwoPanelCrossSendDirection == .secondToFirst,
                        onFirstToSecond: { sendLatestAnswerAcrossPanels(from: 0, to: 1) },
                        onSecondToFirst: { sendLatestAnswerAcrossPanels(from: 1, to: 0) }
                    )
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.top, Layout.topPadding)
            .padding(.bottom, Layout.bottomPadding)
            .frame(width: max(proxy.size.width, minimumWindowSize.width), alignment: .center)
        }
    }

    private var shouldShowTwoPanelCrossSendControl: Bool {
        appState.panelCount == 2 && appState.isTwoPanelCrossSendEnabled
    }

    private func applyPresetFromToolbar(_ preset: ViewPreset) {
        appState.applyPreset(id: preset.id)
    }

    private func panelViewIdentity(for index: Int) -> String {
        "panel-\(appState.panelStructureVersion)-\(index)"
    }

    private func addPresetFromToolbar() {
        let windowSize = currentWindowContentSize()
        _ = appState.saveCurrentPresetWithAutoName(windowSize: windowSize)
    }

    private func clearPresetSelectionFromToolbar() {
        appState.clearActivePresetSelection()
    }

    private func addPanelFromToolbar() {
        guard appState.panelCount < AppState.maxPanels else {
            setCollectionStatus("최대 \(AppState.maxPanels)개 패널까지 추가할 수 있습니다", isError: true)
            return
        }
        appState.addPanel()
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

    private func goHomeForAllVisiblePanels() {
        let panelIndices = Array(0 ..< appState.panelCount)
        guard !panelIndices.isEmpty else {
            setCollectionStatus("홈으로 이동할 패널이 없습니다", isError: true)
            return
        }

        for panelIndex in panelIndices {
            let service = appState.service(at: panelIndex)
            let store = appState.webViewStore(for: panelIndex)
            store.goHome(service: service)
        }

        setCollectionStatus("전체 패널을 홈으로 이동: \(panelIndices.count)개 패널", isError: false)
    }

    @MainActor
    private func sendLatestAnswerAcrossPanels(from sourcePanelIndex: Int, to targetPanelIndex: Int) {
        requestTwoPanelCrossSend(from: sourcePanelIndex, to: targetPanelIndex)
    }

    @MainActor
    private func requestTwoPanelCrossSend(
        from sourcePanelIndex: Int,
        to targetPanelIndex: Int
    ) {
        guard appState.panelCount == 2 else {
            setCollectionStatus("이 기능은 2패널일 때만 사용할 수 있습니다", isError: true)
            return
        }

        Task { @MainActor in
            _ = await performLatestAnswerCrossSend(
                from: sourcePanelIndex,
                to: targetPanelIndex
            )
        }
    }

    @MainActor
    @discardableResult
    private func performLatestAnswerCrossSend(
        from sourcePanelIndex: Int,
        to targetPanelIndex: Int
    ) async -> Bool {
        guard sourcePanelIndex != targetPanelIndex else {
            setCollectionStatus("같은 패널로는 전송할 수 없습니다", isError: true)
            return false
        }

        guard !isTwoPanelCrossSendInFlight else {
            setCollectionStatus("패널 간 전송이 이미 진행 중입니다", isError: true)
            return false
        }

        let sourceStore = appState.webViewStore(for: sourcePanelIndex)
        let targetStore = appState.webViewStore(for: targetPanelIndex)
        let copyStartedAt = Date()

        if sourcePanelIndex == 0, targetPanelIndex == 1 {
            lastTwoPanelCrossSendDirection = .firstToSecond
        } else if sourcePanelIndex == 1, targetPanelIndex == 0 {
            lastTwoPanelCrossSendDirection = .secondToFirst
        }

        isTwoPanelCrossSendInFlight = true
        defer {
            isTwoPanelCrossSendInFlight = false
        }

        setCollectionStatus(
            "패널 \(sourcePanelIndex + 1) 답변을 패널 \(targetPanelIndex + 1)로 전송 중",
            isError: false
        )

        let copyResult = await sourceStore.triggerAssistantAnswerCopy(targetOffset: 0)
        switch copyResult {
        case let .failure(error):
            setCollectionStatus("패널 \(sourcePanelIndex + 1) 최신 답변 복사 실패: \(error.localizedDescription)", isError: true)
            return false
        case .success:
            break
        }

        guard let copiedText = await waitForFreshCopiedResponse(
            from: sourceStore,
            panelIndex: sourcePanelIndex,
            notBefore: copyStartedAt
        ) else {
            setCollectionStatus("패널 \(sourcePanelIndex + 1) 최신 답변을 감지하지 못했습니다", isError: true)
            return false
        }

        let prepareResult = await targetStore.prepareComposerForInput()
        if case let .failure(error) = prepareResult {
            setCollectionStatus("패널 \(targetPanelIndex + 1) 입력창 준비 실패: \(error.localizedDescription)", isError: true)
            return false
        }

        let insertResult = await targetStore.sendTextToComposer(copiedText, submit: false)
        switch insertResult {
        case let .success(insertResponse):
            guard insertResponse.inserted else {
                setCollectionStatus("패널 \(targetPanelIndex + 1)에 답변 입력 실패", isError: true)
                return false
            }

            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return false }
            let submitResult = await targetStore.submitPreparedComposer()
            switch submitResult {
            case let .success(result):
                if result.submitted {
                    setCollectionStatus("패널 \(sourcePanelIndex + 1) 답변을 패널 \(targetPanelIndex + 1)로 전송 완료", isError: false)
                    return true
                }

                setCollectionStatus(
                    "패널 \(sourcePanelIndex + 1) 답변을 패널 \(targetPanelIndex + 1)에 입력 완료 (제출 확인 필요)",
                    isError: true
                )
                return true
            case let .failure(error):
                setCollectionStatus("패널 \(targetPanelIndex + 1) 제출 실패: \(error.localizedDescription)", isError: true)
                return false
            }
        case let .failure(error):
            setCollectionStatus("패널 \(targetPanelIndex + 1) 전송 실패: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    @MainActor
    private func waitForFreshCopiedResponse(
        from store: WebViewStore,
        panelIndex: Int,
        notBefore date: Date
    ) async -> String? {
        for _ in 0..<10 {
            if let copied = store.lastCopiedAssistantResponse,
               copied.capturedAt >= date
            {
                return copied.text
            }

            if let collected = appState.collectedResponse(for: panelIndex),
               collected.capturedAt >= date
            {
                return collected.text
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return nil }
        }
        return nil
    }

    private func sendCollectedResponses(toPanel panelIndex: Int, updateAnalysisTarget: Bool) {
        guard panelIndex >= 0, panelIndex < appState.panelCount else {
            setCollectionStatus("대상 패널이 유효하지 않습니다", isError: true)
            return
        }

        if updateAnalysisTarget {
            appState.setAnalysisTargetPanelIndex(panelIndex)
        }

        let targetStore = appState.webViewStore(for: panelIndex)
        guard let prompt = appState.buildCollectedResponsesAnalysisPrompt() else {
            Task {
                let result = await targetStore.prepareComposerForInput()
                switch result {
                case let .success(prepareResult):
                    if prepareResult.focused {
                        setCollectionStatus("패널 \(panelIndex + 1)을 분석 대상으로 지정했습니다", isError: false)
                    } else {
                        setCollectionStatus("패널 \(panelIndex + 1)을 분석 대상으로 지정했습니다 (입력창 준비 결과 확인 필요)", isError: true)
                    }
                case let .failure(error):
                    setCollectionStatus("패널 \(panelIndex + 1) 분석 대상 지정 완료, 입력창 준비 실패: \(error.localizedDescription)", isError: true)
                }
            }
            return
        }

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

    private func triggerTemporaryChat(for panelIndex: Int) {
        guard panelIndex >= 0, panelIndex < appState.panelCount else {
            setCollectionStatus("패널 인덱스가 유효하지 않습니다", isError: true)
            return
        }

        let store = appState.webViewStore(for: panelIndex)
        Task {
            let result = await store.triggerTemporaryChat()
            switch result {
            case let .success(clickResult):
                if clickResult.clicked {
                    setCollectionStatus("패널 \(panelIndex + 1) 임시채팅 버튼 클릭 완료", isError: false)
                } else {
                    setCollectionStatus("패널 \(panelIndex + 1) 임시채팅 결과 확인 필요", isError: true)
                }
            case let .failure(error):
                setCollectionStatus("패널 \(panelIndex + 1) 임시채팅 실패: \(error.localizedDescription)", isError: true)
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

    private func initializeQuickComposeTargetsIfNeeded() {
        guard quickComposeKnownPanelCount == 0 else { return }
        quickComposeKnownPanelCount = appState.panelCount
        quickComposeTargetPanels = Set(0 ..< appState.panelCount)
    }

    private func closePanel(at panelIndex: Int) {
        guard appState.panelCount > AppState.minPanels else {
            setCollectionStatus("패널이 1개일 때는 닫을 수 없습니다", isError: true)
            return
        }

        let remappedTargets = Set(
            quickComposeTargetPanels.compactMap { index -> Int? in
                guard index != panelIndex else { return nil }
                return index > panelIndex ? index - 1 : index
            }
        )
        quickComposeTargetPanels = remappedTargets
        quickComposeKnownPanelCount = max(AppState.minPanels, appState.panelCount - 1)
        if quickComposeKnownPanelCount < 2 {
            lastTwoPanelCrossSendDirection = nil
        }

        appState.removePanel(at: panelIndex)
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
                let prepareResult = await store.prepareComposerForInput()
                if case .failure = prepareResult {
                    failedCount += 1
                    continue
                }

                let insertResult = await store.sendTextToComposer(trimmed, submit: false)
                switch insertResult {
                case let .success(insertResponse):
                    guard insertResponse.inserted else {
                        failedCount += 1
                        continue
                    }

                    try? await Task.sleep(nanoseconds: 320_000_000)
                    let submitResult = await store.submitPreparedComposer()
                    switch submitResult {
                    case let .success(sendResult):
                        if sendResult.submitted {
                            submittedCount += 1
                        } else {
                            insertedOnlyCount += 1
                        }
                    case .failure:
                        insertedOnlyCount += 1
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

    private func presetSelectionLabel(
        title: String,
        isSelected: Bool
    ) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
            .foregroundStyle(Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isSelected ? Color.secondary.opacity(0.45) : Color.secondary.opacity(0.25),
                        lineWidth: 1
                    )
            )
    }

}
