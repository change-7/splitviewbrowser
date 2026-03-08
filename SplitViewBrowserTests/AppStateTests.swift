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
    func testBuiltInServicesIncludeGrokAndAutoCopyDefaults() {
        XCTAssertTrue(AIService.builtInServices.contains(where: { $0.id == AIService.grok.id }))
        XCTAssertEqual(AIService.legacyID(from: "grok"), AIService.grok.id)

        let config = AutoCopyCatalog.defaultConfiguration(for: AIService.grok)
        XCTAssertEqual(config.supportLevel, .supported)
        let rule = try? XCTUnwrap(config.rule)
        XCTAssertNotNil(rule)
        XCTAssertTrue(rule?.sendButtonSelectors.contains(where: { $0.contains("data-testid") }) ?? false)
        XCTAssertFalse(rule?.sendButtonSelectors.contains("button[role='button']") ?? true)
    }

    @MainActor
    func testBackupRoundTripRestoresKeyState() throws {
        let sourceDefaults = makeDefaults()
        let source = AppState(defaults: sourceDefaults)

        source.setPanelCount(4)
        source.setWebViewRetentionMode(.aggressive)
        try source.addCustomService(title: "Example", urlString: "https://example.com")

        if let custom = source.customServices.first {
            source.updateAutoCopyProfile(
                for: custom.id,
                profile: AutoCopySiteProfile(
                    supportLevel: .limited,
                    composerSelectors: ["textarea"],
                    sendButtonSelectors: ["button[type='submit']"],
                    sendPattern: "send|submit",
                    enableEnterKey: false
                )
            )
            source.setService(custom, at: 0)
        }

        let savedPrompt = try source.savePrompt(title: "Translate", text: "Translate to Korean", tags: ["lang"], isFavorite: true)
        source.setSelectedAnalysisPromptID(savedPrompt.id)
        _ = try source.saveCurrentPreset(name: "Grid4", windowSize: CGSize(width: 1700, height: 900))

        let backup = try source.exportBackupData()

        let targetDefaults = makeDefaults()
        let target = AppState(defaults: targetDefaults)
        try target.importBackupData(backup)

        XCTAssertEqual(target.panelCount, 4)
        XCTAssertEqual(target.webViewRetentionMode, .aggressive)
        XCTAssertFalse(target.customServices.isEmpty)
        XCTAssertEqual(target.savedPrompts.count, 1)
        XCTAssertEqual(target.savedPrompts.first?.tags, ["lang"])
        XCTAssertTrue(target.savedPrompts.first?.isFavorite ?? false)
        XCTAssertEqual(target.selectedAnalysisPromptID, target.savedPrompts.first?.id)
        XCTAssertEqual(target.presets.first?.name, "Grid4")

        if let custom = target.customServices.first {
            let profile = target.autoCopyProfile(for: custom)
            XCTAssertEqual(profile.supportLevel, .limited)
            XCTAssertEqual(profile.composerSelectors ?? [], ["textarea"])
            XCTAssertEqual(profile.enableEnterKey, false)
        } else {
            XCTFail("Custom service missing after import")
        }
    }
}
