import PhotosUI
import SwiftUI
import UIKit

struct OrganizationEditorView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    @StateObject var viewModel: OrganizationEditorViewModel
    @State var selectedPhoto: PhotosPickerItem?
    @State var cropSourceLogoImage: UIImage?
    @State var isShowingLogoCrop = false
    @State var ignoresNextPhotoClear = false
    @State var isShowingDraftRecoveryDialog = false
    @State var isShowingDraftCloseConfirmation = false
    @State private var currentStep = OrganizationEditorStep.basics
    let onSaved: @MainActor () async -> Void
    let editorSectionSpacing: CGFloat = 8
    let editorCardSpacing: CGFloat = 8
    let editorCardPadding: CGFloat = 10
    let editorCardRadius: CGFloat = 16
    let compactInputHeight: CGFloat = 40
    let summaryInputHeight: CGFloat = 78
    let summaryTextHeight: CGFloat = 60
    let uploadMinHeight: CGFloat = 124

    init(
        organizationsViewModel: OrganizationsViewModel,
        onSaved: @escaping @MainActor () async -> Void = {}
    ) {
        self.organizationsViewModel = organizationsViewModel
        _viewModel = StateObject(wrappedValue: OrganizationEditorViewModel(mode: .create))
        self.onSaved = onSaved
    }

    init(
        organizationsViewModel: OrganizationsViewModel,
        organization: Organization,
        onSaved: @escaping @MainActor () async -> Void = {}
    ) {
        self.organizationsViewModel = organizationsViewModel
        _viewModel = StateObject(wrappedValue: OrganizationEditorViewModel(mode: .edit(existing: organization)))
        self.onSaved = onSaved
    }

    var body: some View {
        EditorScreenShell(
            title: viewModel.navigationTitle,
            subtitle: AppStrings.Organizations.editorSubtitle,
            closeStyle: .cancel,
            closeAction: requestClose
        ) {
            statusContent
            editorProgress
            editorStepContent
            editorNavigation
        }
        .tint(AppTheme.accentPrimary)
        .sheet(isPresented: $isShowingLogoCrop, onDismiss: resetLogoCropSelection) {
            if let cropSourceLogoImage {
                ImageCropView(
                    sourceImage: cropSourceLogoImage,
                    profile: .squareLogo,
                    title: AppStrings.Images.Crop.title,
                    instructions: AppStrings.Organizations.logoUploadHelper,
                    onCancel: {},
                    onApply: applyCroppedLogoImage(_:)
                )
            }
        }
        .confirmationDialog(
            AppStrings.DraftRecovery.recoveryTitle,
            isPresented: $isShowingDraftRecoveryDialog,
            titleVisibility: .visible
        ) {
            Button(AppStrings.DraftRecovery.continueDraft) {
                viewModel.continueRecoveredDraft()
            }
            Button(AppStrings.DraftRecovery.createNew) {
                Task {
                    await viewModel.createNewInsteadOfRecoveredDraft()
                }
            }
            Button(AppStrings.DraftRecovery.deleteDraft, role: .destructive) {
                Task {
                    await viewModel.deleteRecoveredDraft()
                }
            }
        } message: {
            Text(AppStrings.DraftRecovery.organizationRecoveryMessage)
        }
        .confirmationDialog(
            AppStrings.DraftRecovery.closeTitle,
            isPresented: $isShowingDraftCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.DraftRecovery.saveDraftAndClose) {
                Task {
                    await viewModel.saveDraftBeforeClosing()
                    dismiss()
                }
            }
            Button(AppStrings.DraftRecovery.discardDraft, role: .destructive) {
                Task {
                    await viewModel.discardCreateDraft()
                    dismiss()
                }
            }
            Button(AppStrings.DraftRecovery.continueEditing, role: .cancel) {}
        } message: {
            Text(AppStrings.DraftRecovery.organizationCloseMessage)
        }
        .interactiveDismissDisabled(viewModel.shouldConfirmDraftBeforeDismiss)
        .onChange(of: selectedPhoto) { _, newItem in
            if newItem == nil, ignoresNextPhotoClear {
                ignoresNextPhotoClear = false
                return
            }
            Task {
                await loadSelectedPhoto(item: newItem)
            }
        }
        .task {
            await loadRecoverableDraftIfNeeded()
        }
    }

    private var editorProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(OrganizationEditorStep.allCases) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? AppTheme.primaryBlue : AppTheme.borderSubtle)
                        .frame(height: 4)
                }
            }

            Text(currentStep.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var editorStepContent: some View {
        switch currentStep {
        case .basics:
            mainInfoCard
            possibleDuplicateCard
            aboutCard
        case .location:
            locationCard
            contactCard
        case .features:
            directoryFeaturesCard
            directoryActionsCard
        case .preview:
            organizationPreviewCard
            moderationNoticeCard
        }
    }

    @ViewBuilder
    private var possibleDuplicateCard: some View {
        if !possibleDuplicateOrganizations.isEmpty {
            editorCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(AppStrings.Organizations.possibleDuplicateTitle, systemImage: "exclamationmark.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.Organizations.possibleDuplicateMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)

                    ForEach(possibleDuplicateOrganizations.prefix(3)) { organization in
                        Label(organization.name, systemImage: "building.2")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var possibleDuplicateOrganizations: [Organization] {
        let candidate = normalizedOrganizationName(viewModel.name)
        guard candidate.count >= 4 else { return [] }

        return organizationsViewModel.organizations.filter { organization in
            guard !viewModel.isEditing || organization.id != viewModel.editingOrganizationID else { return false }
            let existing = normalizedOrganizationName(organization.name)
            return existing == candidate || existing.contains(candidate) || candidate.contains(existing)
        }
    }

    private func normalizedOrganizationName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: LocalizationStore.locale)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    private var editorNavigation: some View {
        HStack(spacing: AppTheme.dashboardSpacing) {
            if currentStep != .basics {
                Button {
                    currentStep = currentStep.previous
                } label: {
                    Label(AppStrings.Organizations.editorBack, systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if currentStep == .preview {
                bottomSubmitButton
            } else {
                PrimaryActionButton(
                    title: AppStrings.Organizations.editorNext,
                    isEnabled: canAdvanceCurrentStep,
                    isLoading: false
                ) {
                    currentStep = currentStep.next
                }
            }
        }
    }

    private var canAdvanceCurrentStep: Bool {
        switch currentStep {
        case .basics: viewModel.canAdvanceBasics
        case .location: viewModel.canAdvanceLocation
        case .features, .preview: true
        }
    }

    private var organizationPreviewCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                HStack(alignment: .top, spacing: AppTheme.dashboardSpacing) {
                    logoPickerContent
                        .frame(width: 72, height: 72)
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(viewModel.name)
                            .font(AppTheme.cardTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(viewModel.shortDescription)
                            .font(AppTheme.cardSubtitleFont)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                AppHorizontalChipRow {
                    AppInfoChip(
                        title: viewModel.profileKind.title,
                        systemImage: viewModel.profileKind.systemImage,
                        tint: AppTheme.accentPrimaryForeground,
                        fill: AppTheme.badgeBlueFill
                    )
                    if let category = OrganizationEditorCategory(rawValue: viewModel.organizationType) {
                        AppInfoChip(
                            title: category.title,
                            systemImage: category.systemImage,
                            tint: AppTheme.textSecondary,
                            fill: AppTheme.surfaceControl
                        )
                    }
                }

                Label(
                    [viewModel.city, viewModel.selectedFederalState?.displayName]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: ", "),
                    systemImage: "mappin.and.ellipse"
                )
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    func loadRecoverableDraftIfNeeded() async {
        await viewModel.loadRecoverableDraftIfNeeded()
        isShowingDraftRecoveryDialog = viewModel.hasPendingRecoveryDraft
    }

    var moderationNoticeCard: some View {
        editorCard {
            HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                Image(systemName: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                Text(AppStrings.Organizations.moderationNotice)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3)
            }
        }
    }

    func iconTextField(
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        isDisabled: Bool = false
    ) -> some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            TextField(placeholder, text: text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .disabled(isDisabled)
        }
        .appEditorInputStyle(minHeight: compactInputHeight)
        .opacity(isDisabled ? 0.58 : 1)
        .accessibilityHint(isDisabled ? AppStrings.Action.comingSoon : "")
    }

    func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
    }

    func editorField<Content: View>(title: String, counterText: String, @ViewBuilder content: () -> Content) -> some View {
        AppEditorField(title: title, counterText: counterText) {
            content()
        }
    }

    func editorSectionTitle(_ title: String) -> some View {
        AppEditorSectionTitle(title: title)
    }
}

private enum OrganizationEditorStep: Int, CaseIterable, Identifiable {
    case basics
    case location
    case features
    case preview

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .basics: AppStrings.Organizations.editorStepBasics
        case .location: AppStrings.Organizations.editorStepLocation
        case .features: AppStrings.Organizations.editorStepFeatures
        case .preview: AppStrings.Organizations.editorStepPreview
        }
    }

    var next: Self {
        Self(rawValue: min(rawValue + 1, Self.preview.rawValue)) ?? .preview
    }

    var previous: Self {
        Self(rawValue: max(rawValue - 1, Self.basics.rawValue)) ?? .basics
    }
}

extension View {
    func organizationEditorCompactInputStyle(minHeight: CGFloat) -> some View {
        self.appEditorInputStyle(minHeight: minHeight)
    }
}
