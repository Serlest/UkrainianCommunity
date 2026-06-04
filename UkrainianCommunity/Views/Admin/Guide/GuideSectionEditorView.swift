import SwiftUI

struct GuideSectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GuideSectionEditorViewModel
    let onSaved: @MainActor (GuideNode) async -> Void

    init(
        viewModel: GuideSectionEditorViewModel,
        onSaved: @escaping @MainActor (GuideNode) async -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSaved = onSaved
    }

    var body: some View {
        DetailPageContainer {
            editorHeader
                .padding(.top, AppTheme.dashboardSpacing)
            statusCard
            editorCard
            actionCard
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .dismissesKeyboardOnBackgroundTap()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: viewModel.title) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.summary) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.regionScope) { _, newValue in
            if newValue != .federalState {
                viewModel.federalState = nil
            }
            viewModel.clearTransientState()
        }
        .onChange(of: viewModel.federalState) { _, _ in viewModel.clearTransientState() }
    }

    private var editorHeader: some View {
        AppCenteredBrandHeader {
            AppGlassIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.Common.cancel) {
                dismiss()
            }
        } trailingContent: {
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        if !viewModel.validationErrors.isEmpty || statusMessage != nil {
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    if let statusMessage {
                        Text(statusMessage)
                            .font(AppTheme.metadataFont)
                            .foregroundStyle(statusTint)
                    }

                    ForEach(viewModel.validationErrors.map(\.message), id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(AppTheme.metadataFont)
                            .foregroundStyle(AppTheme.accentDestructive)
                    }
                }
            }
        }
    }

    private var editorCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                SectionHeaderBlock(
                    title: screenTitle,
                    subtitle: headerSubtitle
                )

                placementContext

                AppEditorField(title: GuideAuthoringPresentation.titleLabel) {
                    TextField(GuideAuthoringPresentation.titleLabel, text: $viewModel.title, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .appEditorInputStyle()
                }

                AppEditorField(title: GuideAuthoringPresentation.shortDescriptionLabel) {
                    TextField(GuideAuthoringPresentation.localized(uk: "Необов’язково", de: "Optional", en: "Optional"), text: $viewModel.summary, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .frame(minHeight: 100, alignment: .topLeading)
                        .appEditorInputStyle(minHeight: 100)
                }

                regionSpecificSection
            }
        }
    }

    private var actionCard: some View {
        AppEditorSectionCard {
            PrimaryActionButton(
                title: viewModel.saveButtonTitle,
                loadingTitle: GuideAuthoringPresentation.savingLabel,
                isEnabled: !viewModel.isSaving,
                isLoading: viewModel.isSaving,
                systemImage: "square.and.arrow.down"
            ) {
                Task {
                    if let node = await viewModel.save() {
                        await onSaved(node)
                        dismiss()
                    }
                }
            }
        }
    }

    private var placementContext: some View {
        VStack(alignment: .leading, spacing: 6) {
            contextRow(
                label: GuideAuthoringPresentation.categoryLabel,
                value: GuideCategoryPresentation.publicTitle(for: viewModel.category)
            )
            contextRow(
                label: GuideAuthoringPresentation.placementHintLabel,
                value: viewModel.mode.parentPathDescription
            )
        }
    }

    private var regionSpecificSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            SectionHeaderBlock(
                title: GuideAuthoringPresentation.regionTitle,
                subtitle: GuideAuthoringPresentation.localized(
                    uk: "Виберіть, чи цей розділ стосується всієї Австрії або окремої землі.",
                    de: "Wählen Sie, ob dieser Abschnitt für ganz Österreich oder für ein Bundesland gilt.",
                    en: "Choose whether this section applies to all Austria or one state."
                )
            )

            Picker(GuideAuthoringPresentation.regionTitle, selection: $viewModel.regionScope) {
                Text(GuideAuthoringPresentation.allAustria).tag(RegionScope.austria)
                Text(GuideAuthoringPresentation.oneFederalState).tag(RegionScope.federalState)
            }
            .pickerStyle(.segmented)

            if viewModel.regionScope == .federalState {
                AppEditorField(title: GuideAuthoringPresentation.federalStateLabel) {
                    Picker(GuideAuthoringPresentation.federalStateLabel, selection: $viewModel.federalState) {
                        Text(GuideAuthoringPresentation.selectFederalState).tag(AustrianFederalState?.none)
                        ForEach(federalStateOptions, id: \.self) { federalState in
                            Text(AppStrings.FederalStates.title(for: federalState))
                                .tag(Optional(federalState))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var federalStateOptions: [AustrianFederalState] {
        [
            .burgenland,
            .kaernten,
            .niederoesterreich,
            .oberoesterreich,
            .salzburg,
            .steiermark,
            .tirol,
            .vorarlberg,
            .wien
        ]
    }

    private var screenTitle: String {
        switch viewModel.mode {
        case .edit:
            return GuideAuthoringPresentation.editSectionScreenTitle
        default:
            return GuideAuthoringPresentation.createSectionScreenTitle
        }
    }

    private var headerSubtitle: String {
        switch viewModel.mode {
        case .createRoot:
            return GuideAuthoringPresentation.localized(
                uk: "Новий розділ буде створено в категорії: \(viewModel.mode.parentPathDescription)",
                de: "Der neue Abschnitt wird in dieser Kategorie erstellt: \(viewModel.mode.parentPathDescription)",
                en: "The new section will be created in: \(viewModel.mode.parentPathDescription)"
            )
        case .createChild:
            return GuideAuthoringPresentation.localized(
                uk: "Новий розділ буде розміщено тут: \(viewModel.mode.parentPathDescription)",
                de: "Der neue Abschnitt wird hier platziert: \(viewModel.mode.parentPathDescription)",
                en: "The new section will be placed here: \(viewModel.mode.parentPathDescription)"
            )
        case .edit:
            return GuideAuthoringPresentation.localized(
                uk: "Оновіть назву, короткий опис і регіональність цього розділу.",
                de: "Passen Sie Titel, Kurzbeschreibung und Region dieses Abschnitts an.",
                en: "Update the title, short description, and region for this section."
            )
        }
    }

    private var statusMessage: String? {
        switch viewModel.saveState {
        case .idle:
            nil
        case .saving:
            GuideAuthoringPresentation.savingLabel
        case .saved:
            GuideAuthoringPresentation.localized(uk: "Розділ збережено.", de: "Abschnitt gespeichert.", en: "Section saved.")
        case .failed(let message):
            message
        }
    }

    private var statusTint: Color {
        switch viewModel.saveState {
        case .failed:
            AppTheme.accentDestructive
        default:
            AppTheme.textSecondary
        }
    }

    private func contextRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTheme.metadataFont)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(AppTheme.secondaryBodyFont)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        GuideSectionEditorView(
            viewModel: GuideSectionEditorViewModel(
                mode: .createRoot(category: .firstSteps),
                repository: FirestoreGuideWriteRepository(),
                currentUserID: "preview-user"
            )
        )
    }
}
