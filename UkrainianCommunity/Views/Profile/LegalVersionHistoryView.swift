import SwiftUI

struct LegalVersionReader: View {
    let document: LegalDocument
    @State private var locale = AppLanguage.stored.rawValue
    var body: some View {
        ProfileDestinationLayout(title: document.type.historyTitle, introSubtitle: AppStrings.legalVersionLabel(document.version)) {
            Picker(AppStrings.LegalManagement.localePicker, selection: $locale) {
                Text(AppStrings.Settings.german).tag("de")
                Text(AppStrings.Settings.ukrainian).tag("uk")
            }.pickerStyle(.segmented)
            if let content = document.content(preferredLocale: locale) {
                AppEditorSectionCard {
                    LegalDocumentText(content: content)
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
    @State private var locale = AppLanguage.stored.rawValue
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
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LegalHistoryViewModel
    init(type: LegalDocumentType, active: LegalDocument, repository: LegalDocumentRepository) {
        self.type = type
        _model = StateObject(wrappedValue: LegalHistoryViewModel(type: type, active: active, repository: repository))
    }
    var body: some View {
        ProfileDestinationLayout(title: LegalEditorText.history, introSubtitle: type.historyTitle) {
            if !LegalAccessScope(authState).allowsOwner || model.accessDenied {
                ErrorStateCard(systemImage: "lock.fill", title: AppStrings.LegalManagement.permissionTitle,
                               message: AppStrings.LegalManagement.permissionMessage)
            } else {
                if !model.hasLoaded || model.loading && model.documents.isEmpty { LoadingStateCard(title: nil) }
                if model.error {
                    ErrorStateCard(systemImage: "clock", title: LegalEditorText.history,
                                   message: AppStrings.LegalManagement.loadFailed, retryTitle: AppStrings.Action.retry) {
                        Task { await model.retry() }
                    }
                }
                if model.hasLoaded && !model.error && model.documents.isEmpty {
                    Text(model.canLoadMore ? LegalEvidenceText.continueHistory : LegalFlowText.historyEmpty)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                if !model.documents.isEmpty {
                    Text(LegalFlowText.historyContext).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    LegalMetadataLabel(title: AppStrings.legalVersionLabel(model.reference.version), systemImage: "number")
                }
                ForEach(model.documents, id: \.version) { document in
                    AppEditorSectionCard {
                        Text(AppStrings.legalVersionLabel(document.version)).font(.headline)
                        if let date = document.publishedAt {
                            Text(LocalizationStore.dateString(from: date)).font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if document.version == model.reference.version { Text(LegalEditorText.active).font(.caption) }
                        NavigationLink { LegalVersionReader(document: document) } label: {
                            LegalActionLabel(title: LegalEditorText.read, systemImage: "doc.text")
                        }.accessibilityIdentifier("legal.history.read.\(document.version)")
                        if document.version != model.reference.version {
                            NavigationLink { LegalVersionComparisonView(previous: document, current: model.reference) } label: {
                                LegalActionLabel(title: LegalEditorText.compare, systemImage: "text.badge.plus")
                            }.accessibilityIdentifier("legal.history.compare.\(document.version)")
                        }
                    }
                }
                if model.canLoadMore {
                    PrimaryActionButton(title: LegalEditorText.more, isEnabled: !model.loading) { Task { await model.load(reset: false) } }
                }
            }
        }
        .task(id: LegalQueryScope(authState, query: "history")) {
            model.clear(); model.accessScope = { LegalAccessScope(authState) }
            guard LegalAccessScope(authState).allowsOwner else { return }
            await model.load()
        }
        .appRefreshable { await model.load() }
        .onChange(of: LegalAccessScope(authState)) { _, _ in model.clear(); dismiss() }
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
