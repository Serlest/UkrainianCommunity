import PhotosUI
import SwiftUI
import UIKit

struct NewsEditorView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @StateObject var viewModel: NewsEditorViewModel
    @StateObject var organizerOrganizationsViewModel: AuthoringOrganizationsViewModel
    @State var selectedPhoto: PhotosPickerItem?
    @State var selectedPreviewImage: UIImage?
    @State var cropSourceImage: UIImage?
    @State var isShowingImageCrop = false
    @State var ignoresNextPhotoClear = false
    @State var imageProcessingTask: Task<Void, Never>?
    @State var imageProcessingToken = UUID()
    @State var isShowingOrganizerPicker = false
    @State var isShowingDraftRecoveryDialog = false
    @State var isShowingDraftCloseConfirmation = false
    @State var currentStep = NewsEditorStep.basics
    @FocusState var focusedField: NewsEditorFocusField?
    let onPublished: @MainActor () async -> Void
    let sourceAttentionMessages: [String]

    let titleLimit = NewsEditorViewModel.titleLimit
    let summaryLimit = NewsEditorViewModel.summaryLimit
    let bodyLimit = NewsEditorViewModel.bodyLimit
    let editorSectionSpacing: CGFloat = 8
    let editorCardSpacing: CGFloat = 8
    let editorCardPadding: CGFloat = 10
    let editorCardRadius: CGFloat = 16
    let compactInputHeight: CGFloat = 40
    let summaryInputHeight: CGFloat = 78
    let summaryTextHeight: CGFloat = 60
    let bodyInputHeight: CGFloat = 190
    let detailRowHeight: CGFloat = 52
    let detailIconSize: CGFloat = 16
    let uploadMinHeight: CGFloat = 124
    let organizerLogoSize: CGFloat = 48

    init(
        repository: NewsRepository,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(repository: repository, mode: .create()))
        _organizerOrganizationsViewModel = StateObject(wrappedValue: AuthoringOrganizationsViewModel(repository: organizationRepository))
        self.onPublished = onPublished
        self.sourceAttentionMessages = []
    }

    init(
        repository: NewsRepository,
        sourceDraft: OwnerContentDraft,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(
            repository: repository,
            mode: .create(),
            sourceDraft: sourceDraft
        ))
        _organizerOrganizationsViewModel = StateObject(wrappedValue: AuthoringOrganizationsViewModel(repository: organizationRepository))
        self.onPublished = onPublished
        self.sourceAttentionMessages = sourceDraft.attentionMessages
    }

    init(
        repository: NewsRepository,
        organizationId: String,
        organizationName: String,
        organizationImageURL: String?,
        organizationFederalState: AustrianFederalState? = nil,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(
            repository: repository,
            mode: .create(context: .init(
                organizationId: organizationId,
                organizationName: organizationName,
                organizationImageURL: organizationImageURL,
                organizationFederalState: organizationFederalState
            ))
        ))
        _organizerOrganizationsViewModel = StateObject(wrappedValue: AuthoringOrganizationsViewModel(repository: organizationRepository))
        self.onPublished = onPublished
        self.sourceAttentionMessages = []
    }

    init(
        repository: NewsRepository,
        news: NewsPost,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(repository: repository, mode: .edit(existing: news)))
        _organizerOrganizationsViewModel = StateObject(wrappedValue: AuthoringOrganizationsViewModel(repository: organizationRepository))
        self.onPublished = onPublished
        self.sourceAttentionMessages = []
    }

    var body: some View {
        EditorScreenShell(
            title: viewModel.isEditing ? AppStrings.NewsEditor.editTitle : AppStrings.NewsEditor.addTitle,
            subtitle: AppStrings.NewsEditor.editorSubtitle,
            closeStyle: .cancel,
            closeAction: requestClose
        ) {
            statusContent

            if !sourceAttentionMessages.isEmpty {
                ContentPlanningAttentionCard(messages: sourceAttentionMessages)
            }

            if showsNoOrganizerAccessState {
                noOrganizerAccessCard
            } else {
                editorProgress
                editorStepContent
                    // Every step contains similarly-shaped cards. Giving the
                    // subtree an explicit identity prevents SwiftUI from
                    // reusing stale text fields/layers when the preview opens.
                    .id(currentStep)
                editorNavigation
            }
        }
        .tint(AppTheme.accentPrimary)
        .accessibilityIdentifier("editor.news")
        .sheet(isPresented: $isShowingOrganizerPicker) {
            NewsOrganizerPickerSheet(
                organizations: availableOrganizerOrganizations,
                selectedOrganizationID: viewModel.selectedOrganizationId
            ) { organization in
                viewModel.selectOrganizer(organization)
                isShowingOrganizerPicker = false
            }
        }
        .sheet(isPresented: $isShowingImageCrop, onDismiss: resetCropSelection) {
            if let cropSourceImage {
                ImageCropView(
                    sourceImage: cropSourceImage,
                    profile: .hero16x9,
                    title: AppStrings.Images.Crop.title,
                    instructions: AppStrings.NewsEditor.coverUploadHelper,
                    onCancel: {},
                    onApply: applyCroppedImage(_:)
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
                currentStep = .basics
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
            Text(AppStrings.DraftRecovery.recoveryMessage)
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
            Text(AppStrings.DraftRecovery.closeMessage)
        }
        .interactiveDismissDisabled(viewModel.shouldConfirmDraftBeforeDismiss)
        .onChange(of: selectedPhoto) { _, newItem in
            if newItem == nil, ignoresNextPhotoClear {
                ignoresNextPhotoClear = false
                return
            }
            imageProcessingTask?.cancel()
            let token = UUID()
            imageProcessingToken = token
            imageProcessingTask = Task {
                await loadSelectedPhoto(item: newItem, token: token)
            }
        }
        .task(id: authState.user?.id) {
            viewModel.setAuthState(authState)
            guard !viewModel.isEditing else { return }
            await organizerOrganizationsViewModel.load(for: authState.user, force: false)
            applyDefaultOrganizerIfNeeded()
            await loadRecoverableDraftIfNeeded()
        }
        .onChange(of: organizerOrganizationsViewModel.contentVersion) { _, _ in
            applyDefaultOrganizerIfNeeded()
        }
        .onDisappear {
            imageProcessingTask?.cancel()
        }
    }

    var availableOrganizerOrganizations: [Organization] {
        guard let user = authState.user else { return [] }

        let organizations = organizerOrganizationsViewModel.organizations
            .filter { $0.id != Organization.systemOrganizationID }
            .sorted { lhs, rhs in
                let result = LocalizationStore.compareForSorting(lhs.name, rhs.name)
                return result == .orderedSame ? lhs.id < rhs.id : result == .orderedAscending
            }

        switch user.globalRole.authorizationRole {
        case .owner:
            return organizations
        case .admin, .user, .topAdmin:
            return PermissionService.manageableOrganizations(from: organizations, user: user)
        }
    }

    var canSelectOrganizer: Bool {
        !viewModel.isEditing && availableOrganizerOrganizations.count > 1
    }

    var hasAuthorizedOrganizerSelection: Bool {
        guard !viewModel.isEditing else { return true }
        guard let selectedID = viewModel.selectedOrganizationId else { return false }
        return availableOrganizerOrganizations.contains(where: { $0.id == selectedID })
    }

    var showsNoOrganizerAccessState: Bool {
        !viewModel.isEditing
            && !organizerOrganizationsViewModel.isLoading
            && availableOrganizerOrganizations.isEmpty
    }

    func applyDefaultOrganizerIfNeeded() {
        guard !viewModel.isEditing else { return }
        guard viewModel.selectedOrganizationId == nil else { return }
        guard availableOrganizerOrganizations.count == 1, let organization = availableOrganizerOrganizations.first else { return }
        viewModel.selectOrganizer(organization)
    }

    func loadRecoverableDraftIfNeeded() async {
        await viewModel.loadRecoverableDraftIfNeeded()
        isShowingDraftRecoveryDialog = viewModel.hasPendingRecoveryDraft
    }

    func settingsRows<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.82))
        )
    }

    func detailRow(
        systemImage: String,
        title: String,
        value: String,
        isPlaceholder: Bool = false,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            rowIcon(systemImage)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: detailRowHeight)
    }

    func rowIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(width: detailIconSize, height: detailIconSize)
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

    func counterText(_ count: Int, limit: Int) -> String {
        "\(count)/\(limit)"
    }
}

enum NewsEditorStep: Int, CaseIterable, Identifiable {
    case basics
    case content
    case preview

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .basics: AppStrings.NewsEditor.editorStepBasics
        case .content: AppStrings.NewsEditor.editorStepContent
        case .preview: AppStrings.NewsEditor.editorStepPreview
        }
    }

    var next: Self { Self(rawValue: min(rawValue + 1, Self.preview.rawValue)) ?? .preview }
    var previous: Self { Self(rawValue: max(rawValue - 1, Self.basics.rawValue)) ?? .basics }
}

enum NewsEditorFocusField: Hashable {
    case title
    case summary
    case body
    case source
    case tags
}


#Preview {
    NavigationStack {
        NewsEditorView(repository: MockNewsRepository(), onPublished: {})
    }
    .environmentObject(AuthState())
}

extension View {
    func newsEditorCompactInputStyle(minHeight: CGFloat) -> some View {
        self.appEditorInputStyle(minHeight: minHeight)
    }
}
