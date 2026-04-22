import SwiftUI

struct PromptRepositoryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var promptDraftTitle = ""
    @State private var promptDraftText = ""
    @State private var promptDraftTags = ""
    @State private var promptDraftIsFavorite = false
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var copiedPromptID: String?
    @State private var editingPromptID: String?
    @State private var searchText = ""
    @State private var selectedTagFilter: String?
    @State private var sortMode: PromptSortMode = .recent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "prompt_repository.title"))
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
                .accessibilityLabel("프롬프트 저장소 닫기")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("이름(선택)", text: $promptDraftTitle)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("프롬프트 이름")

                    HStack(spacing: 8) {
                        TextField("태그 (쉼표로 구분)", text: $promptDraftTags)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("프롬프트 태그")

                        Toggle("즐겨찾기", isOn: $promptDraftIsFavorite)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .help("즐겨찾기")
                            .accessibilityLabel("즐겨찾기")

                        Image(systemName: promptDraftIsFavorite ? "star.fill" : "star")
                            .foregroundStyle(promptDraftIsFavorite ? Color.yellow : .secondary)
                    }

                    TextEditor(text: $promptDraftText)
                        .font(.body)
                        .frame(height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(.quaternary)
                        )

                    HStack {
                        if editingPromptID != nil {
                            Button("취소") {
                                cancelPromptEditing()
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("프롬프트 수정 취소")
                        }

                        Spacer()

                        Button(editingPromptID == nil ? "저장" : "수정 저장") {
                            savePrompt()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(promptDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(editingPromptID == nil ? "프롬프트 저장" : "프롬프트 수정 저장")
                    }
                }
                .padding(.top, 4)
            } label: {
                Text(editingPromptID == nil ? "새 프롬프트 저장" : "프롬프트 수정")
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? .red : .secondary)
            }

            Text("전송 기본 프롬프트: \(appState.selectedAnalysisPromptDisplayTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox {
                if appState.savedPrompts.isEmpty {
                    Text("저장된 프롬프트가 없습니다.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            TextField("검색", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("프롬프트 검색")

                            Picker("정렬", selection: $sortMode) {
                                ForEach(PromptSortMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            .accessibilityLabel("프롬프트 정렬")
                        }

                        if !allTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    promptTagFilterChip(title: "전체", tag: nil)
                                    ForEach(allTags, id: \.self) { tag in
                                        promptTagFilterChip(title: "#\(tag)", tag: tag)
                                    }
                                }
                            }
                        }

                        if filteredPrompts.isEmpty {
                            Text("조건에 맞는 프롬프트가 없습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }

                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(filteredPrompts) { prompt in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(prompt.title)
                                                .lineLimit(1)

                                            if prompt.isBuiltIn {
                                                builtInBadge
                                            }

                                            if prompt.isFavorite {
                                                Image(systemName: "star.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.yellow)
                                            }
                                        }

                                        Text(promptPreview(prompt.text))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)

                                        if !prompt.tags.isEmpty {
                                            Text(prompt.tags.map { "#\($0)" }.joined(separator: " "))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Button {
                                        appState.setSavedPromptFavorite(id: prompt.id, isFavorite: !prompt.isFavorite)
                                        statusMessage = "\"\(prompt.title)\" \(prompt.isFavorite ? "즐겨찾기 해제" : "즐겨찾기")"
                                        statusIsError = false
                                    } label: {
                                        Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                                    }
                                    .buttonStyle(.bordered)
                                    .help(prompt.isFavorite ? "Unfavorite" : "Favorite")
                                    .accessibilityLabel(prompt.isFavorite ? "즐겨찾기 해제" : "즐겨찾기")

                                    Button {
                                        beginEditing(prompt)
                                    } label: {
                                        Image(systemName: editingPromptID == prompt.id ? "pencil.circle.fill" : "pencil")
                                    }
                                    .buttonStyle(.bordered)
                                    .help("Edit")
                                    .accessibilityLabel("프롬프트 수정")

                                    Button {
                                        copyPrompt(prompt)
                                    } label: {
                                        Image(systemName: copiedPromptID == prompt.id ? "checkmark.circle.fill" : "doc.on.doc")
                                    }
                                    .buttonStyle(.bordered)
                                    .help("Copy")
                                    .accessibilityLabel("프롬프트 복사")

                                    Button {
                                        duplicatePrompt(prompt)
                                    } label: {
                                        Image(systemName: "plus.square.on.square")
                                    }
                                    .buttonStyle(.bordered)
                                    .help("Duplicate")
                                    .accessibilityLabel("프롬프트 복제")

                                    Toggle("기본", isOn: analysisPromptSelectionBinding(for: prompt))
                                    .toggleStyle(.checkbox)
                                    .controlSize(.small)
                                    .font(.caption2)
                                    .help("전송 기본 프롬프트 선택 (하나만 선택)")
                                    .accessibilityLabel("전송 기본 프롬프트 선택")

                                    Button(role: .destructive) {
                                        removePrompt(prompt)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("프롬프트 삭제")
                                }
                                .padding(.vertical, 8)

                                Divider()
                            }
                        }
                    }
                        .frame(maxHeight: 420)
                    }
                }
            } label: {
                HStack {
                    Text("저장된 프롬프트")
                    Spacer()
                    Button("기본 템플릿 동기화") {
                        restoreBuiltInTemplates()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .accessibilityLabel("기본 템플릿 동기화")
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 640, height: 700)
    }

    private func savePrompt() {
        do {
            let tags = parseTags(promptDraftTags)
            if let editingPromptID {
                let updated = try appState.updateSavedPrompt(
                    id: editingPromptID,
                    title: promptDraftTitle,
                    text: promptDraftText,
                    tags: tags,
                    isFavorite: promptDraftIsFavorite
                )
                cancelPromptEditing(clearStatus: false)
                statusMessage = "\"\(updated.title)\" 수정됨"
            } else {
                let saved = try appState.savePrompt(
                    title: promptDraftTitle,
                    text: promptDraftText,
                    tags: tags,
                    isFavorite: promptDraftIsFavorite
                )
                promptDraftTitle = ""
                promptDraftText = ""
                promptDraftTags = ""
                promptDraftIsFavorite = false
                statusMessage = "\"\(saved.title)\" 저장됨"
            }
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func copyPrompt(_ prompt: SavedPrompt) {
        PlatformClipboard.writeString(prompt.text)
        copiedPromptID = prompt.id
        statusMessage = "\"\(prompt.title)\" 복사됨"
        statusIsError = false
    }

    private func duplicatePrompt(_ prompt: SavedPrompt) {
        do {
            let duplicated = try appState.duplicateSavedPrompt(id: prompt.id)
            statusMessage = "\"\(duplicated.title)\" 복제됨"
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func removePrompt(_ prompt: SavedPrompt) {
        appState.removeSavedPrompt(id: prompt.id)
        if copiedPromptID == prompt.id {
            copiedPromptID = nil
        }
        if editingPromptID == prompt.id {
            cancelPromptEditing(clearStatus: false)
        }
        statusMessage = "\"\(prompt.title)\" 삭제됨"
        statusIsError = false
    }

    private func analysisPromptSelectionBinding(for prompt: SavedPrompt) -> Binding<Bool> {
        Binding(
            get: { appState.selectedAnalysisPromptID == prompt.id },
            set: { isSelected in
                setAnalysisPromptSelection(prompt, isSelected: isSelected)
            }
        )
    }

    private func setAnalysisPromptSelection(_ prompt: SavedPrompt, isSelected: Bool) {
        if isSelected {
            appState.setSelectedAnalysisPromptID(prompt.id)
            statusMessage = "\"\(prompt.title)\"을(를) 전송 기본 프롬프트로 지정"
        } else if appState.selectedAnalysisPromptID == prompt.id {
            appState.setSelectedAnalysisPromptID(nil)
            statusMessage = "전송 기본 프롬프트를 내장 기본값으로 변경"
        }
        statusIsError = false
    }

    private func beginEditing(_ prompt: SavedPrompt) {
        editingPromptID = prompt.id
        promptDraftTitle = prompt.title
        promptDraftText = prompt.text
        promptDraftTags = prompt.tags.joined(separator: ", ")
        promptDraftIsFavorite = prompt.isFavorite
        statusMessage = "\"\(prompt.title)\" 수정 중"
        statusIsError = false
    }

    private func cancelPromptEditing(clearStatus: Bool = true) {
        editingPromptID = nil
        promptDraftTitle = ""
        promptDraftText = ""
        promptDraftTags = ""
        promptDraftIsFavorite = false
        if clearStatus {
            statusMessage = ""
            statusIsError = false
        }
    }

    private func restoreBuiltInTemplates() {
        let restoredCount = appState.restoreBuiltInAnalysisPromptTemplates()
        if restoredCount > 0 {
            statusMessage = "기본 템플릿 \(restoredCount)개 반영됨"
            statusIsError = false
        } else {
            statusMessage = "기본 템플릿이 이미 최신 상태입니다"
            statusIsError = false
        }
    }

    private func promptPreview(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var allTags: [String] {
        Array(Set(appState.savedPrompts.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredPrompts: [SavedPrompt] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = appState.savedPrompts.filter { prompt in
            let matchesSearch: Bool
            if normalizedSearch.isEmpty {
                matchesSearch = true
            } else {
                let haystack = [prompt.title, prompt.text] + prompt.tags
                matchesSearch = haystack.joined(separator: " ").localizedCaseInsensitiveContains(normalizedSearch)
            }

            let matchesTag = selectedTagFilter.map { prompt.tags.contains($0) } ?? true
            return matchesSearch && matchesTag
        }

        switch sortMode {
        case .recent:
            return filtered.sorted {
                let lhsDate = $0.updatedAt ?? .distantPast
                let rhsDate = $1.updatedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .title:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .favoritesFirst:
            return filtered.sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                let lhsDate = lhs.updatedAt ?? .distantPast
                let rhsDate = rhs.updatedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private func parseTags(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private func promptTagFilterChip(title: String, tag: String?) -> some View {
        let isSelected = selectedTagFilter == tag
        Button {
            selectedTagFilter = tag
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("태그 필터 \(title)")
    }

    private var builtInBadge: some View {
        Text("내장")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    private enum PromptSortMode: String, CaseIterable, Identifiable {
        case recent
        case title
        case favoritesFirst

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recent:
                return "최근순"
            case .title:
                return "이름순"
            case .favoritesFirst:
                return "즐겨찾기"
            }
        }
    }
}
