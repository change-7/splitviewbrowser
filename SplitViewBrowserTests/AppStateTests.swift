import XCTest
@testable import SplitViewBrowser

final class AppStateTests: XCTestCase {
    private func makeDefaults(_ testName: String = #function) -> UserDefaults {
        let suite = "SplitViewBrowserTests.\(testName).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @MainActor
    func testPromptSaveUpdateFavoriteAndTags() throws {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)
        let builtInCount = AppState.builtInAnalysisPromptTemplates.count

        let saved = try state.savePrompt(
            title: "Code Review",
            text: "Please review this diff",
            tags: ["work", "review", "Work"],
            isFavorite: true
        )

        XCTAssertEqual(saved.tags, ["work", "review"])
        XCTAssertTrue(saved.isFavorite)

        let updated = try state.updateSavedPrompt(
            id: saved.id,
            title: "Code Review Updated",
            text: "Please review this diff carefully",
            tags: ["bug", "urgent"],
            isFavorite: false
        )

        XCTAssertEqual(updated.title, "Code Review Updated")
        XCTAssertEqual(updated.tags, ["bug", "urgent"])
        XCTAssertFalse(updated.isFavorite)
        XCTAssertEqual(state.savedPrompts.count, builtInCount + 1)
    }

    @MainActor
    func testLockedPresetCannotBeOverwritten() throws {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        _ = try state.saveCurrentPreset(name: "Work")
        guard let preset = state.presets.first(where: { $0.name == "Work" }) else {
            return XCTFail("Preset not created")
        }

        state.setPresetLocked(id: preset.id, isLocked: true)

        XCTAssertThrowsError(try state.saveCurrentPreset(name: "Work")) { error in
            guard let presetError = error as? AppState.PresetValidationError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            XCTAssertEqual(presetError.errorDescription, AppState.PresetValidationError.lockedPreset.errorDescription)
        }
    }

    @MainActor
    func testActivePresetUpdatesWhenCurrentStateChanges() throws {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        _ = try state.saveCurrentPreset(name: "Preset A")
        guard let preset = state.presets.first(where: { $0.name == "Preset A" }) else {
            return XCTFail("Preset not created")
        }

        state.applyPreset(id: preset.id)
        XCTAssertEqual(state.activePresetID, preset.id)

        state.setPanelCount(4)
        state.setService(.perplexity, at: 0)

        guard let updated = state.presets.first(where: { $0.id == preset.id }) else {
            return XCTFail("Updated preset missing")
        }

        XCTAssertEqual(updated.panelCount, 4)
        XCTAssertEqual(updated.panelServiceIDs.first, AIService.perplexity.id)
        XCTAssertEqual(state.activePresetID, preset.id)
    }

    @MainActor
    func testActivePresetUpdatesWindowSize() throws {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        _ = try state.saveCurrentPreset(name: "Window Preset", windowSize: CGSize(width: 1200, height: 800))
        guard let preset = state.presets.first(where: { $0.name == "Window Preset" }) else {
            return XCTFail("Preset not created")
        }

        state.applyPreset(id: preset.id)
        state.syncActivePresetWindowSize(CGSize(width: 1400, height: 900))

        guard let updated = state.presets.first(where: { $0.id == preset.id }) else {
            return XCTFail("Updated preset missing")
        }

        let width = try XCTUnwrap(updated.windowWidth)
        let height = try XCTUnwrap(updated.windowHeight)
        XCTAssertEqual(width, 1400, accuracy: 0.6)
        XCTAssertEqual(height, 900, accuracy: 0.6)
        XCTAssertEqual(state.activePresetID, preset.id)
    }

    @MainActor
    func testCollectedResponsesBuildAnalysisPrompt() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        state.collectPanelResponse(
            panelIndex: 0,
            service: .chatGPT,
            text: "답변 A"
        )
        state.collectPanelResponse(
            panelIndex: 1,
            service: .gemini,
            text: "답변 B"
        )

        let prompt = state.buildCollectedResponsesAnalysisPrompt()
        XCTAssertNotNil(prompt)
        XCTAssertEqual(state.visibleCollectedResponseCount, 2)
        XCTAssertTrue(prompt?.contains("사실 여부를 검증") ?? false)
        XCTAssertTrue(prompt?.contains("실시간 정보 검증 결과") ?? false)
        XCTAssertTrue(prompt?.contains("공식문서/공식발표 > 신뢰할 수 있는 뉴스") ?? false)
        XCTAssertTrue(prompt?.contains("속보성 이슈/사건은 공식문서가 늦을 수 있으므로") ?? false)
        XCTAssertTrue(prompt?.contains("답변 A") ?? false)
        XCTAssertTrue(prompt?.contains("답변 B") ?? false)
        XCTAssertFalse(prompt?.contains("패널 1 - ChatGPT") ?? false)
        XCTAssertFalse(prompt?.contains("https://chatgpt.com/") ?? false)
        XCTAssertFalse(prompt?.contains("수집 시각") ?? false)
    }

    @MainActor
    func testSelectedSavedPromptOverridesDefaultCollectedResponseHeader() throws {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)
        let customPrompt = try state.savePrompt(
            title: "Deep Verify",
            text: "커스텀 분석 프롬프트 헤더",
            tags: [],
            isFavorite: false
        )
        state.setSelectedAnalysisPromptID(customPrompt.id)

        state.collectPanelResponse(
            panelIndex: 0,
            service: .chatGPT,
            text: "답변 A"
        )

        let overridden = state.buildCollectedResponsesAnalysisPrompt()
        XCTAssertTrue(overridden?.hasPrefix("커스텀 분석 프롬프트 헤더") ?? false)
        XCTAssertTrue(overridden?.contains("답변 A") ?? false)
        XCTAssertFalse(overridden?.contains("패널 1 - ChatGPT") ?? false)

        state.removeSavedPrompt(id: customPrompt.id)
        let fallback = state.buildCollectedResponsesAnalysisPrompt()
        XCTAssertNil(state.selectedAnalysisPromptID)
        XCTAssertTrue(fallback?.contains("사실 여부를 검증") ?? false)
    }

    @MainActor
    func testAnalysisTargetPanelClampsAfterPanelCountReduction() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        state.setPanelCount(5)
        state.setAnalysisTargetPanelIndex(4)
        XCTAssertEqual(state.analysisTargetPanelIndex, 4)

        state.setPanelCount(2)
        XCTAssertEqual(state.analysisTargetPanelIndex, 1)
    }

    @MainActor
    func testAddPanelAppendsNewLastPanelAndPersistsState() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        state.setPanelCount(2)
        state.setService(.chatGPT, at: 0)
        state.setService(.gemini, at: 1)
        state.addPanel()

        XCTAssertEqual(state.panelCount, 3)
        XCTAssertEqual(state.service(at: 0).id, AIService.chatGPT.id)
        XCTAssertEqual(state.service(at: 1).id, AIService.gemini.id)
        XCTAssertEqual(state.service(at: 2).id, AIService.perplexity.id)

        let restored = AppState(defaults: defaults)
        XCTAssertEqual(restored.panelCount, 3)
        XCTAssertEqual(restored.service(at: 0).id, AIService.chatGPT.id)
        XCTAssertEqual(restored.service(at: 1).id, AIService.gemini.id)
        XCTAssertEqual(restored.service(at: 2).id, AIService.perplexity.id)
    }

    @MainActor
    func testAddPanelAfterMiddleRemovalKeepsOrderAndAppendsDefault() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        state.setPanelCount(4)
        state.setService(.chatGPT, at: 0)
        state.setService(.gemini, at: 1)
        state.setService(.grok, at: 2)
        state.setService(.perplexity, at: 3)
        state.removePanel(at: 1)
        state.addPanel()

        XCTAssertEqual(state.panelCount, 4)
        XCTAssertEqual(state.service(at: 0).id, AIService.chatGPT.id)
        XCTAssertEqual(state.service(at: 1).id, AIService.grok.id)
        XCTAssertEqual(state.service(at: 2).id, AIService.perplexity.id)
        XCTAssertEqual(state.service(at: 3).id, AIService.gemini.id)
    }

    @MainActor
    func testAddPanelPrefersClaudeAfterPerplexity() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        state.setPanelCount(4)
        state.setService(.chatGPT, at: 0)
        state.setService(.gemini, at: 1)
        state.setService(.perplexity, at: 2)
        state.setService(.grok, at: 3)
        state.addPanel()

        XCTAssertEqual(state.panelCount, 5)
        XCTAssertEqual(state.service(at: 4).id, AIService.claude.id)
    }

    @MainActor
    func testPanelStructureVersionChangesWhenPanelsAreAddedOrRemoved() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        let initialVersion = state.panelStructureVersion
        state.addPanel()
        XCTAssertEqual(state.panelStructureVersion, initialVersion + 1)

        let afterAddVersion = state.panelStructureVersion
        state.removePanel(at: 1)
        XCTAssertEqual(state.panelStructureVersion, afterAddVersion + 1)
    }

    @MainActor
    func testServiceChangeRecreatesPanelStoreWithoutChangingPanelSlotIdentity() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        let initialSlotID = state.panelSlots[0].id
        let initialStore = state.webViewStore(for: 0)
        let initialVersion = state.panelStructureVersion

        state.setService(.gemini, at: 0)

        let recreatedStore = state.webViewStore(for: 0)
        XCTAssertFalse(initialStore === recreatedStore)
        XCTAssertEqual(state.panelSlots[0].id, initialSlotID)
        XCTAssertEqual(state.panelStructureVersion, initialVersion)
        XCTAssertEqual(state.service(at: 0).id, AIService.gemini.id)
    }

    @MainActor
    func testRemovingMiddlePanelKeepsRemainingPanelSlotsAndStoresStable() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        state.setPanelCount(3)
        state.setService(.chatGPT, at: 0)
        state.setService(.gemini, at: 1)
        state.setService(.grok, at: 2)

        let firstSlotID = state.panelSlots[0].id
        let middleSlotID = state.panelSlots[1].id
        let lastSlotID = state.panelSlots[2].id
        let firstStore = state.webViewStore(for: 0)
        let middleStore = state.webViewStore(for: 1)
        let lastStore = state.webViewStore(for: 2)

        state.removePanel(at: 1)

        XCTAssertEqual(state.panelCount, 2)
        XCTAssertEqual(state.panelSlots[0].id, firstSlotID)
        XCTAssertEqual(state.panelSlots[1].id, lastSlotID)
        XCTAssertNotEqual(state.panelSlots[2].id, middleSlotID)
        XCTAssertTrue(state.webViewStore(for: 0) === firstStore)
        XCTAssertTrue(state.webViewStore(for: 1) === lastStore)
        XCTAssertFalse(state.webViewStore(for: 1) === middleStore)
        XCTAssertEqual(state.service(at: 0).id, AIService.chatGPT.id)
        XCTAssertEqual(state.service(at: 1).id, AIService.grok.id)
    }

    @MainActor
    func testServiceChangeCanPreserveExistingPanelStore() {
        let defaults = makeDefaults()
        defaults.set(PanelServiceChangeStorePolicy.preserveSession.rawValue, forKey: "panelServiceChangeStorePolicy")
        let state = AppState(defaults: defaults)

        let initialStore = state.webViewStore(for: 0)
        let initialVersion = state.panelStructureVersion

        state.setService(.gemini, at: 0)

        let preservedStore = state.webViewStore(for: 0)
        XCTAssertTrue(initialStore === preservedStore)
        XCTAssertEqual(state.panelStructureVersion, initialVersion)
        XCTAssertEqual(state.panelServiceChangeStorePolicy, .preserveSession)
        XCTAssertEqual(state.service(at: 0).id, AIService.gemini.id)
    }

    @MainActor
    func testRemovePanelReindexesServicesResponsesAndAnalysisTarget() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        state.setPanelCount(4)
        state.setService(.chatGPT, at: 0)
        state.setService(.gemini, at: 1)
        state.setService(.grok, at: 2)
        state.setService(.perplexity, at: 3)
        state.setAnalysisTargetPanelIndex(2)

        state.collectPanelResponse(panelIndex: 1, service: .gemini, text: "B")
        state.collectPanelResponse(panelIndex: 2, service: .grok, text: "C")
        state.collectPanelResponse(panelIndex: 3, service: .perplexity, text: "D")

        state.removePanel(at: 1)

        XCTAssertEqual(state.panelCount, 3)
        XCTAssertEqual(state.service(at: 0).id, AIService.chatGPT.id)
        XCTAssertEqual(state.service(at: 1).id, AIService.grok.id)
        XCTAssertEqual(state.service(at: 2).id, AIService.perplexity.id)
        XCTAssertEqual(state.analysisTargetPanelIndex, 1)
        XCTAssertNil(state.collectedResponse(for: 0))
        XCTAssertEqual(state.collectedResponse(for: 1)?.text, "C")
        XCTAssertEqual(state.collectedResponse(for: 2)?.text, "D")
    }

    @MainActor
    func testRemoveTargetPanelAssignsNextValidPanelAndPersistsState() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        state.setPanelCount(3)
        state.setService(.chatGPT, at: 0)
        state.setService(.gemini, at: 1)
        state.setService(.grok, at: 2)
        state.setAnalysisTargetPanelIndex(1)
        state.removePanel(at: 1)

        XCTAssertEqual(state.panelCount, 2)
        XCTAssertEqual(state.analysisTargetPanelIndex, 1)
        XCTAssertEqual(state.service(at: 0).id, AIService.chatGPT.id)
        XCTAssertEqual(state.service(at: 1).id, AIService.grok.id)

        let restored = AppState(defaults: defaults)
        XCTAssertEqual(restored.panelCount, 2)
        XCTAssertEqual(restored.service(at: 0).id, AIService.chatGPT.id)
        XCTAssertEqual(restored.service(at: 1).id, AIService.grok.id)
    }

    @MainActor
    func testBuiltInServicesIncludeClaudeAndLegacyMapping() {
        XCTAssertTrue(AIService.builtInServices.contains(where: { $0.id == AIService.claude.id }))
        XCTAssertEqual(AIService.legacyID(from: "claude"), AIService.claude.id)
        XCTAssertTrue(AIService.builtInServices.contains(where: { $0.id == AIService.grok.id }))
        XCTAssertEqual(AIService.legacyID(from: "grok"), AIService.grok.id)
    }

    func testBuiltInServiceTrustedHosts() {
        XCTAssertTrue(AIService.chatGPT.trustsHost("chatgpt.com"))
        XCTAssertTrue(AIService.chatGPT.trustsHost("auth.openai.com"))
        XCTAssertTrue(AIService.gemini.trustsHost("accounts.google.com"))
        XCTAssertTrue(AIService.perplexity.trustsHost("www.perplexity.ai"))
        XCTAssertTrue(AIService.claude.trustsHost("claude.ai"))
        XCTAssertTrue(AIService.grok.trustsHost("grok.com"))
        XCTAssertFalse(AIService.chatGPT.trustsHost("example.com"))
    }

    @MainActor
    func testBuiltInAnalysisPromptTemplatesSeedOnlyOnce() {
        let defaults = makeDefaults()

        let first = AppState(defaults: defaults)
        XCTAssertEqual(first.savedPrompts.filter(\.isBuiltIn).count, AppState.builtInAnalysisPromptTemplates.count)
        XCTAssertEqual(first.savedPrompts.first(where: { $0.id == "builtin-prompt-integrated-answer" })?.title, "통합 답변형")

        let second = AppState(defaults: defaults)
        XCTAssertEqual(second.savedPrompts.filter(\.isBuiltIn).count, AppState.builtInAnalysisPromptTemplates.count)
        XCTAssertEqual(second.savedPrompts.count, AppState.builtInAnalysisPromptTemplates.count)
        XCTAssertEqual(second.savedPrompts.first(where: { $0.id == "builtin-prompt-practical-conclusion" })?.title, "실무 결론형")
    }

    @MainActor
    func testLegacySavedPromptsRestoreAlongsideBuiltInSeed() throws {
        struct LegacySavedPrompt: Codable {
            let id: String
            let title: String
            let text: String
            let tags: [String]
            let isFavorite: Bool
            let updatedAt: Date?
        }

        let defaults = makeDefaults()
        let legacyPrompt = LegacySavedPrompt(
            id: "legacy-user-prompt",
            title: "사용자 프롬프트",
            text: "사용자 본문",
            tags: ["사용자"],
            isFavorite: true,
            updatedAt: nil
        )
        let data = try JSONEncoder().encode([legacyPrompt])
        defaults.set(data, forKey: "savedPrompts")

        let state = AppState(defaults: defaults)

        XCTAssertEqual(state.savedPrompts.count, AppState.builtInAnalysisPromptTemplates.count + 1)
        XCTAssertTrue(state.savedPrompts.contains(where: { $0.id == "legacy-user-prompt" && !$0.isBuiltIn }))
    }

    @MainActor
    func testSelectedBuiltInAnalysisPromptIsUsedForCollectedResponseHeader() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)
        let builtIn = AppState.builtInAnalysisPromptTemplates[0]

        state.setSelectedAnalysisPromptID(builtIn.id)
        state.collectPanelResponse(
            panelIndex: 0,
            service: .chatGPT,
            text: "답변 A"
        )

        let prompt = state.buildCollectedResponsesAnalysisPrompt()
        XCTAssertEqual(state.selectedAnalysisPromptID, builtIn.id)
        XCTAssertTrue(prompt?.hasPrefix(builtIn.text) ?? false)
        XCTAssertTrue(prompt?.contains("답변 A") ?? false)
    }

    @MainActor
    func testRestoreBuiltInAnalysisPromptTemplatesOnlyAddsMissingOnes() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)
        let removedID = AppState.builtInAnalysisPromptTemplates[0].id

        state.removeSavedPrompt(id: removedID)
        XCTAssertTrue(state.hasMissingBuiltInAnalysisPromptTemplates)

        let restoredCount = state.restoreBuiltInAnalysisPromptTemplates()
        XCTAssertEqual(restoredCount, 1)
        XCTAssertEqual(state.savedPrompts.filter(\.isBuiltIn).count, AppState.builtInAnalysisPromptTemplates.count)
    }

    @MainActor
    func testBuiltInAnalysisPromptTemplatesUpgradeExistingSeededTemplates() throws {
        let defaults = makeDefaults()

        let legacyBuiltIn = SavedPrompt(
            id: "builtin-prompt-integrated-answer",
            title: "통합 답변",
            text: "예전 통합 템플릿",
            tags: ["예전"],
            isFavorite: true,
            isBuiltIn: true,
            updatedAt: nil
        )

        let data = try JSONEncoder().encode([legacyBuiltIn])
        defaults.set(data, forKey: "savedPrompts")
        defaults.set(1, forKey: "builtInAnalysisPromptTemplatesSeedVersion")

        let state = AppState(defaults: defaults)

        let upgraded = try XCTUnwrap(state.savedPrompts.first(where: { $0.id == "builtin-prompt-integrated-answer" }))
        XCTAssertEqual(upgraded.title, "통합 답변형")
        XCTAssertNotEqual(upgraded.text, "예전 통합 템플릿")
        XCTAssertEqual(upgraded.tags, ["비교", "통합"])
        XCTAssertTrue(upgraded.isBuiltIn)
        XCTAssertTrue(upgraded.isFavorite)
        XCTAssertEqual(state.savedPrompts.filter(\.isBuiltIn).count, AppState.builtInAnalysisPromptTemplates.count)
    }

}
