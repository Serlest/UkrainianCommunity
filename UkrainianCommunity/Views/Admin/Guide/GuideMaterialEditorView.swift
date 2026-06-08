import SwiftUI

struct GuideMaterialEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GuideMaterialEditorViewModel
    let onSaved: @MainActor (GuideMaterial) async -> Void

    init(
        viewModel: GuideMaterialEditorViewModel,
        onSaved: @escaping @MainActor (GuideMaterial) async -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSaved = onSaved
    }

    var body: some View {
        EditorScreenShell(
            title: screenTitle,
            subtitle: headerSubtitle,
            closeStyle: .cancel
        ) {
            statusCard
            GuideMaterialEditorArticleSection(
                nodePathDescription: viewModel.nodePathDescription,
                title: $viewModel.title,
                summary: $viewModel.summary,
                articleBody: $viewModel.body
            )
            GuideMaterialEditorKnowledgeSections(
                steps: $viewModel.steps,
                checklistItems: $viewModel.checklistItems,
                contacts: $viewModel.contacts,
                importantInformation: $viewModel.importantInformation
            )
            GuideMaterialEditorSourcesSection(sourceLinks: $viewModel.sourceLinks)
            GuideMaterialEditorSettingsSection(
                reviewInterval: $viewModel.reviewInterval,
                regionScope: $viewModel.regionScope,
                federalState: $viewModel.federalState,
                reviewIntervalTitle: reviewIntervalTitle
            )
            GuideMaterialEditorFooter(
                isSaving: viewModel.isSaving,
                saveButtonTitle: viewModel.saveButtonTitle,
                onSave: handleSave
            )
        }
        .onChange(of: viewModel.title) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.summary) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.body) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.steps) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.checklistItems) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.contacts) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.importantInformation) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.sourceLinks) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.reviewInterval) { _, newValue in
            if viewModel.nextReviewAt <= viewModel.lastReviewedAt {
                viewModel.nextReviewAt = Calendar.current.date(byAdding: .month, value: newValue.months, to: viewModel.lastReviewedAt) ?? viewModel.lastReviewedAt
            }
            viewModel.clearTransientState()
        }
        .onChange(of: viewModel.lastReviewedAt) { _, newValue in
            if viewModel.nextReviewAt <= newValue {
                viewModel.nextReviewAt = Calendar.current.date(byAdding: .month, value: viewModel.reviewInterval.months, to: newValue) ?? newValue
            }
            viewModel.clearTransientState()
        }
        .onChange(of: viewModel.nextReviewAt) { _, _ in viewModel.clearTransientState() }
        .onChange(of: viewModel.regionScope) { _, newValue in
            if newValue != .federalState {
                viewModel.federalState = nil
            }
            viewModel.clearTransientState()
        }
        .onChange(of: viewModel.federalState) { _, _ in viewModel.clearTransientState() }
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

    private var screenTitle: String {
        switch viewModel.mode {
        case .create:
            return GuideAuthoringPresentation.createMaterialScreenTitle
        case .edit:
            return GuideAuthoringPresentation.editMaterialScreenTitle
        }
    }

    private var headerSubtitle: String {
        switch viewModel.mode {
        case .create:
            return GuideAuthoringPresentation.materialPlacementDescription(viewModel.nodePathDescription)
        case .edit:
            return GuideAuthoringPresentation.localized(
                uk: "Кінцева сторінка, яку читатимуть користувачі.",
                de: "Dies ist die endgültige Seite, die Nutzer lesen werden.",
                en: "This is the final page readers will see."
            )
        }
    }

    private func reviewIntervalTitle(_ interval: ReviewInterval) -> String {
        switch interval {
        case .critical:
            return GuideAuthoringPresentation.localized(uk: "3 місяці", de: "3 Monate", en: "3 months")
        case .normal:
            return GuideAuthoringPresentation.localized(uk: "6 місяців", de: "6 Monate", en: "6 months")
        case .stable:
            return GuideAuthoringPresentation.localized(uk: "12 місяців", de: "12 Monate", en: "12 months")
        }
    }

    private var statusMessage: String? {
        switch viewModel.saveState {
        case .idle:
            return nil
        case .saving:
            return GuideAuthoringPresentation.savingLabel
        case .saved:
            return GuideAuthoringPresentation.localized(uk: "Матеріал збережено.", de: "Artikel gespeichert.", en: "Material saved.")
        case .failed(let message):
            return message
        }
    }

    private var statusTint: Color {
        switch viewModel.saveState {
        case .failed:
            return AppTheme.accentDestructive
        default:
            return AppTheme.textSecondary
        }
    }

    private func handleSave() {
        Task {
            if let material = await viewModel.save() {
                await onSaved(material)
                dismiss()
            }
        }
    }
}

#Preview {
    let node = GuideNode(
        id: "node-preview",
        parentID: FirestoreGuideWriteRepository.rootParentID,
        category: .firstSteps,
        title: "Arrival",
        summary: "Root node",
        createdAt: Date(),
        updatedAt: Date()
    )

    return NavigationStack {
        GuideMaterialEditorView(
            viewModel: GuideMaterialEditorViewModel(
                mode: .create(
                    node: node,
                    nodePath: GuideTreePath(components: [
                        .init(id: node.category.rawValue, title: GuideCategoryPresentation.publicTitle(for: node.category)),
                        .init(id: node.id, title: node.title)
                    ])
                ),
                repository: FirestoreGuideWriteRepository(),
                currentUserID: "preview-user"
            )
        )
    }
}
