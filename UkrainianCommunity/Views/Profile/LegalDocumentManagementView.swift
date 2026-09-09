import Combine
import SwiftUI

@MainActor
final class LegalDocumentManagementViewModel: ObservableObject {
    @Published var states: [LegalDocumentType: LegalDocumentManagementState] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository: LegalDocumentRepository
    private var loadGeneration = 0

    init(repository: LegalDocumentRepository) {
        self.repository = repository
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil

        do {
            async let termsState = RefreshRequest.run { [self] in try await repository.fetchManagementState(type: .terms) }
            async let privacyState = RefreshRequest.run { [self] in try await repository.fetchManagementState(type: .privacy) }
            async let organizationRulesState = RefreshRequest.run { [self] in try await repository.fetchManagementState(type: .organizationRules) }
            let loadedStates = try await [termsState, privacyState, organizationRulesState]
            guard generation == loadGeneration else { return }
            states = Dictionary(uniqueKeysWithValues: loadedStates.map { ($0.type, $0) })
        } catch {
            guard generation == loadGeneration else { return }
            // A management snapshot must be authoritative as a unit. Keeping
            // old cards editable after any failed component read can publish
            // from a stale active version.
            states = [:]
            errorMessage = AppStrings.LegalManagement.loadFailed
        }
        if generation == loadGeneration { isLoading = false }
    }
}

struct LegalDocumentManagementView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: LegalDocumentManagementViewModel
    private let repository: LegalDocumentRepository

    init(repository: LegalDocumentRepository) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: LegalDocumentManagementViewModel(repository: repository))
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.LegalManagement.title,
            introSubtitle: AppStrings.LegalManagement.subtitle
        ) {
            if !PermissionService.isAppOwner(user: authState.user) {
                ErrorStateCard(
                    systemImage: "lock.fill",
                    title: AppStrings.LegalManagement.permissionTitle,
                    message: AppStrings.LegalManagement.permissionMessage
                )
            } else if viewModel.isLoading && viewModel.states.isEmpty {
                LoadingStateCard(title: nil)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let errorMessage = viewModel.errorMessage, viewModel.states.isEmpty {
                ErrorStateCard(
                    systemImage: "doc.badge.ellipsis",
                    title: AppStrings.LegalManagement.title,
                    message: errorMessage,
                    retryTitle: AppStrings.Action.retry
                ) {
                    Task { await viewModel.load() }
                }
            } else {
                VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                    if let errorMessage = viewModel.errorMessage {
                        InlineMessageCard(style: .error, message: errorMessage)
                    }

                    ForEach(LegalDocumentType.allCases) { type in
                        LegalDocumentManagementCard(
                            type: type,
                            state: viewModel.states[type],
                            repository: repository,
                            onSaved: {
                                await viewModel.load()
                            }
                        )
                    }
                }
                .allowsHitTesting(!viewModel.isLoading)
            }
        }
        .task {
            await viewModel.load()
        }
        .appRefreshable {
            await viewModel.load()
        }
    }
}

private struct LegalDocumentManagementCard: View {
    let type: LegalDocumentType
    let state: LegalDocumentManagementState?
    let repository: LegalDocumentRepository
    let onSaved: () async -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: type.systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(type.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if let activeDocument = state?.activeDocument {
                        AppInfoChip(title: AppStrings.legalVersionLabel(activeDocument.version), systemImage: "number")
                        AppInfoChip(
                            title: activeDocument.requiresAcceptance ? AppStrings.LegalManagement.requiresAcceptance : AppStrings.LegalManagement.acceptanceNotRequired,
                            systemImage: activeDocument.requiresAcceptance ? "checkmark.seal" : "minus.circle"
                        )
                        if let publishedAt = activeDocument.publishedAt {
                            AppInfoChip(
                                title: AppStrings.legalLastUpdatedLabel(LocalizationStore.dateString(from: publishedAt)),
                                systemImage: "calendar"
                            )
                        }
                    }

                    if state?.draftDocument != nil {
                        AppInfoChip(title: AppStrings.LegalManagement.draftExists, systemImage: "pencil.and.outline")
                    }
                }

                NavigationLink {
                    LegalDocumentEditorView(
                        type: type,
                        state: state,
                        repository: repository,
                        onSaved: onSaved
                    )
                } label: {
                    ProfileModuleRow(
                        title: state?.draftDocument == nil ? AppStrings.LegalManagement.createDraft : AppStrings.LegalManagement.editDraft,
                        subtitle: AppStrings.LegalManagement.editorSubtitle,
                        systemImage: "square.and.pencil",
                        status: .available
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var subtitle: String {
        switch type {
        case .terms:
            return AppStrings.LegalManagement.termsSubtitle
        case .privacy:
            return AppStrings.LegalManagement.privacySubtitle
        case .organizationRules:
            return AppStrings.LegalManagement.organizationRulesSubtitle
        }
    }
}

private struct LegalDocumentEditorView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    let type: LegalDocumentType
    let state: LegalDocumentManagementState?
    let repository: LegalDocumentRepository
    let onSaved: () async -> Void

    @State private var draft: LegalDocumentDraft
    @State private var lastSavedDraft: LegalDocumentDraft
    @State private var hasPersistedDraft: Bool
    @State private var selectedLocale = AppLanguage.german.rawValue
    @State private var isSaving = false
    @State private var isPublishing = false
    @State private var statusMessage: String?
    @State private var statusStyle: InlineMessageStyle = .info
    @State private var isShowingPreview = false
    @State private var isConfirmingPublish = false
    @State private var validationErrors: [String] = []

    init(
        type: LegalDocumentType,
        state: LegalDocumentManagementState?,
        repository: LegalDocumentRepository,
        onSaved: @escaping () async -> Void
    ) {
        self.type = type
        self.state = state
        self.repository = repository
        self.onSaved = onSaved
        let activeDocument = state?.activeDocument ?? LegalDocument.hardcodedFallback(type: type)
        var existingDraft = state?.draftDocument.map { LegalDocumentDraft(document: $0) }
        if existingDraft?.supersedesVersion == nil {
            existingDraft?.supersedesVersion = activeDocument.version
        }
        let initialDraft = existingDraft ?? LegalDocumentDraft.from(activeDocument: activeDocument)
        _draft = State(initialValue: initialDraft)
        _lastSavedDraft = State(initialValue: initialDraft)
        _hasPersistedDraft = State(initialValue: existingDraft != nil)
    }

    var body: some View {
        PushedScreenShell(
            title: AppStrings.LegalManagement.editorTitle(type.title),
            subtitle: AppStrings.LegalManagement.editorIntro,
            backAction: handleBack
        ) {
            AppGroupedContentPlane(spacing: AppTheme.feedRowSpacing) {
                editorContent
            }
        }
        .confirmationDialog(
            AppStrings.LegalManagement.publishConfirmTitle,
            isPresented: $isConfirmingPublish,
            titleVisibility: .visible
        ) {
            Button(AppStrings.LegalManagement.publish, role: .destructive) {
                Task { await publish() }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.LegalManagement.publishConfirmMessage)
        }
        .sheet(isPresented: $isShowingPreview) {
            NavigationStack {
                LegalMarkdownPreview(document: previewDocument, preferredLocale: selectedLocale)
            }
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
            if let statusMessage {
                InlineMessageCard(style: statusStyle, message: statusMessage)
            }

            ForEach(validationErrors, id: \.self) { validationError in
                InlineMessageCard(style: .error, message: validationError)
            }

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    SectionHeaderBlock(
                        title: AppStrings.LegalManagement.versionSection,
                        subtitle: AppStrings.LegalManagement.versionSectionSubtitle
                    )

                    AppInfoChip(title: AppStrings.legalVersionLabel(draft.version), systemImage: "number")

                    Toggle(AppStrings.LegalManagement.requiresAcceptance, isOn: $draft.requiresAcceptance)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    TextField(AppStrings.LegalManagement.changeSummary, text: changeSummaryBinding, axis: .vertical)
                        .lineLimit(2...4)
                        .appEditorInputStyle(minHeight: 72)
                }
            }

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    SectionHeaderBlock(
                        title: AppStrings.LegalManagement.localizedContent,
                        subtitle: AppStrings.LegalManagement.localizedContentSubtitle
                    )

                    ContentTranslationButton(kind: "legal", fields: [
                        .init("title", AppStrings.LegalManagement.localizedTitle, source: draft.locales["uk"]?.title ?? "", target: translationBinding(title: true), limit: 500),
                        .init("markdown", AppStrings.LegalManagement.localizedContent, source: draft.locales["uk"]?.contentMarkdown ?? "", target: translationBinding(title: false), limit: 20000)
                    ])

                    Picker(AppStrings.LegalManagement.localePicker, selection: $selectedLocale) {
                        Text(AppStrings.Settings.german).tag(AppLanguage.german.rawValue)
                        Text(AppStrings.Settings.ukrainian).tag(AppLanguage.ukrainian.rawValue)
                    }
                    .pickerStyle(.segmented)

                    TextField(AppStrings.LegalManagement.localizedTitle, text: localizedTitleBinding)
                        .appEditorInputStyle()

                    TextEditor(text: localizedMarkdownBinding)
                        .frame(minHeight: 260)
                        .scrollContentBackground(.hidden)
                        .appEditorInputStyle(minHeight: 260)
                }
            }

            AppEditorSectionCard {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    PrimaryActionButton(
                        title: AppStrings.LegalManagement.saveDraft,
                        loadingTitle: AppStrings.LegalManagement.saving,
                        isEnabled: (!hasPersistedDraft || hasUnsavedChanges) && !isPublishing,
                        isLoading: isSaving,
                        systemImage: "tray.and.arrow.down.fill"
                    ) {
                        Task { _ = await saveDraft() }
                    }

                    Button {
                        isShowingPreview = true
                    } label: {
                        Label(AppStrings.LegalManagement.preview, systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                    }
                    .appActionButtonStyle(.secondary)

                    Button(role: .destructive) {
                        validateAndConfirmPublish()
                    } label: {
                        Label(isPublishing ? AppStrings.LegalManagement.publishing : AppStrings.LegalManagement.publish, systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .appActionButtonStyle(.secondary)
                    .disabled(isPublishing || isSaving)
                }
            }
        }
    }

    private var changeSummaryBinding: Binding<String> {
        Binding(
            get: { draft.changeSummary ?? "" },
            set: { draft.changeSummary = $0.isEmpty ? nil : $0 }
        )
    }

    private var hasUnsavedChanges: Bool {
        normalizedDraft != normalized(lastSavedDraft)
    }

    private func translationBinding(title: Bool) -> Binding<String> {
        Binding(get: { title ? draft.locales["de"]?.title ?? "" : draft.locales["de"]?.contentMarkdown ?? "" }, set: { text in
            updateLocale(title: title ? text : nil, markdown: title ? nil : text, locale: "de")
        })
    }

    private var localizedTitleBinding: Binding<String> {
        Binding(
            get: { draft.locales[selectedLocale]?.title ?? "" },
            set: { updateLocale(title: $0, markdown: nil) }
        )
    }

    private var localizedMarkdownBinding: Binding<String> {
        Binding(
            get: { draft.locales[selectedLocale]?.contentMarkdown ?? "" },
            set: { updateLocale(title: nil, markdown: $0) }
        )
    }

    private var previewDocument: LegalDocument {
        LegalDocument(
            id: type.rawValue,
            type: type,
            version: draft.version,
            versionNumber: draft.versionNumber,
            locales: draft.locales,
            defaultLocale: draft.defaultLocale,
            canonicalLocale: draft.canonicalLocale,
            contentHash: nil,
            changeSummary: draft.changeSummary,
            requiresAcceptance: draft.requiresAcceptance,
            status: .draft,
            updatedAt: .now,
            updatedBy: authState.user?.id,
            publishedAt: nil,
            publishedBy: nil
        )
    }

    private func updateLocale(title: String?, markdown: String?, locale: String? = nil) {
        let locale = locale ?? selectedLocale
        validationErrors = []
        let existing = draft.locales[locale]
            ?? LegalDocumentLocaleContent(title: "", contentMarkdown: "", contentText: nil, contentHash: nil)
        draft.locales[locale] = LegalDocumentLocaleContent(
            title: title ?? existing.title,
            contentMarkdown: markdown ?? existing.contentMarkdown,
            contentText: nil,
            contentHash: existing.contentHash
        )
    }

    private func saveDraft() async -> Bool {
        guard let userID = authState.user?.id else { return false }
        guard !isSaving, !isPublishing else { return false }
        guard !hasPersistedDraft || hasUnsavedChanges else { return true }
        isSaving = true
        statusMessage = nil
        validationErrors = []
        defer { isSaving = false }

        do {
            var finalDraft = normalizedDraft
            try await repository.saveDraft(finalDraft, updatedBy: userID)
            finalDraft.sourceContentHash = finalDraft.normalizedContentHash
            draft = finalDraft
            lastSavedDraft = finalDraft
            hasPersistedDraft = true
            await onSaved()
            statusStyle = .success
            statusMessage = AppStrings.LegalManagement.draftSaved
            return true
        } catch {
            statusStyle = .error
            statusMessage = AppStrings.LegalManagement.saveFailed
            return false
        }
    }

    private func publish() async {
        guard let userID = authState.user?.id else { return }
        guard !isSaving, !isPublishing else { return }
        guard publishValidationErrors(for: normalizedDraft).isEmpty else {
            validateAndConfirmPublish()
            return
        }

        statusMessage = nil
        validationErrors = []

        if (!hasPersistedDraft || hasUnsavedChanges), !(await saveDraft()) { return }
        isPublishing = true
        defer { isPublishing = false }

        do {
            let finalDraft = normalizedDraft
            try await repository.publishDraft(finalDraft, publishedBy: userID)
            await onSaved()
            dismiss()
        } catch {
            statusStyle = .error
            statusMessage = AppStrings.LegalManagement.publishFailed
        }
    }

    private func handleBack() {
        guard !isSaving, !isPublishing else { return }
        guard hasUnsavedChanges else {
            dismiss()
            return
        }
        Task {
            if await saveDraft() { dismiss() }
        }
    }

    private func validateAndConfirmPublish() {
        statusMessage = nil
        validationErrors = publishValidationErrors(for: normalizedDraft)
        isConfirmingPublish = validationErrors.isEmpty
    }

    private func publishValidationErrors(for draft: LegalDocumentDraft) -> [String] {
        var errors: [String] = []
        let germanContent = draft.locales[AppLanguage.german.rawValue]
        let ukrainianContent = draft.locales[AppLanguage.ukrainian.rawValue]

        if germanContent?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            errors.append(AppStrings.LegalManagement.missingGermanTitle)
        }

        if germanContent?.contentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            errors.append(AppStrings.LegalManagement.missingGermanContent)
        }

        if ukrainianContent?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            errors.append(AppStrings.LegalManagement.missingUkrainianTitle)
        }

        if ukrainianContent?.contentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            errors.append(AppStrings.LegalManagement.missingUkrainianContent)
        }

        return errors
    }

    private var normalizedDraft: LegalDocumentDraft {
        normalized(draft)
    }

    private func normalized(_ source: LegalDocumentDraft) -> LegalDocumentDraft {
        var copy = source
        copy.defaultLocale = AppLanguage.german.rawValue
        copy.canonicalLocale = AppLanguage.german.rawValue
        copy.changeSummary = copy.changeSummary?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        for language in AppLanguage.allCases {
            let key = language.rawValue
            if copy.locales[key] == nil {
                copy.locales[key] = LegalDocumentLocaleContent(
                    title: type.title,
                    contentMarkdown: "",
                    contentText: nil,
                    contentHash: nil
                )
            }
        }
        return copy
    }
}

private struct LegalMarkdownPreview: View {
    @Environment(\.dismiss) private var dismiss
    let document: LegalDocument
    let preferredLocale: String

    private var content: LegalDocumentLocaleContent {
        document.content(preferredLocale: preferredLocale)
            ?? LegalDocument.hardcodedFallback(type: document.type).content(preferredLocale: preferredLocale)
            ?? LegalDocumentLocaleContent(title: document.type.title, contentMarkdown: "", contentText: nil, contentHash: nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppEditorSectionCard {
                    SectionHeaderBlock(title: content.title, subtitle: AppStrings.legalVersionLabel(document.version))
                }

                AppEditorSectionCard {
                    LegalMarkdownRenderer(
                        markdown: content.contentMarkdown,
                        fallbackText: content.contentText
                    )
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.vertical, AppTheme.sectionSpacing)
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(AppStrings.LegalManagement.preview)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppStrings.Common.done) { dismiss() }
            }
        }
    }

}

private extension LegalDocumentDraft {
    init(document: LegalDocument) {
        self.init(
            type: document.type,
            version: document.version,
            versionNumber: document.versionNumber,
            defaultLocale: document.defaultLocale,
            canonicalLocale: document.canonicalLocale ?? document.defaultLocale,
            locales: document.locales,
            requiresAcceptance: document.requiresAcceptance,
            changeSummary: document.changeSummary,
            supersedesVersion: document.supersedesVersion,
            sourceContentHash: document.status == .draft ? document.contentHash : nil
        )
    }
}

private extension LegalDocumentType {
    var title: String {
        switch self {
        case .terms:
            return AppStrings.Settings.terms
        case .privacy:
            return AppStrings.Settings.privacyPolicy
        case .organizationRules:
            return AppStrings.OrganizationRules.title
        }
    }

    var systemImage: String {
        switch self {
        case .terms: "doc.text.fill"
        case .privacy: "lock.shield.fill"
        case .organizationRules: "building.2.crop.circle.fill"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
