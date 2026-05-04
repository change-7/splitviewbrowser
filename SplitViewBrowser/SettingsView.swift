import SwiftUI

struct SettingsView: View {
    private enum SettingsCategory: String, CaseIterable, Identifiable {
        case general
        case customSites
        case presets
        case diagnostics

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:
                return "General"
            case .customSites:
                return "Custom Sites"
            case .presets:
                return "Presets"
            case .diagnostics:
                return "Diagnostics"
            }
        }

        var symbolName: String {
            switch self {
            case .general:
                return "slider.horizontal.3"
            case .customSites:
                return "globe"
            case .presets:
                return "square.grid.2x2"
            case .diagnostics:
                return "stethoscope"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: SettingsCategory = .general
    @State private var customSiteName = ""
    @State private var customSiteURL = ""
    @State private var errorMessage = ""
    @State private var presetName = ""
    @State private var presetMessage = ""
    @State private var presetMessageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader
            Divider()
            HStack(spacing: 0) {
                settingsSidebar
                Divider()
                settingsDetailPane
            }
        }
        .padding(14)
    }

    private var settingsHeader: some View {
        HStack {
            Text(String(localized: "settings.title"))
                .font(.title3.bold())

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(String(localized: "common.close"))
            .accessibilityLabel("설정 닫기")
        }
    }

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SettingsCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: category.symbolName)
                                .frame(width: 16)
                            Text(category.title)
                                .font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selectedCategory == category ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedCategory == category ? Color.accentColor : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("설정 항목 \(category.title)")
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
        .frame(width: 190)
        .padding(.trailing, 12)
    }

    private var settingsDetailPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedCategory.title)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    selectedCategoryContent
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var selectedCategoryContent: some View {
        switch selectedCategory {
        case .general:
            panelWidthPolicySection
            retentionPolicySection
            twoPanelCrossSendSection
        case .customSites:
            customSitesSection
        case .presets:
            presetsSection
        case .diagnostics:
            diagnosticsSection
        }
    }

    private var panelWidthPolicySection: some View {
        GroupBox("Panel Width Policy") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Each panel is fixed in the mobile range: 360pt to 430pt.")
                Text("Panels stay within that range and the window scrolls horizontally if there is not enough width.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var retentionPolicySection: some View {
        GroupBox("WebView Memory Policy") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Retention", selection: retentionModeBinding) {
                    ForEach(WebViewRetentionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("웹뷰 메모리 정책")

                Text(appState.webViewRetentionMode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("백그라운드 전환 시 숨겨진 패널 웹뷰는 정책에 따라 우선 정리됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Picker("Service Change", selection: panelServiceChangePolicyBinding) {
                    ForEach(PanelServiceChangeStorePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("서비스 변경 웹뷰 처리 정책")

                Text(appState.panelServiceChangeStorePolicy.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private var twoPanelCrossSendSection: some View {
        GroupBox("Two Panel Cross Send") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("2패널일 때 패널 사이 화살표 버튼으로 최신 답변 교차 전송 사용", isOn: twoPanelCrossSendBinding)
                    .toggleStyle(.switch)
                    .accessibilityLabel("2패널 교차 전송 사용")

                Text("이 기능은 패널이 정확히 2개일 때만 보입니다. 가운데 구분선에 1→2, 2→1 화살표 버튼이 표시되고, 각 패널의 최신 답변을 반대편 패널 입력창으로 바로 전송합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }

    private var customSitesSection: some View {
        GroupBox("Custom Sites") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("여기서 추가한 커스텀 사이트에는 현재 `답변 수집`, `분석 패널 전송`, `동시 입력/전송` 자동화 기능이 적용되지 않습니다.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )

                HStack(spacing: 8) {
                    TextField("Site name", text: $customSiteName)
                        .textFieldStyle(.roundedBorder)

                    TextField("https://example.com", text: $customSiteURL)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        addCustomSite()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("커스텀 사이트 추가")
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if appState.customServices.isEmpty {
                    Text("No custom sites yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(appState.customServices) { service in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(service.title)
                                        Text(service.urlString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button(role: .destructive) {
                                        removeCustomSite(service)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("커스텀 사이트 삭제")
                                }
                                .padding(.vertical, 8)

                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
            .padding(.top, 4)
        }
    }

    private var presetsSection: some View {
        GroupBox("Presets") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Preset name", text: $presetName)
                        .textFieldStyle(.roundedBorder)

                    Button("Save Current") {
                        saveCurrentPreset()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("현재 상태 프리셋 저장")

                    Button("Select None") {
                        clearPresetSelection()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("프리셋 선택 해제")
                }

                if !presetMessage.isEmpty {
                    Text(presetMessage)
                        .font(.caption)
                        .foregroundStyle(presetMessageIsError ? .red : .secondary)
                }

                if appState.presets.isEmpty {
                    Text("No presets yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.presets, id: \ViewPreset.id) { (preset: ViewPreset) in
                            PresetEditorRow(
                                preset: preset,
                                isSelected: appState.activePresetID == preset.id,
                                canMoveUp: appState.presets.first?.id != preset.id,
                                canMoveDown: appState.presets.last?.id != preset.id,
                                onApply: { applyPreset(preset) },
                                onDuplicate: { duplicatePreset(preset) },
                                onMoveUp: { movePresetUp(preset) },
                                onMoveDown: { movePresetDown(preset) },
                                onToggleLock: { togglePresetLock(preset) },
                                onDelete: { removePreset(preset) },
                                onRename: { newName in renamePreset(preset, newName: newName) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var diagnosticsSection: some View {
        DiagnosticsSectionView()
    }

    private func addCustomSite() {
        do {
            try appState.addCustomService(title: customSiteName, urlString: customSiteURL)
            customSiteName = ""
            customSiteURL = ""
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeCustomSite(_ service: AIService) {
        do {
            try appState.removeCustomService(id: service.id)
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var retentionModeBinding: Binding<WebViewRetentionMode> {
        Binding(
            get: { appState.webViewRetentionMode },
            set: { appState.setWebViewRetentionMode($0) }
        )
    }

    private var panelServiceChangePolicyBinding: Binding<PanelServiceChangeStorePolicy> {
        Binding(
            get: { appState.panelServiceChangeStorePolicy },
            set: { appState.setPanelServiceChangeStorePolicy($0) }
        )
    }

    private var twoPanelCrossSendBinding: Binding<Bool> {
        Binding(
            get: { appState.isTwoPanelCrossSendEnabled },
            set: { appState.setTwoPanelCrossSendEnabled($0) }
        )
    }

    private func saveCurrentPreset() {
        do {
            let window = preferredContentWindow()
            let windowSize = window.map { $0.contentRect(forFrameRect: $0.frame).size }
            try appState.saveCurrentPreset(name: presetName, windowSize: windowSize)
            presetName = ""
            presetMessage = "Current layout saved."
            presetMessageIsError = false
        } catch {
            presetMessage = error.localizedDescription
            presetMessageIsError = true
        }
    }

    private func applyPreset(_ preset: ViewPreset) {
        appState.applyPreset(id: preset.id)
        presetMessage = "\"\(preset.name)\" applied."
        presetMessageIsError = false
    }

    private func duplicatePreset(_ preset: ViewPreset) {
        if let duplicate = appState.duplicatePreset(id: preset.id) {
            presetMessage = "\"\(duplicate.name)\" duplicated."
            presetMessageIsError = false
        }
    }

    private func movePresetUp(_ preset: ViewPreset) {
        appState.movePreset(id: preset.id, offset: -1)
        presetMessage = "\"\(preset.name)\" moved up."
        presetMessageIsError = false
    }

    private func movePresetDown(_ preset: ViewPreset) {
        appState.movePreset(id: preset.id, offset: 1)
        presetMessage = "\"\(preset.name)\" moved down."
        presetMessageIsError = false
    }

    private func togglePresetLock(_ preset: ViewPreset) {
        appState.setPresetLocked(id: preset.id, isLocked: !preset.isLocked)
        presetMessage = "\"\(preset.name)\" \(preset.isLocked ? "unlocked" : "locked")."
        presetMessageIsError = false
    }

    private func renamePreset(_ preset: ViewPreset, newName: String) {
        do {
            try appState.renamePreset(id: preset.id, name: newName)
            presetMessage = "Preset renamed."
            presetMessageIsError = false
        } catch {
            presetMessage = error.localizedDescription
            presetMessageIsError = true
        }
    }

    private func removePreset(_ preset: ViewPreset) {
        guard !preset.isLocked else {
            presetMessage = "Locked preset cannot be deleted."
            presetMessageIsError = true
            return
        }
        appState.removePreset(id: preset.id)
        if appState.presets.isEmpty {
            presetMessage = ""
        } else {
            presetMessage = "\"\(preset.name)\" deleted."
            presetMessageIsError = false
        }
    }

    private func clearPresetSelection() {
        appState.clearActivePresetSelection()
        presetMessage = "Preset selection cleared."
        presetMessageIsError = false
    }

}

private struct PresetEditorRow: View {
    let preset: ViewPreset
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onApply: () -> Void
    let onDuplicate: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @State private var nameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Preset name", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(preset.isLocked)
                    .onSubmit { if !preset.isLocked { onRename(nameDraft) } }
                    .accessibilityLabel("프리셋 이름")

                if preset.isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .help("Locked")
                }

                if isSelected {
                    Text("선택됨")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 6) {
                Text("\(preset.panelCount) panels")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let updatedAt = preset.updatedAt {
                    Text(updatedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 6) {
                Button("Apply", action: onApply)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("프리셋 적용")

                Button {
                    onRename(nameDraft)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .disabled(preset.isLocked)
                .help("Rename")
                .accessibilityLabel("프리셋 이름 변경")

                Button {
                    onDuplicate()
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                .help("Duplicate")
                .accessibilityLabel("프리셋 복제")

                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveUp)
                .help("Move Up")
                .accessibilityLabel("프리셋 위로 이동")

                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(!canMoveDown)
                .help("Move Down")
                .accessibilityLabel("프리셋 아래로 이동")

                Button {
                    onToggleLock()
                } label: {
                    Image(systemName: preset.isLocked ? "lock.open" : "lock")
                }
                .buttonStyle(.bordered)
                .help(preset.isLocked ? "Unlock" : "Lock")
                .accessibilityLabel(preset.isLocked ? "프리셋 잠금 해제" : "프리셋 잠금")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(preset.isLocked)
                .accessibilityLabel("프리셋 삭제")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            if nameDraft.isEmpty {
                nameDraft = preset.name
            }
        }
        .onChange(of: preset.name) { newValue in
            nameDraft = newValue
        }
    }
}
