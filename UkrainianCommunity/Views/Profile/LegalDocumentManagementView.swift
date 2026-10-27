import Combine
import SwiftUI

private enum LegalEditorPresentation: Identifiable {
    case preview(LegalDocument, String)
    case close(LegalDocumentDraft)
    case publish(LegalDocumentDraft)
    case discard(LegalDocumentDraft)
    var id: String { switch self { case .preview: "preview"; case .close: "close"; case .publish: "publish"; case .discard: "discard" } }
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
            if !LegalAccessScope(authState).allowsOwner || viewModel.accessDenied {
                ErrorStateCard(
                    systemImage: "lock.fill",
                    title: AppStrings.LegalManagement.permissionTitle,
                    message: AppStrings.LegalManagement.permissionMessage,
                    retryTitle: LegalAccessScope(authState).allowsOwner ? AppStrings.Action.retry : nil
                ) { Task { await viewModel.load() } }
            } else if (!viewModel.hasLoaded || viewModel.isLoading) && viewModel.states.isEmpty {
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
                        if viewModel.failedTypes.contains(type), viewModel.states[type] == nil {
                            ErrorStateCard(systemImage: "doc.badge.ellipsis", title: type.title,
                                           message: AppStrings.LegalManagement.loadFailed,
                                           retryTitle: AppStrings.Action.retry) { Task { await viewModel.load() } }
                        } else {
                        if viewModel.failedTypes.contains(type) {
                            InlineMessageCard(style: .error, message: AppStrings.LegalManagement.loadFailed)
                            Button(AppStrings.Action.retry) { Task { await viewModel.load(types: [type]) } }
                        }
                        LegalDocumentManagementCard(
                            type: type,
                            state: viewModel.states[type],
                            canEdit: !viewModel.failedTypes.contains(type),
                            repository: repository,
                            onSaved: {
                                await viewModel.load(types: [type], force: true)
                            }
                        )
                        }
                    }
                }
                .allowsHitTesting(!viewModel.isLoading)
            }
        }
        .task(id: LegalQueryScope(authState, query: "management")) {
            viewModel.clear()
            viewModel.accessScope = { LegalAccessScope(authState) }
            guard LegalAccessScope(authState).allowsOwner else { return }
            await viewModel.load()
        }
        .appRefreshable {
            guard LegalAccessScope(authState).allowsOwner else { return }
            await viewModel.load()
        }
    }
}

private struct LegalDocumentManagementCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let type: LegalDocumentType
    let state: LegalDocumentManagementState?
    var canEdit = true
    let repository: LegalDocumentRepository
    let onSaved: () async -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
                    Image(systemName: type.systemImage)
                        .font(.system(size: 18, weight: .semibold))
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
                        LegalMetadataLabel(title: AppStrings.legalVersionLabel(activeDocument.version), systemImage: "number")
                            .accessibilityIdentifier("legal.manage.version.\(type.rawValue)")
                        LegalMetadataLabel(
                            title: type == .privacy
                                ? AppStrings.LegalManagement.privacyAcknowledgement
                                : type == .terms || activeDocument.requiresAcceptance
                                    ? AppStrings.LegalManagement.requiresAcceptance
                                    : AppStrings.LegalManagement.acceptanceNotRequired,
                            systemImage: type == .terms || type == .privacy || activeDocument.requiresAcceptance
                                ? "checkmark.seal" : "minus.circle"
                        )
                        if let publishedAt = activeDocument.publishedAt {
                            LegalMetadataLabel(
                                title: AppStrings.legalLastUpdatedLabel(LocalizationStore.dateString(from: publishedAt)),
                                systemImage: "calendar"
                            )
                        }
                    }

                    if state?.draftDocument != nil {
                        LegalMetadataLabel(title: AppStrings.LegalManagement.draftExists, systemImage: "pencil.and.outline")
                    }
                }

                if let active = state?.activeDocument {
                    NavigationLink { LegalVersionReader(document: active) } label: {
                        LegalActionLabel(title: LegalEditorText.active, systemImage: "doc.text.magnifyingglass")
                    }.accessibilityIdentifier("legal.manage.active.\(type.rawValue)")
                    NavigationLink { LegalVersionHistoryView(type: type, active: active, repository: repository) } label: {
                        LegalActionLabel(title: LegalEditorText.history, systemImage: "clock.arrow.circlepath")
                    }.accessibilityIdentifier("legal.manage.history.\(type.rawValue)")
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
                .accessibilityIdentifier("legal.manage.edit.\(type.rawValue)")
                .disabled(state == nil || !canEdit)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @State private var validationErrors: [String] = []
    @State private var presentation: LegalEditorPresentation?
    @State private var editorScope: LegalAccessScope?
    @State private var operationID = UUID()

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
        let loadedDraft = existingDraft ?? LegalDocumentDraft.from(activeDocument: activeDocument)
        var initialDraft = loadedDraft
        initialDraft.requiresAcceptance = true
        if !LegalChangeSummary(raw: initialDraft.changeSummary).hasSeparateTranslations {
            initialDraft.changeSummary = nil
        }
        _draft = State(initialValue: initialDraft)
        _lastSavedDraft = State(initialValue: loadedDraft)
        _hasPersistedDraft = State(initialValue: existingDraft != nil)
    }

    var body: some View {
        PushedScreenShell(
            title: LegalFlowText.editorTitle,
            subtitle: type.title,
            tabBarHidden: true,
            backAction: handleBack
        ) {
            AppGroupedContentPlane(spacing: AppTheme.feedRowSpacing) {
                editorContent
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                PrimaryActionButton(title: dynamicTypeSize.isAccessibilitySize ? LegalFlowText.save : AppStrings.LegalManagement.saveDraft,
                                    loadingTitle: AppStrings.LegalManagement.saving,
                                    isEnabled: (!hasPersistedDraft || hasUnsavedChanges) && !isPublishing && currentSession,
                                    isLoading: isSaving, systemImage: "tray.and.arrow.down.fill") {
                    Task { _ = await saveDraft() }
                }.accessibilityIdentifier("legal.edit.save")
                Menu {
                    Button(AppStrings.LegalManagement.preview, systemImage: "doc.richtext") { presentation = .preview(previewDocument, selectedLocale) }.accessibilityIdentifier("legal.edit.preview")
                    Button(AppStrings.LegalManagement.publish, systemImage: "paperplane", role: .destructive) { validateAndConfirmPublish() }.accessibilityIdentifier("legal.edit.publish")
                    if hasPersistedDraft {
                        Button(LegalEditorText.discard, systemImage: "trash", role: .destructive) { presentation = .discard(lastSavedDraft) }
                            .accessibilityIdentifier("legal.edit.discard")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 24, weight: .semibold))
                        .frame(width: 44, height: 44).accessibilityLabel(LegalEditorText.actions)
                }
                .accessibilityIdentifier("legal.edit.actions")
                .disabled(isSaving || isPublishing || !currentSession)
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .task { if editorScope == nil { editorScope = LegalAccessScope(authState) } }
        .onChange(of: LegalAccessScope(authState)) { _, _ in
            operationID = UUID(); presentation = nil; isSaving = false; isPublishing = false; dismiss()
        }
        .onChange(of: draft) { _, _ in
            if !isSaving && !isPublishing && hasUnsavedChanges { statusMessage = nil; validationErrors = [] }
        }
        .sheet(item: $presentation) { presentationContent($0) }
    }

    @ViewBuilder private func presentationContent(_ route: LegalEditorPresentation) -> some View {
        switch route {
        case let .preview(document, locale):
            NavigationStack { LegalMarkdownPreview(document: document, preferredLocale: locale) }
        case let .close(command):
            NotificationConfirmationSheet(title: LegalEditorText.closeTitle, cancel: { presentation = nil }) {
                NotificationConfirmationAction(title: AppStrings.LegalManagement.saveDraft, id: "legal.edit.closeSave") {
                    presentation = nil
                    Task { if await saveDraft(command) { dismiss() } }
                }
                NotificationConfirmationAction(title: LegalEditorText.leaveUnsaved, id: "legal.edit.leaveUnsaved", role: .destructive) {
                    presentation = nil; dismiss()
                }
            }
        case let .discard(command):
            NotificationConfirmationSheet(title: LegalEditorText.discardTitle,
                message: type.title + "\n" + AppStrings.legalVersionLabel(command.version) + "\n\n" + LegalEditorText.discardMessage,
                cancel: { presentation = nil }) {
                NotificationConfirmationAction(title: LegalEditorText.discard, id: "legal.edit.confirmDiscard", role: .destructive) {
                    presentation = nil; Task { await discardDraft(command) }
                }
            }
        case let .publish(command):
            NotificationConfirmationSheet(title: AppStrings.LegalManagement.publishConfirmTitle,
                message: type.title + "\n" + AppStrings.legalVersionLabel(command.version) + "\n\n" +
                    (type == .privacy ? LegalEditorText.privacyPublishMessage : AppStrings.LegalManagement.publishConfirmMessage),
                cancel: { presentation = nil }) {
                NotificationConfirmationAction(title: AppStrings.LegalManagement.publish, id: "legal.edit.confirmPublish", role: .destructive) {
                    presentation = nil; Task { await publish(command) }
                }
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
                    Text(LegalEditorText.privateDraft).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SectionHeaderBlock(
                        title: type == .privacy ? LegalEditorText.privacyVersionTitle : AppStrings.LegalManagement.versionSection,
                        subtitle: AppStrings.LegalManagement.versionSectionSubtitle
                    )

                    LegalMetadataLabel(title: AppStrings.legalVersionLabel(draft.version), systemImage: "number")
                        .accessibilityIdentifier("legal.edit.version")

                    LegalMetadataLabel(
                        title: type == .privacy ? AppStrings.LegalManagement.privacyAcknowledgement : AppStrings.LegalManagement.requiresAcceptance,
                        systemImage: "checkmark.seal"
                    )

                    Text(AppStrings.LegalManagement.changeSummaryGerman).font(.subheadline.weight(.semibold))
                    TextField(AppStrings.LegalManagement.changeSummaryGerman, text: changeSummaryBinding(locale: "de"), axis: .vertical)
                        .accessibilityIdentifier("legal.edit.summary.de")
                        .lineLimit(2...4)
                        .appEditorInputStyle(minHeight: 72)
                    Text(AppStrings.LegalManagement.changeSummaryUkrainian).font(.subheadline.weight(.semibold))
                    TextField(AppStrings.LegalManagement.changeSummaryUkrainian, text: changeSummaryBinding(locale: "uk"), axis: .vertical)
                        .accessibilityIdentifier("legal.edit.summary.uk")
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
                        .init("title", AppStrings.LegalManagement.localizedTitle, source: draft.locales[selectedLocale]?.title ?? "", target: translationBinding(title: true), limit: 500),
                        .init("markdown", AppStrings.LegalManagement.localizedContent, source: draft.locales[selectedLocale]?.contentMarkdown ?? "", target: translationBinding(title: false), limit: 100000)
                    ], sourceLanguage: selectedLocale == "de" ? .german : .ukrainian)


                    Picker(AppStrings.LegalManagement.localePicker, selection: $selectedLocale) {
                        Text(AppStrings.Settings.german).tag(AppLanguage.german.rawValue)
                        Text(AppStrings.Settings.ukrainian).tag(AppLanguage.ukrainian.rawValue)
                    }
                    .pickerStyle(.segmented)

                    Text(AppStrings.LegalManagement.localizedTitle).font(.subheadline.weight(.semibold))
                    TextField(AppStrings.LegalManagement.localizedTitle, text: localizedTitleBinding, axis: .vertical)
                        .lineLimit(1...4).accessibilityIdentifier("legal.edit.title")
                        .appEditorInputStyle()

                    Text(AppStrings.LegalManagement.localizedContent).font(.subheadline.weight(.semibold))
                    TextEditor(text: localizedMarkdownBinding)
                        .accessibilityIdentifier("legal.edit.body")
                        .frame(height: 320)
                        .scrollContentBackground(.hidden)
                        .appEditorInputStyle(minHeight: 260)
                }
            }


        }
        .padding(.bottom, 16)
        .disabled(isSaving || isPublishing || presentation != nil || !currentSession)
    }

    private func changeSummaryBinding(locale: String) -> Binding<String> {
        Binding(
            get: { LegalChangeSummary(raw: draft.changeSummary).localized(locale) },
            set: { value in
                validationErrors = []
                var summary = LegalChangeSummary(raw: draft.changeSummary)
                if locale == "uk" { summary.ukrainian = value } else { summary.german = value }
                draft.changeSummary = summary.encoded
            }
        )
    }

    private var hasUnsavedChanges: Bool {
        normalizedDraft != normalized(lastSavedDraft)
    }

    private func translationBinding(title: Bool) -> Binding<String> {
        let target = selectedLocale == "de" ? "uk" : "de"
        return Binding(get: { title ? draft.locales[target]?.title ?? "" : draft.locales[target]?.contentMarkdown ?? "" }, set: { text in
            updateLocale(title: title ? text : nil, markdown: title ? nil : text, locale: target)
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

    private var currentSession: Bool {
        let current = LegalAccessScope(authState)
        return current.allowsOwner && current == editorScope
    }

    private func requireCurrent(_ scope: LegalAccessScope, operation: UUID) throws {
        guard currentSession, scope == LegalAccessScope(authState), operation == operationID, !Task.isCancelled else { throw CancellationError() }
    }

    private func persist(_ command: LegalDocumentDraft, scope: LegalAccessScope, operation: UUID) async throws -> LegalDocumentDraft {
        try requireCurrent(scope, operation: operation)
        guard let userID = scope.identity.userID else { throw AppError.permissionDenied }
        try await repository.saveDraft(command, updatedBy: userID)
        try requireCurrent(scope, operation: operation)
        var saved = command
        saved.sourceContentHash = saved.normalizedContentHash
        saved.sourceStateHash = saved.stateHash
        draft = saved; lastSavedDraft = saved; hasPersistedDraft = true
        await onSaved()
        try requireCurrent(scope, operation: operation)
        return saved
    }

    private func saveDraft(_ captured: LegalDocumentDraft? = nil) async -> Bool {
        guard currentSession, !isSaving, !isPublishing else { return false }
        let command = captured ?? normalizedDraft
        guard command.stateHash == normalizedDraft.stateHash else { statusMessage = LegalFlowText.conflict; statusStyle = .error; return false }
        guard !hasPersistedDraft || hasUnsavedChanges else { return true }
        guard command.locales.values.allSatisfy({ $0.title.utf16.count <= 500 && $0.contentMarkdown.utf16.count <= 100000 }) else {
            validationErrors = [LegalEditorText.tooLong]; return false
        }
        let scope = LegalAccessScope(authState), operation = UUID()
        operationID = operation; isSaving = true; statusMessage = nil; validationErrors = []
        defer { if operationID == operation { isSaving = false } }
        do {
            _ = try await persist(command, scope: scope, operation: operation)
            statusStyle = .success; statusMessage = AppStrings.LegalManagement.draftSaved
            return true
        } catch is CancellationError { return false }
        catch { if currentSession && operationID == operation { showMutationFailure(error, publishing: false) }; return false }
    }

    private func publish(_ captured: LegalDocumentDraft) async {
        guard currentSession, !isSaving, !isPublishing else { return }
        guard captured.stateHash == normalizedDraft.stateHash else { showMutationFailure(AppError.validationFailed, publishing: true); return }
        validationErrors = publishValidationErrors(for: captured)
        guard validationErrors.isEmpty else { return }
        let scope = LegalAccessScope(authState), operation = UUID()
        operationID = operation; isPublishing = true; statusMessage = nil
        defer { if operationID == operation { isPublishing = false } }
        do {
            var command = captured
            if !hasPersistedDraft || hasUnsavedChanges { command = try await persist(command, scope: scope, operation: operation) }
            try requireCurrent(scope, operation: operation)
            guard let userID = scope.identity.userID else { throw AppError.permissionDenied }
            try await repository.publishDraft(command, publishedBy: userID)
            try requireCurrent(scope, operation: operation)
            await onSaved()
            try requireCurrent(scope, operation: operation)
            dismiss()
        } catch is CancellationError { return }
        catch { if currentSession && operationID == operation { showMutationFailure(error, publishing: true) } }
    }

    private func handleBack() {
        guard !isSaving, !isPublishing else { return }
        guard hasUnsavedChanges else { dismiss(); return }
        presentation = .close(normalizedDraft)
    }

    private func discardDraft(_ captured: LegalDocumentDraft) async {
        guard currentSession, !isSaving, !isPublishing else { return }
        let scope = LegalAccessScope(authState), operation = UUID()
        operationID = operation; isSaving = true; statusMessage = nil
        defer { if operationID == operation { isSaving = false } }
        do {
            try requireCurrent(scope, operation: operation)
            try await repository.discardDraft(captured)
            try requireCurrent(scope, operation: operation)
            await onSaved()
            try requireCurrent(scope, operation: operation)
            dismiss()
        } catch is CancellationError { return }
        catch { if currentSession && operationID == operation { showMutationFailure(error, publishing: false) } }
    }

    private func showMutationFailure(_ error: Error, publishing: Bool) {
        statusStyle = .error
        statusMessage = error as? AppError == .validationFailed ? LegalFlowText.conflict
            : publishing ? AppStrings.LegalManagement.publishFailed : AppStrings.LegalManagement.saveFailed
    }

    private func validateAndConfirmPublish() {
        guard currentSession, !isSaving, !isPublishing else { return }
        statusMessage = nil
        let command = normalizedDraft
        validationErrors = publishValidationErrors(for: command)
        if validationErrors.isEmpty { presentation = .publish(command) }
    }

    private func publishValidationErrors(for draft: LegalDocumentDraft) -> [String] {
        var errors: [String] = []
        if !draft.locales.values.allSatisfy({ $0.title.utf16.count <= 500 && $0.contentMarkdown.utf16.count <= 100000 }) {
            errors.append(LegalEditorText.tooLong)
        }
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

        if !LegalChangeSummary(raw: draft.changeSummary).hasBothLanguages {
            errors.append(AppStrings.LegalManagement.missingChangeSummaries)
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
                    LegalMetadataLabel(title: AppStrings.legalVersionLabel(document.version), systemImage: "number")
                }

                AppEditorSectionCard {
                    LegalDocumentText(content: content)
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
