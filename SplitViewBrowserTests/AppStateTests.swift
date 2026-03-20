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
        XCTAssertEqual(state.savedPrompts.count, 1)
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
            sourceURLString: "https://chatgpt.com/",
            text: "답변 A"
        )
        state.collectPanelResponse(
            panelIndex: 1,
            service: .gemini,
            sourceURLString: "https://gemini.google.com/",
            text: "답변 B"
        )

        let prompt = state.buildCollectedResponsesAnalysisPrompt()
        XCTAssertNotNil(prompt)
        XCTAssertEqual(state.visibleCollectedResponseCount, 2)
        XCTAssertTrue(prompt?.contains("패널 1 - ChatGPT") ?? false)
        XCTAssertTrue(prompt?.contains("패널 2 - Gemini") ?? false)
        XCTAssertTrue(prompt?.contains("사실 여부를 검증") ?? false)
        XCTAssertTrue(prompt?.contains("실시간 정보 검증 결과") ?? false)
        XCTAssertTrue(prompt?.contains("공식문서/공식발표 > 신뢰할 수 있는 뉴스") ?? false)
        XCTAssertTrue(prompt?.contains("속보성 이슈/사건은 공식문서가 늦을 수 있으므로") ?? false)
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
            sourceURLString: "https://chatgpt.com/",
            text: "답변 A"
        )

        let overridden = state.buildCollectedResponsesAnalysisPrompt()
        XCTAssertTrue(overridden?.hasPrefix("커스텀 분석 프롬프트 헤더") ?? false)
        XCTAssertTrue(overridden?.contains("패널 1 - ChatGPT") ?? false)

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
    func testAddPanelUsesLastVisibleServiceWhenAllBuiltInServicesAlreadyVisible() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        state.setPanelCount(4)
        state.setService(.chatGPT, at: 0)
        state.setService(.gemini, at: 1)
        state.setService(.perplexity, at: 2)
        state.setService(.grok, at: 3)
        state.addPanel()

        XCTAssertEqual(state.panelCount, 5)
        XCTAssertEqual(state.service(at: 4).id, AIService.grok.id)
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
    func testRemovePanelReindexesServicesResponsesAndAnalysisTarget() {
        let defaults = makeDefaults()
        let state = AppState(defaults: defaults)

        state.setPanelCount(4)
        state.setService(.chatGPT, at: 0)
        state.setService(.gemini, at: 1)
        state.setService(.grok, at: 2)
        state.setService(.perplexity, at: 3)
        state.setAnalysisTargetPanelIndex(2)

        state.collectPanelResponse(panelIndex: 1, service: .gemini, sourceURLString: "https://gemini.google.com/", text: "B")
        state.collectPanelResponse(panelIndex: 2, service: .grok, sourceURLString: "https://grok.com/", text: "C")
        state.collectPanelResponse(panelIndex: 3, service: .perplexity, sourceURLString: "https://www.perplexity.ai/", text: "D")

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
    func testBuiltInServicesIncludeGrokAndLegacyMapping() {
        XCTAssertTrue(AIService.builtInServices.contains(where: { $0.id == AIService.grok.id }))
        XCTAssertEqual(AIService.legacyID(from: "grok"), AIService.grok.id)
    }

    func testBuiltInServiceTrustedHosts() {
        XCTAssertTrue(AIService.chatGPT.trustsHost("chatgpt.com"))
        XCTAssertTrue(AIService.chatGPT.trustsHost("auth.openai.com"))
        XCTAssertTrue(AIService.gemini.trustsHost("accounts.google.com"))
        XCTAssertTrue(AIService.perplexity.trustsHost("www.perplexity.ai"))
        XCTAssertTrue(AIService.grok.trustsHost("grok.com"))
        XCTAssertFalse(AIService.chatGPT.trustsHost("example.com"))
    }

}
