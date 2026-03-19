import AppKit
import Foundation

struct ViewPreset: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var panelCount: Int
    var panelServiceIDs: [String]
    var windowWidth: Double?
    var windowHeight: Double?
    var isLocked: Bool
    var updatedAt: Date?

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        panelCount: Int,
        panelServiceIDs: [String],
        windowWidth: Double? = nil,
        windowHeight: Double? = nil,
        isLocked: Bool = false,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.panelCount = panelCount
        self.panelServiceIDs = panelServiceIDs
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.isLocked = isLocked
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case panelCount
        case panelServiceIDs
        case windowWidth
        case windowHeight
        case isLocked
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        name = try container.decode(String.self, forKey: .name)
        panelCount = try container.decode(Int.self, forKey: .panelCount)
        panelServiceIDs = try container.decode([String].self, forKey: .panelServiceIDs)
        windowWidth = try container.decodeIfPresent(Double.self, forKey: .windowWidth)
        windowHeight = try container.decodeIfPresent(Double.self, forKey: .windowHeight)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct SavedPrompt: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var text: String
    var tags: [String]
    var isFavorite: Bool
    var updatedAt: Date?

    init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        text: String,
        tags: [String] = [],
        isFavorite: Bool = false,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.tags = tags
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case text
        case tags
        case isFavorite
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        title = try container.decode(String.self, forKey: .title)
        text = try container.decode(String.self, forKey: .text)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct CollectedPanelResponse: Identifiable, Hashable {
    var id: Int { panelIndex }
    let panelIndex: Int
    let serviceID: String
    let serviceTitle: String
    let sourceURLString: String?
    let text: String
    let capturedAt: Date
}

enum WebViewRetentionMode: String, CaseIterable, Codable, Identifiable {
    case aggressive
    case balanced
    case keepAlive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aggressive:
            return "즉시 정리"
        case .balanced:
            return "균형"
        case .keepAlive:
            return "항상 유지"
        }
    }

    var summary: String {
        switch self {
        case .aggressive:
            return "패널을 줄이면 숨겨진 웹뷰를 바로 해제"
        case .balanced:
            return "숨겨진 웹뷰를 일정 시간 보관 후 정리"
        case .keepAlive:
            return "숨겨진 웹뷰도 최대한 유지 (메모리 사용량 증가)"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    private enum WebViewRetentionPolicy {
        static let hiddenTTL: TimeInterval = 10 * 60
        static let maxHiddenStores = 3
    }

    private static let responseTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    enum SiteValidationError: LocalizedError {
        case emptyTitle
        case invalidURL
        case builtInDeletionNotAllowed

        var errorDescription: String? {
            switch self {
            case .emptyTitle:
                return "Site name is required."
            case .invalidURL:
                return "Enter a valid URL. Example: https://example.com"
            case .builtInDeletionNotAllowed:
                return "Built-in services cannot be removed."
            }
        }
    }

    enum PresetValidationError: LocalizedError {
        case emptyName
        case lockedPreset

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Preset name is required."
            case .lockedPreset:
                return "Locked preset cannot be overwritten."
            }
        }
    }

    enum PromptValidationError: LocalizedError {
        case emptyText
        case promptNotFound

        var errorDescription: String? {
            switch self {
            case .emptyText:
                return "Prompt text is required."
            case .promptNotFound:
                return "Prompt not found."
            }
        }
    }

    private enum DefaultsKey {
        static let panelCount = "panelCount"
        static let panelServices = "panelServices"
        static let customServices = "customServices"
        static let presets = "presets"
        static let savedPrompts = "savedPrompts"
        static let selectedAnalysisPromptID = "selectedAnalysisPromptID"
        static let activePresetID = "activePresetID"
        static let webViewRetentionMode = "webViewRetentionMode"
        static let twoPanelCrossSendEnabled = "twoPanelCrossSendEnabled"
    }

    static let minPanels = 1
    static let maxPanels = 5
    private static let fallbackServiceID = AIService.chatGPT.id

    @Published private(set) var panelCount: Int
    @Published private(set) var panelServiceIDs: [String]
    @Published private(set) var services: [AIService]
    @Published private(set) var presets: [ViewPreset]
    @Published private(set) var activePresetID: String?
    @Published private(set) var savedPrompts: [SavedPrompt]
    @Published private(set) var webViewRetentionMode: WebViewRetentionMode
    @Published private(set) var isTwoPanelCrossSendEnabled: Bool
    @Published private(set) var pendingPresetWindowSize: CGSize?
    private(set) var isAppActive: Bool
    @Published private(set) var collectedResponsesByPanel: [Int: CollectedPanelResponse]
    @Published private(set) var analysisTargetPanelIndex: Int
    @Published private(set) var selectedAnalysisPromptID: String?

    private let defaults: UserDefaults
    private var webViewStores: [Int: WebViewStore] = [:]
    private var servicesByID: [String: AIService] = [:]
    private var savedPromptsByID: [String: SavedPrompt] = [:]
    private var hiddenStoreSince: [Int: Date] = [:]
    private var hiddenStoreReleaseTasks: [Int: Task<Void, Never>] = [:]
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var defaultsWriteTasks: [String: Task<Void, Never>] = [:]
    private let defaultsWriteThrottleNanos: UInt64 = 350_000_000
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var isApplyingPreset = false
    let logger = AppLogger.shared

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedCount = defaults.object(forKey: DefaultsKey.panelCount) as? Int ?? 2
        let restoredServices = AIService.builtInServices + Self.restoreCustomServices(from: defaults)
        let initialPanelCount = Self.clampPanelCount(savedCount)
        let didClampPanelCount = savedCount != initialPanelCount
        panelCount = initialPanelCount
        panelServiceIDs = Self.restorePanelServiceIDs(from: defaults)
        services = restoredServices
        presets = Self.restorePresets(from: defaults)
        activePresetID = Self.restoreActivePresetID(from: defaults)
        savedPrompts = Self.restoreSavedPrompts(from: defaults)
        selectedAnalysisPromptID = Self.restoreSelectedAnalysisPromptID(from: defaults)
        webViewRetentionMode = Self.restoreWebViewRetentionMode(from: defaults)
        isTwoPanelCrossSendEnabled = Self.restoreTwoPanelCrossSendEnabled(from: defaults)
        pendingPresetWindowSize = nil
        isAppActive = NSApp?.isActive ?? true
        collectedResponsesByPanel = [:]
        analysisTargetPanelIndex = max(0, initialPanelCount - 1)
        servicesByID = Dictionary(uniqueKeysWithValues: restoredServices.map { ($0.id, $0) })
        savedPromptsByID = Dictionary(uniqueKeysWithValues: savedPrompts.map { ($0.id, $0) })

        normalizeRestoredStateAndPersistIfNeeded(forcePersist: didClampPanelCount)
        configureMemoryPressureMonitoring()
        configureApplicationLifecycleMonitoring()
        logger.log(.info, category: "AppState", "Initialized with \(panelCount) panels, \(services.count) services")
    }

    deinit {
        for task in hiddenStoreReleaseTasks.values {
            task.cancel()
        }
        for task in defaultsWriteTasks.values {
            task.cancel()
        }
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        memoryPressureSource?.cancel()
    }

    func setPanelCount(_ count: Int) {
        let clamped = Self.clampPanelCount(count)
        guard clamped != panelCount else { return }
        let previousCount = panelCount
        panelCount = clamped
        persistPanelCount()

        reconcileWebViewStores(afterPanelCountChangeFrom: previousCount, to: panelCount)
        normalizeAnalysisTargetPanelIndex()
        pruneCollectedResponsesToVisiblePanels()
        syncActivePresetToCurrentStateIfNeeded()
        logger.log(.info, category: "Layout", "Panel count changed \(previousCount) -> \(panelCount)")
    }

    func addPanel() {
        guard panelCount < Self.maxPanels else { return }

        let previousCount = panelCount
        panelCount += 1
        panelServiceIDs = normalizedServiceIDs(from: panelServiceIDs)

        persistPanelCount()
        persistPanelServiceIDs()
        flushPendingDefaultWrites()
        markStoreActive(at: panelCount - 1)
        syncActivePresetToCurrentStateIfNeeded()
        clearActivePresetIfNoLongerMatchingCurrentState()
        logger.log(.info, category: "Layout", "Added panel \(panelCount) (\(previousCount) -> \(panelCount))")
    }

    func removePanel(at index: Int) {
        guard panelCount > Self.minPanels else { return }
        guard index >= 0, index < panelCount else { return }

        let previousCount = panelCount
        panelCount = max(Self.minPanels, panelCount - 1)
        panelServiceIDs = reindexedPanelServiceIDs(removing: index)
        remapCollectedResponses(removingPanelAt: index)
        remapAnalysisTargetIndex(removingPanelAt: index)
        remapWebViewStores(removingPanelAt: index)

        persistPanelCount()
        persistPanelServiceIDs()
        flushPendingDefaultWrites()
        syncActivePresetToCurrentStateIfNeeded()
        clearActivePresetIfNoLongerMatchingCurrentState()
        logger.log(.info, category: "Layout", "Removed panel \(index + 1) (\(previousCount) -> \(panelCount))")
    }

    func service(at index: Int) -> AIService {
        guard panelServiceIDs.indices.contains(index) else {
            return AIService.chatGPT
        }

        let selectedID = panelServiceIDs[index]
        return servicesByID[selectedID] ?? AIService.chatGPT
    }

    func setService(_ service: AIService, at index: Int) {
        guard panelServiceIDs.indices.contains(index) else { return }
        guard servicesByID[service.id] != nil else { return }
        guard panelServiceIDs[index] != service.id else { return }

        var updatedServiceIDs = panelServiceIDs
        updatedServiceIDs[index] = service.id
        panelServiceIDs = updatedServiceIDs
        persistPanelServiceIDs()
        syncActivePresetToCurrentStateIfNeeded()
    }

    func setAnalysisTargetPanelIndex(_ index: Int) {
        let clamped = max(0, min(panelCount - 1, index))
        guard analysisTargetPanelIndex != clamped else { return }
        analysisTargetPanelIndex = clamped
        logger.log(.info, category: "Collection", "Analysis target panel set to \(clamped + 1)")
    }

    func setSelectedAnalysisPromptID(_ id: String?) {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedID: String?
        if let normalizedID, !normalizedID.isEmpty, savedPromptsByID[normalizedID] != nil {
            resolvedID = normalizedID
        } else {
            resolvedID = nil
        }

        guard selectedAnalysisPromptID != resolvedID else { return }
        selectedAnalysisPromptID = resolvedID
        persistSelectedAnalysisPromptID()
    }

    var visibleCollectedResponses: [CollectedPanelResponse] {
        collectedResponsesByPanel.values
            .filter { $0.panelIndex < panelCount }
            .sorted { lhs, rhs in lhs.panelIndex < rhs.panelIndex }
    }

    var visibleCollectedResponseCount: Int {
        visibleCollectedResponses.count
    }

    var selectedAnalysisPrompt: SavedPrompt? {
        guard let selectedAnalysisPromptID else { return nil }
        return savedPromptsByID[selectedAnalysisPromptID]
    }

    var selectedAnalysisPromptDisplayTitle: String {
        selectedAnalysisPrompt?.title ?? "기본(내장)"
    }

    func collectedResponse(for panelIndex: Int) -> CollectedPanelResponse? {
        collectedResponsesByPanel[panelIndex]
    }

    func collectPanelResponse(
        panelIndex: Int,
        service: AIService,
        sourceURLString: String?,
        text: String
    ) {
        guard panelIndex >= 0, panelIndex < Self.maxPanels else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = collectedResponsesByPanel
        updated[panelIndex] = CollectedPanelResponse(
            panelIndex: panelIndex,
            serviceID: service.id,
            serviceTitle: service.title,
            sourceURLString: sourceURLString,
            text: trimmed,
            capturedAt: Date()
        )
        collectedResponsesByPanel = updated
        logger.log(.info, category: "Collection", "Collected latest response from panel \(panelIndex + 1) (\(service.title))")
    }

    func clearCollectedResponsesForVisiblePanels() {
        let visibleIndexes = Set(0 ..< panelCount)
        let filtered = collectedResponsesByPanel.filter { !visibleIndexes.contains($0.key) }
        guard filtered != collectedResponsesByPanel else { return }
        collectedResponsesByPanel = filtered
        logger.log(.info, category: "Collection", "Cleared collected responses for visible panels")
    }

    func buildCollectedResponsesAnalysisPrompt() -> String? {
        let responses = visibleCollectedResponses
        guard !responses.isEmpty else { return nil }
        let header = resolvedAnalysisPromptHeader()

        let body = responses.map { response in
            var lines: [String] = []
            lines.append("## 패널 \(response.panelIndex + 1) - \(response.serviceTitle)")
            if let sourceURLString = response.sourceURLString, !sourceURLString.isEmpty {
                lines.append("- URL: \(sourceURLString)")
            }
            lines.append("- 수집 시각: \(Self.responseTimestampFormatter.string(from: response.capturedAt))")
            lines.append("")
            lines.append(response.text)
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n---\n\n")

        return header + "\n\n" + body
    }

    func setWebViewRetentionMode(_ mode: WebViewRetentionMode) {
        guard webViewRetentionMode != mode else { return }
        webViewRetentionMode = mode
        persistWebViewRetentionMode()
        logger.log(.info, category: "WebViewRetention", "Retention mode changed to \(mode.rawValue)")

        switch mode {
        case .aggressive:
            releaseAllHiddenStores()
        case .balanced:
            pruneHiddenStoresToLimit()
        case .keepAlive:
            break
        }
    }

    func setTwoPanelCrossSendEnabled(_ isEnabled: Bool) {
        guard isTwoPanelCrossSendEnabled != isEnabled else { return }
        isTwoPanelCrossSendEnabled = isEnabled
        persistTwoPanelCrossSendEnabled()
        logger.log(.info, category: "Layout", "Two-panel cross send \(isEnabled ? "enabled" : "disabled")")
    }

    @discardableResult
    func saveCurrentPreset(name: String, windowSize: CGSize? = nil) throws -> ViewPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PresetValidationError.emptyName
        }

        let normalizedServices = normalizedServiceIDs(from: panelServiceIDs)
        let width = windowSize.map { Double($0.width) }
        let height = windowSize.map { Double($0.height) }
        var savedPreset: ViewPreset

        if let existingIndex = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            guard !presets[existingIndex].isLocked else {
                throw PresetValidationError.lockedPreset
            }
            presets[existingIndex].name = trimmed
            presets[existingIndex].panelCount = panelCount
            presets[existingIndex].panelServiceIDs = normalizedServices
            presets[existingIndex].windowWidth = width
            presets[existingIndex].windowHeight = height
            presets[existingIndex].updatedAt = Date()
            savedPreset = presets[existingIndex]
        } else {
            let newPreset = ViewPreset(
                name: trimmed,
                panelCount: panelCount,
                panelServiceIDs: normalizedServices,
                windowWidth: width,
                windowHeight: height,
                updatedAt: Date()
            )
            presets.append(newPreset)
            savedPreset = newPreset
        }

        persistPresets()
        logger.log(.info, category: "Preset", "Saved current state to preset \(savedPreset.name)")
        return savedPreset
    }

    @discardableResult
    func saveCurrentPresetWithAutoName(windowSize: CGSize? = nil) -> ViewPreset? {
        let name = nextAutoPresetName()
        return try? saveCurrentPreset(name: name, windowSize: windowSize)
    }

    func applyPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }

        if let width = preset.windowWidth, let height = preset.windowHeight {
            pendingPresetWindowSize = CGSize(width: width, height: height)
        } else {
            pendingPresetWindowSize = nil
        }

        isApplyingPreset = true
        defer { isApplyingPreset = false }

        updateActivePresetID(preset.id)
        let normalizedPresetServices = normalizedServiceIDs(from: preset.panelServiceIDs)
        if normalizedPresetServices != panelServiceIDs {
            panelServiceIDs = normalizedPresetServices
            persistPanelServiceIDs()
        }
        setPanelCount(preset.panelCount)
        logger.log(.info, category: "Preset", "Applied preset \(preset.name)")
    }

    func removePreset(id: String) {
        guard let existing = presets.first(where: { $0.id == id }) else { return }
        guard !existing.isLocked else { return }
        presets.removeAll(where: { $0.id == id })
        persistPresets()
        if activePresetID == id {
            updateActivePresetID(nil)
        }
        logger.log(.info, category: "Preset", "Removed preset \(existing.name)")
    }

    func clearActivePresetSelection() {
        updateActivePresetID(nil)
    }

    func renamePreset(id: String, name: String) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        guard !presets[index].isLocked else {
            throw PresetValidationError.lockedPreset
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PresetValidationError.emptyName
        }
        presets[index].name = trimmed
        presets[index].updatedAt = Date()
        persistPresets()
        logger.log(.info, category: "Preset", "Renamed preset to \(trimmed)")
    }

    @discardableResult
    func duplicatePreset(id: String) -> ViewPreset? {
        guard let preset = presets.first(where: { $0.id == id }) else { return nil }
        let duplicateName = uniquePresetName(basedOn: "\(preset.name) Copy")
        let duplicate = ViewPreset(
            name: duplicateName,
            panelCount: preset.panelCount,
            panelServiceIDs: preset.panelServiceIDs,
            windowWidth: preset.windowWidth,
            windowHeight: preset.windowHeight,
            isLocked: false,
            updatedAt: Date()
        )
        if let sourceIndex = presets.firstIndex(where: { $0.id == id }) {
            presets.insert(duplicate, at: min(sourceIndex + 1, presets.count))
        } else {
            presets.append(duplicate)
        }
        persistPresets()
        logger.log(.info, category: "Preset", "Duplicated preset \(preset.name)")
        return duplicate
    }

    func movePreset(id: String, offset: Int) {
        guard let sourceIndex = presets.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = max(0, min(presets.count - 1, sourceIndex + offset))
        guard targetIndex != sourceIndex else { return }
        let moved = presets.remove(at: sourceIndex)
        presets.insert(moved, at: targetIndex)
        persistPresets()
        logger.log(.info, category: "Preset", "Moved preset \(moved.name) to index \(targetIndex)")
    }

    func setPresetLocked(id: String, isLocked: Bool) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        guard presets[index].isLocked != isLocked else { return }
        presets[index].isLocked = isLocked
        presets[index].updatedAt = Date()
        persistPresets()
        logger.log(.info, category: "Preset", "\(isLocked ? "Locked" : "Unlocked") preset \(presets[index].name)")
    }

    @discardableResult
    func savePrompt(title: String, text: String, tags: [String] = [], isFavorite: Bool = false) throws -> SavedPrompt {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw PromptValidationError.emptyText
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredTitle = trimmedTitle.isEmpty ? Self.defaultPromptTitle(from: trimmedText) : trimmedTitle
        let uniqueTitle = uniquePromptTitle(from: preferredTitle)
        let normalizedTags = normalizedPromptTags(tags)
        let prompt = SavedPrompt(
            title: uniqueTitle,
            text: trimmedText,
            tags: normalizedTags,
            isFavorite: isFavorite,
            updatedAt: Date()
        )
        savedPrompts.append(prompt)
        savedPromptsByID[prompt.id] = prompt
        persistSavedPrompts()
        logger.log(.info, category: "Prompt", "Saved prompt \(prompt.title)")
        return prompt
    }

    @discardableResult
    func updateSavedPrompt(
        id: String,
        title: String,
        text: String,
        tags: [String]? = nil,
        isFavorite: Bool? = nil
    ) throws -> SavedPrompt {
        guard let existingIndex = savedPrompts.firstIndex(where: { $0.id == id }) else {
            throw PromptValidationError.promptNotFound
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw PromptValidationError.emptyText
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredTitle = trimmedTitle.isEmpty ? Self.defaultPromptTitle(from: trimmedText) : trimmedTitle
        let uniqueTitle = uniquePromptTitle(from: preferredTitle, excludingID: id)
        let normalizedTags = tags.map(normalizedPromptTags) ?? savedPrompts[existingIndex].tags
        let favoriteValue = isFavorite ?? savedPrompts[existingIndex].isFavorite

        let updatedPrompt = SavedPrompt(
            id: id,
            title: uniqueTitle,
            text: trimmedText,
            tags: normalizedTags,
            isFavorite: favoriteValue,
            updatedAt: Date()
        )
        if savedPrompts[existingIndex] != updatedPrompt {
            savedPrompts[existingIndex] = updatedPrompt
            savedPromptsByID[updatedPrompt.id] = updatedPrompt
            persistSavedPrompts()
            logger.log(.info, category: "Prompt", "Updated prompt \(updatedPrompt.title)")
        }

        return savedPrompts[existingIndex]
    }

    func setSavedPromptFavorite(id: String, isFavorite: Bool) {
        guard let prompt = savedPrompts.first(where: { $0.id == id }) else { return }
        _ = try? updateSavedPrompt(
            id: prompt.id,
            title: prompt.title,
            text: prompt.text,
            tags: prompt.tags,
            isFavorite: isFavorite
        )
    }

    func removeSavedPrompt(id: String) {
        guard let removed = savedPromptsByID[id] else { return }
        savedPrompts.removeAll(where: { $0.id == id })
        savedPromptsByID.removeValue(forKey: id)
        if selectedAnalysisPromptID == id {
            selectedAnalysisPromptID = nil
            persistSelectedAnalysisPromptID()
        }
        persistSavedPrompts()
        logger.log(.info, category: "Prompt", "Removed prompt \(removed.title)")
    }

    func consumePendingPresetWindowSize() {
        guard pendingPresetWindowSize != nil else { return }
        pendingPresetWindowSize = nil
    }

    func syncActivePresetWindowSize(_ size: CGSize) {
        let width = Double(size.width)
        let height = Double(size.height)
        let epsilon = 0.5

        updateActivePresetSnapshotIfNeeded(logReason: "window size") { preset in
            let widthChanged: Bool
            if let existingWidth = preset.windowWidth {
                widthChanged = abs(existingWidth - width) > epsilon
            } else {
                widthChanged = true
            }

            let heightChanged: Bool
            if let existingHeight = preset.windowHeight {
                heightChanged = abs(existingHeight - height) > epsilon
            } else {
                heightChanged = true
            }

            guard widthChanged || heightChanged else { return false }
            preset.windowWidth = width
            preset.windowHeight = height
            return true
        }
    }

    func webViewStore(for panelIndex: Int) -> WebViewStore {
        if let store = webViewStores[panelIndex] {
            markStoreActive(at: panelIndex)
            return store
        }

        let newStore = WebViewStore()
        webViewStores[panelIndex] = newStore
        markStoreActive(at: panelIndex)
        logger.log(.info, category: "WebView", "Created store for panel \(panelIndex)")
        return newStore
    }

    func addCustomService(title: String, urlString: String) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw SiteValidationError.emptyTitle
        }

        guard let normalizedURL = AIService.normalizeURLString(urlString) else {
            throw SiteValidationError.invalidURL
        }

        let service = AIService(
            id: "custom-\(UUID().uuidString.lowercased())",
            title: trimmedTitle,
            urlString: normalizedURL,
            isBuiltIn: false
        )

        services.append(service)
        rebuildServiceIndex()
        persistCustomServices()
        logger.log(.info, category: "Service", "Added custom service \(service.title)")
    }

    func removeCustomService(id: String) throws {
        guard let target = servicesByID[id] else { return }
        guard !target.isBuiltIn else {
            throw SiteValidationError.builtInDeletionNotAllowed
        }

        services.removeAll(where: { $0.id == id })
        rebuildServiceIndex()
        persistCustomServices()
        normalizePanelSelectionsAndPersistIfNeeded()
        normalizePresetsAndPersistIfNeeded()
        clearActivePresetIfNoLongerMatchingCurrentState()
        logger.log(.info, category: "Service", "Removed custom service \(target.title)")
    }

    var customServices: [AIService] {
        services.filter { !$0.isBuiltIn }
    }

    private static func clampPanelCount(_ value: Int) -> Int {
        min(max(value, minPanels), maxPanels)
    }

    private static func restorePanelServiceIDs(from defaults: UserDefaults) -> [String] {
        let fallback = AIService.defaultPanelServiceIDs(count: Self.maxPanels)
        guard let stored = defaults.array(forKey: DefaultsKey.panelServices) as? [String] else {
            return fallback
        }

        var restored = stored.map { AIService.legacyID(from: $0) ?? $0 }
        if restored.count > Self.maxPanels {
            restored = Array(restored.prefix(Self.maxPanels))
        }
        if restored.count < Self.maxPanels {
            restored += fallback.dropFirst(restored.count)
        }
        return restored
    }

    private static func restoreCustomServices(from defaults: UserDefaults) -> [AIService] {
        guard let data = defaults.data(forKey: DefaultsKey.customServices),
              let decoded = try? JSONDecoder().decode([AIService].self, from: data) else {
            return []
        }

        return decoded.compactMap { service in
            guard !service.isBuiltIn else { return nil }
            guard let normalizedURL = AIService.normalizeURLString(service.urlString) else { return nil }

            return AIService(
                id: service.id,
                title: service.title,
                urlString: normalizedURL,
                isBuiltIn: false
            )
        }
    }

    private static func restorePresets(from defaults: UserDefaults) -> [ViewPreset] {
        guard let data = defaults.data(forKey: DefaultsKey.presets),
              let decoded = try? JSONDecoder().decode([ViewPreset].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func restoreActivePresetID(from defaults: UserDefaults) -> String? {
        defaults.string(forKey: DefaultsKey.activePresetID)
    }

    private static func restoreSavedPrompts(from defaults: UserDefaults) -> [SavedPrompt] {
        guard let data = defaults.data(forKey: DefaultsKey.savedPrompts),
              let decoded = try? JSONDecoder().decode([SavedPrompt].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func restoreSelectedAnalysisPromptID(from defaults: UserDefaults) -> String? {
        defaults.string(forKey: DefaultsKey.selectedAnalysisPromptID)
    }

    private static func restoreWebViewRetentionMode(from defaults: UserDefaults) -> WebViewRetentionMode {
        guard let raw = defaults.string(forKey: DefaultsKey.webViewRetentionMode),
              let mode = WebViewRetentionMode(rawValue: raw) else {
            return .balanced
        }
        return mode
    }

    private static func restoreTwoPanelCrossSendEnabled(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: DefaultsKey.twoPanelCrossSendEnabled) as? Bool ?? false
    }

    private func normalizeRestoredStateAndPersistIfNeeded(
        forcePersist: Bool = false,
        cancelPendingWrites: Bool = false
    ) {
        var shouldPersist = forcePersist
        shouldPersist = normalizePanelSelectionsAndPersistIfNeeded(persist: false) || shouldPersist
        shouldPersist = normalizePresetsAndPersistIfNeeded(persist: false) || shouldPersist
        shouldPersist = normalizeActivePresetAndPersistIfNeeded(persist: false) || shouldPersist
        shouldPersist = clearActivePresetIfNoLongerMatchingCurrentState(persist: false) || shouldPersist
        shouldPersist = normalizeSavedPromptsAndPersistIfNeeded(persist: false) || shouldPersist
        shouldPersist = normalizeSelectedAnalysisPromptAndPersistIfNeeded(persist: false) || shouldPersist

        guard shouldPersist else { return }
        if cancelPendingWrites {
            cancelPendingDefaultWrites()
        }
        writeAllDefaultsNow()
    }

    @discardableResult
    private func normalizePanelSelectionsAndPersistIfNeeded(persist: Bool = true) -> Bool {
        let updated = normalizedServiceIDs(from: panelServiceIDs)

        guard updated != panelServiceIDs else { return false }
        panelServiceIDs = updated
        if persist {
            persistPanelServiceIDs()
        }
        return true
    }

    @discardableResult
    private func normalizePresetsAndPersistIfNeeded(persist: Bool = true) -> Bool {
        var didChange = false
        let normalized = presets.compactMap { preset -> ViewPreset? in
            let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                didChange = true
                return nil
            }

            let clampedCount = Self.clampPanelCount(preset.panelCount)
            let normalizedIDs = normalizedServiceIDs(from: preset.panelServiceIDs)

            let updated = ViewPreset(
                id: preset.id,
                name: trimmedName,
                panelCount: clampedCount,
                panelServiceIDs: normalizedIDs,
                windowWidth: preset.windowWidth,
                windowHeight: preset.windowHeight,
                isLocked: preset.isLocked,
                updatedAt: preset.updatedAt
            )

            if updated != preset {
                didChange = true
            }
            return updated
        }

        guard didChange || normalized != presets else { return false }
        presets = normalized
        if persist {
            persistPresets()
        }
        return true
    }

    @discardableResult
    private func normalizeActivePresetAndPersistIfNeeded(persist: Bool = true) -> Bool {
        guard let activePresetID else { return false }
        guard presets.contains(where: { $0.id == activePresetID }) else {
            updateActivePresetID(nil, persist: persist)
            return true
        }
        return false
    }

    @discardableResult
    private func clearActivePresetIfNoLongerMatchingCurrentState(persist: Bool = true) -> Bool {
        guard let activePresetID else { return false }
        guard let preset = presets.first(where: { $0.id == activePresetID }) else {
            updateActivePresetID(nil, persist: persist)
            return true
        }

        let normalizedPresetServices = normalizedServiceIDs(from: preset.panelServiceIDs)
        let normalizedCurrentServices = normalizedServiceIDs(from: panelServiceIDs)
        let isMatching =
            preset.panelCount == panelCount &&
            normalizedPresetServices == normalizedCurrentServices
        if !isMatching {
            updateActivePresetID(nil, persist: persist)
            return true
        }
        return false
    }

    private func syncActivePresetToCurrentStateIfNeeded() {
        let normalizedServices = normalizedServiceIDs(from: panelServiceIDs)
        updateActivePresetSnapshotIfNeeded(logReason: "panel state") { preset in
            var didChange = false
            if preset.panelCount != panelCount {
                preset.panelCount = panelCount
                didChange = true
            }
            if preset.panelServiceIDs != normalizedServices {
                preset.panelServiceIDs = normalizedServices
                didChange = true
            }
            return didChange
        }
    }

    private func updateActivePresetSnapshotIfNeeded(
        logReason: String,
        mutate: (inout ViewPreset) -> Bool
    ) {
        guard !isApplyingPreset else { return }
        guard let activePresetID else { return }
        guard let index = presets.firstIndex(where: { $0.id == activePresetID }) else { return }
        guard !presets[index].isLocked else { return }

        var updatedPreset = presets[index]
        guard mutate(&updatedPreset) else { return }
        updatedPreset.updatedAt = Date()

        var updatedPresets = presets
        updatedPresets[index] = updatedPreset
        presets = updatedPresets
        persistPresets()
        logger.log(.info, category: "Preset", "Synced active preset \(updatedPreset.name) (\(logReason))")
    }

    @discardableResult
    private func normalizeSavedPromptsAndPersistIfNeeded(persist: Bool = true) -> Bool {
        var didChange = false
        let normalized = savedPrompts.compactMap { prompt -> SavedPrompt? in
            let trimmedText = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                didChange = true
                return nil
            }

            let trimmedTitle = prompt.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = trimmedTitle.isEmpty ? Self.defaultPromptTitle(from: trimmedText) : trimmedTitle

            let updated = SavedPrompt(
                id: prompt.id,
                title: finalTitle,
                text: trimmedText,
                tags: normalizedPromptTags(prompt.tags),
                isFavorite: prompt.isFavorite,
                updatedAt: prompt.updatedAt
            )
            if updated != prompt {
                didChange = true
            }
            return updated
        }

        guard didChange || normalized != savedPrompts else { return false }
        savedPrompts = normalized
        rebuildSavedPromptIndex()
        if persist {
            persistSavedPrompts()
        }
        return true
    }

    @discardableResult
    private func normalizeSelectedAnalysisPromptAndPersistIfNeeded(persist: Bool = true) -> Bool {
        guard let selectedAnalysisPromptID else { return false }
        guard savedPromptsByID[selectedAnalysisPromptID] != nil else {
            self.selectedAnalysisPromptID = nil
            if persist {
                persistSelectedAnalysisPromptID()
            }
            return true
        }
        return false
    }

    private func normalizeAnalysisTargetPanelIndex() {
        let clamped = max(0, min(panelCount - 1, analysisTargetPanelIndex))
        if analysisTargetPanelIndex != clamped {
            analysisTargetPanelIndex = clamped
        }
    }

    private func pruneCollectedResponsesToVisiblePanels() {
        let visibleIndexes = Set(0 ..< panelCount)
        let filtered = collectedResponsesByPanel.filter { visibleIndexes.contains($0.key) }
        if filtered != collectedResponsesByPanel {
            collectedResponsesByPanel = filtered
        }
    }

    private func normalizedServiceIDs(from source: [String]) -> [String] {
        var normalized = source.map { AIService.legacyID(from: $0) ?? $0 }
        if normalized.count > Self.maxPanels {
            normalized = Array(normalized.prefix(Self.maxPanels))
        }
        if normalized.count < Self.maxPanels {
            normalized += AIService.defaultPanelServiceIDs(count: Self.maxPanels).dropFirst(normalized.count)
        }

        let fallbackID = services.first?.id ?? Self.fallbackServiceID

        for index in normalized.indices where servicesByID[normalized[index]] == nil {
            normalized[index] = fallbackID
        }

        return normalized
    }

    private func nextAutoPresetName() -> String {
        let base = "Preset"
        var index = 1
        while presets.contains(where: { $0.name.caseInsensitiveCompare("\(base) \(index)") == .orderedSame }) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func uniquePresetName(basedOn rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Preset" : trimmed
        guard !presets.contains(where: { $0.name.caseInsensitiveCompare(base) == .orderedSame }) else {
            var index = 2
            while presets.contains(where: { $0.name.caseInsensitiveCompare("\(base) \(index)") == .orderedSame }) {
                index += 1
            }
            return "\(base) \(index)"
        }
        return base
    }

    private static func defaultPromptTitle(from text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else {
            return "Prompt"
        }

        let maxLength = 28
        if collapsed.count <= maxLength {
            return collapsed
        }
        return String(collapsed.prefix(maxLength)) + "..."
    }

    private func uniquePromptTitle(from baseTitle: String, excludingID: String? = nil) -> String {
        let trimmedBase = baseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBase = trimmedBase.isEmpty ? "Prompt" : trimmedBase
        let titleExists: (String) -> Bool = { candidate in
            self.savedPrompts.contains { prompt in
                if let excludingID, prompt.id == excludingID {
                    return false
                }
                return prompt.title.caseInsensitiveCompare(candidate) == .orderedSame
            }
        }

        guard !titleExists(resolvedBase) else {
            var index = 2
            while titleExists("\(resolvedBase) \(index)") {
                index += 1
            }
            return "\(resolvedBase) \(index)"
        }

        return resolvedBase
    }

    private func normalizedPromptTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { tag in
                let key = tag.lowercased()
                if seen.contains(key) {
                    return false
                }
                seen.insert(key)
                return true
            }
    }

    private func reindexedPanelServiceIDs(removing removedIndex: Int) -> [String] {
        var updated = panelServiceIDs
        guard updated.indices.contains(removedIndex) else { return normalizedServiceIDs(from: updated) }
        updated.remove(at: removedIndex)

        let defaults = AIService.defaultPanelServiceIDs(count: Self.maxPanels)
        let fallbackID = defaults.indices.contains(updated.count) ? defaults[updated.count] : Self.fallbackServiceID
        updated.append(fallbackID)
        return normalizedServiceIDs(from: updated)
    }

    private func remapCollectedResponses(removingPanelAt removedIndex: Int) {
        guard !collectedResponsesByPanel.isEmpty else { return }

        var updated: [Int: CollectedPanelResponse] = [:]
        for response in collectedResponsesByPanel.values {
            guard response.panelIndex != removedIndex else { continue }
            let newIndex = response.panelIndex > removedIndex ? response.panelIndex - 1 : response.panelIndex
            guard newIndex >= 0, newIndex < panelCount else { continue }
            updated[newIndex] = CollectedPanelResponse(
                panelIndex: newIndex,
                serviceID: response.serviceID,
                serviceTitle: response.serviceTitle,
                sourceURLString: response.sourceURLString,
                text: response.text,
                capturedAt: response.capturedAt
            )
        }
        collectedResponsesByPanel = updated
    }

    private func remapAnalysisTargetIndex(removingPanelAt removedIndex: Int) {
        if analysisTargetPanelIndex == removedIndex {
            analysisTargetPanelIndex = min(removedIndex, max(panelCount - 1, 0))
        } else if analysisTargetPanelIndex > removedIndex {
            analysisTargetPanelIndex -= 1
        }
        normalizeAnalysisTargetPanelIndex()
    }

    private func remapWebViewStores(removingPanelAt removedIndex: Int) {
        if let removedStore = webViewStores.removeValue(forKey: removedIndex) {
            removedStore.prepareForRelease()
        }
        hiddenStoreSince.removeValue(forKey: removedIndex)
        hiddenStoreReleaseTasks.removeValue(forKey: removedIndex)?.cancel()

        func remapKeys<T>(_ source: [Int: T]) -> [Int: T] {
            var mapped: [Int: T] = [:]
            for (key, value) in source {
                guard key != removedIndex else { continue }
                let newKey = key > removedIndex ? key - 1 : key
                mapped[newKey] = value
            }
            return mapped
        }

        webViewStores = remapKeys(webViewStores)
        hiddenStoreSince = remapKeys(hiddenStoreSince)
        hiddenStoreReleaseTasks = remapKeys(hiddenStoreReleaseTasks)
        pruneHiddenStoresToLimit()
    }

    private func reconcileWebViewStores(afterPanelCountChangeFrom oldCount: Int, to newCount: Int) {
        if newCount < oldCount {
            for index in newCount ..< oldCount {
                markStoreHidden(at: index)
            }
        } else if newCount > oldCount {
            for index in oldCount ..< newCount {
                markStoreActive(at: index)
            }
        }

        pruneHiddenStoresToLimit()
    }

    private func markStoreHidden(at index: Int) {
        guard webViewStores[index] != nil else { return }
        hiddenStoreSince[index] = hiddenStoreSince[index] ?? Date()
        switch webViewRetentionMode {
        case .aggressive:
            releaseStoreIfHidden(at: index, force: true)
        case .balanced:
            scheduleHiddenStoreRelease(at: index)
        case .keepAlive:
            hiddenStoreReleaseTasks[index]?.cancel()
            hiddenStoreReleaseTasks.removeValue(forKey: index)
        }
    }

    private func markStoreActive(at index: Int) {
        guard hiddenStoreSince[index] != nil || hiddenStoreReleaseTasks[index] != nil else { return }
        hiddenStoreSince.removeValue(forKey: index)
        let pendingTask = hiddenStoreReleaseTasks.removeValue(forKey: index)
        pendingTask?.cancel()
    }

    private func scheduleHiddenStoreRelease(at index: Int) {
        guard webViewRetentionMode == .balanced else { return }
        hiddenStoreReleaseTasks[index]?.cancel()
        hiddenStoreReleaseTasks[index] = Task { [weak self] in
            let nanos = UInt64(WebViewRetentionPolicy.hiddenTTL * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.releaseStoreIfHidden(at: index, force: false)
        }
    }

    private func pruneHiddenStoresToLimit() {
        guard webViewRetentionMode != .keepAlive else { return }
        let hiddenIndexes = webViewStores.keys.filter { $0 >= panelCount }
        guard hiddenIndexes.count > WebViewRetentionPolicy.maxHiddenStores else { return }

        let sortedIndexes = hiddenIndexes.sorted { lhs, rhs in
            let lhsDate = hiddenStoreSince[lhs] ?? .distantPast
            let rhsDate = hiddenStoreSince[rhs] ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs < rhs
        }

        let overflow = hiddenIndexes.count - WebViewRetentionPolicy.maxHiddenStores
        for index in sortedIndexes.prefix(overflow) {
            releaseStoreIfHidden(at: index, force: true)
        }
    }

    private func releaseStoreIfHidden(at index: Int, force: Bool) {
        guard let store = webViewStores[index] else {
            hiddenStoreSince.removeValue(forKey: index)
            hiddenStoreReleaseTasks[index]?.cancel()
            hiddenStoreReleaseTasks.removeValue(forKey: index)
            return
        }

        if !force, index < panelCount {
            markStoreActive(at: index)
            return
        }

        store.prepareForRelease()
        webViewStores.removeValue(forKey: index)
        hiddenStoreSince.removeValue(forKey: index)
        hiddenStoreReleaseTasks[index]?.cancel()
        hiddenStoreReleaseTasks.removeValue(forKey: index)
        logger.log(.info, category: "WebView", "Released hidden store for panel \(index)")
    }

    private func releaseAllHiddenStores() {
        let hiddenIndexes = webViewStores.keys.filter { $0 >= panelCount }
        for index in hiddenIndexes {
            releaseStoreIfHidden(at: index, force: true)
        }
    }

    private func configureMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.logger.log(.warning, category: "Memory", "Memory pressure detected; releasing hidden web views")
            Task { @MainActor [weak self] in
                self?.releaseAllHiddenStores()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func configureApplicationLifecycleMonitoring() {
        let center = NotificationCenter.default
        let didResign = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationDidResignActive()
            }
        }
        let didBecome = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationDidBecomeActive()
            }
        }
        lifecycleObservers = [didResign, didBecome]
    }

    private func handleApplicationDidResignActive() {
        isAppActive = false
        flushPendingDefaultWrites()
        if webViewRetentionMode != .keepAlive {
            releaseAllHiddenStores()
        }
        logger.log(.info, category: "Lifecycle", "App resigned active")
    }

    private func handleApplicationDidBecomeActive() {
        isAppActive = true
        logger.log(.info, category: "Lifecycle", "App became active")
    }

    private func encodedData<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private func writePanelCountToDefaults() {
        defaults.set(panelCount, forKey: DefaultsKey.panelCount)
    }

    private func writePanelServiceIDsToDefaults() {
        defaults.set(panelServiceIDs, forKey: DefaultsKey.panelServices)
    }

    private func writeCustomServicesToDefaults() {
        guard let data = encodedData(services.filter { !$0.isBuiltIn }) else { return }
        defaults.set(data, forKey: DefaultsKey.customServices)
    }

    private func writePresetsToDefaults() {
        guard let data = encodedData(presets) else { return }
        defaults.set(data, forKey: DefaultsKey.presets)
    }

    private func writeActivePresetIDToDefaults() {
        if let id = activePresetID {
            defaults.set(id, forKey: DefaultsKey.activePresetID)
        } else {
            defaults.removeObject(forKey: DefaultsKey.activePresetID)
        }
    }

    private func writeSavedPromptsToDefaults() {
        guard let data = encodedData(savedPrompts) else { return }
        defaults.set(data, forKey: DefaultsKey.savedPrompts)
    }

    private func writeSelectedAnalysisPromptIDToDefaults() {
        if let selectedAnalysisPromptID {
            defaults.set(selectedAnalysisPromptID, forKey: DefaultsKey.selectedAnalysisPromptID)
        } else {
            defaults.removeObject(forKey: DefaultsKey.selectedAnalysisPromptID)
        }
    }

    private func writeWebViewRetentionModeToDefaults() {
        defaults.set(webViewRetentionMode.rawValue, forKey: DefaultsKey.webViewRetentionMode)
    }

    private func writeTwoPanelCrossSendEnabledToDefaults() {
        defaults.set(isTwoPanelCrossSendEnabled, forKey: DefaultsKey.twoPanelCrossSendEnabled)
    }

    private func writeAllDefaultsNow() {
        writePanelCountToDefaults()
        writePanelServiceIDsToDefaults()
        writePresetsToDefaults()
        writeSavedPromptsToDefaults()
        writeSelectedAnalysisPromptIDToDefaults()
        writeCustomServicesToDefaults()
        writeActivePresetIDToDefaults()
        writeWebViewRetentionModeToDefaults()
        writeTwoPanelCrossSendEnabledToDefaults()
    }

    private func cancelPendingDefaultWrites() {
        for task in defaultsWriteTasks.values {
            task.cancel()
        }
        defaultsWriteTasks.removeAll()
    }

    private func persistPanelServiceIDs() {
        scheduleDefaultsWrite(key: DefaultsKey.panelServices) { [weak self] in
            self?.writePanelServiceIDsToDefaults()
        }
    }

    private func rebuildServiceIndex() {
        servicesByID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
    }

    private func rebuildSavedPromptIndex() {
        savedPromptsByID = Dictionary(uniqueKeysWithValues: savedPrompts.map { ($0.id, $0) })
    }

    private func persistCustomServices() {
        scheduleDefaultsWrite(key: DefaultsKey.customServices) { [weak self] in
            self?.writeCustomServicesToDefaults()
        }
    }

    private func persistPresets() {
        scheduleDefaultsWrite(key: DefaultsKey.presets) { [weak self] in
            self?.writePresetsToDefaults()
        }
    }

    private func updateActivePresetID(_ id: String?, persist: Bool = true) {
        guard activePresetID != id else { return }
        activePresetID = id
        if persist {
            scheduleDefaultsWrite(key: DefaultsKey.activePresetID) { [weak self] in
                self?.writeActivePresetIDToDefaults()
            }
        }
    }

    private func persistSavedPrompts() {
        scheduleDefaultsWrite(key: DefaultsKey.savedPrompts) { [weak self] in
            self?.writeSavedPromptsToDefaults()
        }
    }

    private func persistSelectedAnalysisPromptID() {
        scheduleDefaultsWrite(key: DefaultsKey.selectedAnalysisPromptID) { [weak self] in
            self?.writeSelectedAnalysisPromptIDToDefaults()
        }
    }

    private func persistPanelCount() {
        scheduleDefaultsWrite(key: DefaultsKey.panelCount) { [weak self] in
            self?.writePanelCountToDefaults()
        }
    }

    private func persistWebViewRetentionMode() {
        scheduleDefaultsWrite(key: DefaultsKey.webViewRetentionMode) { [weak self] in
            self?.writeWebViewRetentionModeToDefaults()
        }
    }

    private func persistTwoPanelCrossSendEnabled() {
        scheduleDefaultsWrite(key: DefaultsKey.twoPanelCrossSendEnabled) { [weak self] in
            self?.writeTwoPanelCrossSendEnabledToDefaults()
        }
    }

    private func scheduleDefaultsWrite(key: String, action: @escaping @MainActor () -> Void) {
        defaultsWriteTasks[key]?.cancel()
        defaultsWriteTasks[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.defaultsWriteThrottleNanos ?? 0)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                action()
                self?.defaultsWriteTasks.removeValue(forKey: key)
            }
        }
    }

    private func flushPendingDefaultWrites() {
        cancelPendingDefaultWrites()
        writeAllDefaultsNow()
    }

    private func resolvedAnalysisPromptHeader() -> String {
        let selectedText = selectedAnalysisPrompt?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selectedText, !selectedText.isEmpty {
            return selectedText
        }
        return Self.defaultAnalysisPromptHeader
    }

    private static let defaultAnalysisPromptHeader = """
    아래는 여러 AI 패널에서 수집한 최신 답변입니다.
    목표는 단순 비교/요약이 아니라, 여러 답변을 재료로 사용해 사실 여부를 검증하고
    가능하면 실시간 정보(최신 웹/공식 출처)를 대입해 더 깊고, 더 정확하며, 수준 높은 최종 답변과 인사이트를 만드는 것이다.
    즉, 공통점/차이점 정리는 중간 과정일 뿐이고 최종 목적은 "정확도 상승 + 통찰력 있는 통합 답변"이다.

    작업 순서(반드시):
    1. 각 답변의 핵심 내용과 관점(주장/근거/수치/날짜/고유명사 포함)을 빠르게 파악
    2. 답변 간 공통점과 차이점을 이용해 사실 여부를 검증하고, 검증이 필요한 핵심 쟁점을 선별
    3. 실시간 정보 검증(가능하면 최신 웹 검색/공식 문서/공식 발표 기준, 날짜 명시)으로 정확도 보정
    4. 여러 답변의 장점을 결합하고 누락된 관점을 보완해, 더 깊고 수준 높은 통합 답변 작성
    5. 실무적으로 도움이 되는 해석/의사결정 포인트/주의사항까지 포함한 인사이트 정리

    출력 형식:
    1. 질문/문제의 핵심 재정의(무엇을 정확하게 답해야 하는지)
    2. 답변 통합을 위한 핵심 쟁점 정리(필요한 경우에만 공통점/차이점 간단 요약)
    3. 실시간 정보 검증 결과(출처, 확인 날짜/시간, 정정 내용)
    4. 정확도 보정 후 최종 답변(더 깊고, 더 정확하고, 바로 활용 가능한 형태)
    5. 추가 인사이트(왜 이런 결론이 나오는지, 실무 적용 포인트, 놓치기 쉬운 함정)
    6. 신뢰도 등급 및 남은 리스크/확인 필요 항목

    규칙:
    - 단순 다수결로 결론 내리지 말 것
    - 출처 우선순위는 기본적으로 "공식문서/공식발표 > 신뢰할 수 있는 뉴스(복수 교차확인) > 커뮤니티/개인경험" 순서로 적용할 것
    - 단, 속보성 이슈/사건은 공식문서가 늦을 수 있으므로 신뢰 가능한 복수 뉴스 교차검증을 허용하고, 확인 시각을 명시할 것
    - 단, 사용 팁/실사용 오류 해결/우회 방법은 커뮤니티 정보 활용을 허용하되 재현 여부와 불확실성을 함께 표시할 것
    - 실시간 확인이 필요한 내용(뉴스/가격/정책/일정/버전/수치)은 최신 정보로 재검증할 것
    - 실시간 검색/브라우징이 불가능하면 그 사실을 먼저 밝히고, 확인 필요 항목을 명시할 것
    - 확실하지 않은 내용은 추측하지 말고 "확인 필요"로 표시
    - 답변별로 어떤 AI가 말했는지 구분해서 써줘
    - 최종 답변에는 정정된 수치/날짜를 명확히 표시해줘
    - 중간 비교표를 길게 늘어놓는 것보다, 검증을 거친 통합 결론의 품질과 통찰력을 우선할 것
    - 표가 적절하면 표를 사용해도 됨
    - 응답은 한국어로 작성
    """
}
