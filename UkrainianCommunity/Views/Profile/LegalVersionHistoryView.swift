import SwiftUI

struct LegalVersionReader: View {
    let document: LegalDocument
    @State private var locale = "de"
    var body: some View {
        ProfileDestinationLayout(title: document.type.historyTitle, introSubtitle: AppStrings.legalVersionLabel(document.version)) {
            Picker(AppStrings.LegalManagement.localePicker, selection: $locale) {
                Text(AppStrings.Settings.german).tag("de")
                Text(AppStrings.Settings.ukrainian).tag("uk")
            }.pickerStyle(.segmented)
            if let content = document.content(preferredLocale: locale) {
                AppEditorSectionCard {
                    Text(content.title).font(.title2.bold())
                    LegalMarkdownRenderer(markdown: content.contentMarkdown, fallbackText: content.contentText)
                }
            }
        }
    }
}

struct LegalTextChange: Identifiable, Equatable {
    let id: String
    let text: String
    let added: Bool
    static func compare(old: String, new: String) -> [LegalTextChange] {
        let before = old.components(separatedBy: "\n"), after = new.components(separatedBy: "\n")
        return after.difference(from: before).map { change in
            switch change {
            case .insert(let offset, let text, _): return Self(id: "add-\(offset)", text: text, added: true)
            case .remove(let offset, let text, _): return Self(id: "remove-\(offset)", text: text, added: false)
            }
        }.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct LegalVersionComparisonView: View {
    let previous: LegalDocument
    let current: LegalDocument
    @State private var locale = "de"
    private var changes: [LegalTextChange] {
        LegalTextChange.compare(old: previous.content(preferredLocale: locale)?.contentMarkdown ?? "",
                                new: current.content(preferredLocale: locale)?.contentMarkdown ?? "")
    }
    var body: some View {
        ProfileDestinationLayout(title: LegalEditorText.compare, introSubtitle: "\(previous.version) → \(current.version)") {
            Picker(AppStrings.LegalManagement.localePicker, selection: $locale) {
                Text(AppStrings.Settings.german).tag("de")
                Text(AppStrings.Settings.ukrainian).tag("uk")
            }.pickerStyle(.segmented)
            if changes.isEmpty { Text(LegalEditorText.noChanges).foregroundStyle(AppTheme.textSecondary) }
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(changes) { change in
                    AppEditorSectionCard {
                        Label(change.added ? LegalEditorText.added : LegalEditorText.removed,
                              systemImage: change.added ? "plus.circle" : "minus.circle")
                            .font(.headline).foregroundStyle(AppTheme.accentPrimaryForeground)
                        Text(change.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct LegalVersionHistoryView: View {
    let type: LegalDocumentType
    let active: LegalDocument
    let repository: LegalDocumentRepository
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var documents: [LegalDocument] = []
    @State private var cursor: Int?
    @State private var loaded = false
    @State private var loading = false
    @State private var error = false
    var body: some View {
        ProfileDestinationLayout(title: LegalEditorText.history, introSubtitle: type.historyTitle) {
            if PermissionService.isAppOwner(user: authState.user) {
                if loading && documents.isEmpty { LoadingStateCard(title: nil) }
                if error {
                    ErrorStateCard(systemImage: "clock", title: LegalEditorText.history,
                                   message: AppStrings.LegalManagement.loadFailed,
                                   retryTitle: AppStrings.Action.retry) { Task { await load() } }
                }
                ForEach(documents, id: \.version) { document in
                    AppEditorSectionCard {
                        Text(AppStrings.legalVersionLabel(document.version)).font(.headline)
                        if let date = document.publishedAt { Text(LocalizationStore.dateString(from: date)).foregroundStyle(AppTheme.textSecondary) }
                        if document.version == active.version { Text(LegalEditorText.active).font(.caption) }
                        NavigationLink { LegalVersionReader(document: document) } label: {
                            Label(LegalEditorText.read, systemImage: "doc.text")
                        }
                        if document.version != active.version {
                            NavigationLink { LegalVersionComparisonView(previous: document, current: active) } label: {
                                Label(LegalEditorText.compare, systemImage: "text.badge.plus")
                            }
                        }
                    }
                }
                if loaded && cursor != nil {
                    Button(LegalEditorText.more) { Task { await load() } }.disabled(loading)
                }
            }
        }
        .task { await load() }
        .onChange(of: authState.user?.id) { _, _ in documents = []; dismiss() }
    }
    private func load() async {
        guard !loading, PermissionService.isAppOwner(user: authState.user), !loaded || cursor != nil else { return }
        let userID = authState.user?.id
        loading = true; error = false
        defer { loading = false }
        do {
            let page = try await repository.fetchVersionHistory(type: type, before: cursor)
            guard authState.user?.id == userID else { return }
            let known = Set(documents.map(\.version))
            documents += page.documents.filter { !known.contains($0.version) }
            cursor = page.nextBefore; loaded = true
        } catch { self.error = true }
    }
}

private extension LegalDocumentType {
    var historyTitle: String {
        switch self {
        case .terms: AppStrings.Settings.terms
        case .privacy: AppStrings.Settings.privacyPolicy
        case .organizationRules: AppStrings.OrganizationRules.title
        }
    }
}
