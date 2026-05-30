import PhotosUI
import SwiftUI
import UIKit

struct NewsEditorView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @StateObject var viewModel: NewsEditorViewModel
    @StateObject var organizerOrganizationsViewModel: OrganizationsViewModel
    @State var selectedPhoto: PhotosPickerItem?
    @State var selectedPreviewImage: UIImage?
    @State var cropSourceImage: UIImage?
    @State var isShowingImageCrop = false
    @State var ignoresNextPhotoClear = false
    @State var imageProcessingTask: Task<Void, Never>?
    @State var imageProcessingToken = UUID()
    @State var isShowingOrganizerPicker = false
    let onPublished: @MainActor () async -> Void

    let titleLimit = 120
    let summaryLimit = 200
    let bodyLimit = 10000
    let editorSectionSpacing: CGFloat = 8
    let editorCardSpacing: CGFloat = 8
    let editorCardPadding: CGFloat = 10
    let editorCardRadius: CGFloat = 16
    let compactInputHeight: CGFloat = 40
    let summaryInputHeight: CGFloat = 78
    let summaryTextHeight: CGFloat = 60
    let bodyInputHeight: CGFloat = 70
    let detailRowHeight: CGFloat = 52
    let detailIconSize: CGFloat = 16
    let uploadMinHeight: CGFloat = 124
    let headerLogoSize = CGSize(width: 118, height: 42)
    let organizerLogoSize: CGFloat = 48

    init(
        repository: NewsRepository,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(repository: repository, mode: .create()))
        _organizerOrganizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: organizationRepository))
        self.onPublished = onPublished
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
        _organizerOrganizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: organizationRepository))
        self.onPublished = onPublished
    }

    init(
        repository: NewsRepository,
        news: NewsPost,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: NewsEditorViewModel(repository: repository, mode: .edit(existing: news)))
        _organizerOrganizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: organizationRepository))
        self.onPublished = onPublished
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: editorSectionSpacing) {
                editorHeader
                    .padding(.top, AppTheme.dashboardSpacing)

                editorTitleBlock

                statusContent

                if showsNoOrganizerAccessState {
                    noOrganizerAccessCard
                } else {
                    mainInformationCard

                    coverImageCard

                    if !viewModel.isEditing {
                        organizerCard
                    }

                    bodyContentCard

                    sourceCard

                    tagsCard

                    if viewModel.showsRegionPicker {
                        settingsCard
                    }

                    bottomPublishButton
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
        }
        .background(AppBackgroundView())
        .tint(AppTheme.accentPrimary)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
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
        .onChange(of: selectedPhoto) { _, newItem in
            if newItem == nil, ignoresNextPhotoClear {
                ignoresNextPhotoClear = false
                return
            }
            dismissKeyboard()
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
            await organizerOrganizationsViewModel.loadIfNeeded()
            applyDefaultOrganizerIfNeeded()
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
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        switch user.globalRole.authorizationRole {
        case .owner:
            return organizations
        case .user, .topAdmin, .appModerator:
            return PermissionService.manageableOrganizations(from: organizations, user: user)
        }
    }

    var canSelectOrganizer: Bool {
        !viewModel.isEditing && availableOrganizerOrganizations.count > 1
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
                .foregroundStyle(isPlaceholder ? AppTheme.textSecondary.opacity(0.68) : AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: detailRowHeight)
    }

    func rowIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.92))
            .frame(width: detailIconSize, height: detailIconSize)
    }

    func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(editorCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassSurface(for: colorScheme),
            in: RoundedRectangle(cornerRadius: editorCardRadius, style: .continuous)
        )
        .background {
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: editorCardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: editorCardRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.55))
        )
        .shadow(color: AppTheme.glassShadow(for: colorScheme).opacity(0.45), radius: 10, y: 5)
    }

    func editorField<Content: View>(title: String, counterText: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                Text(counterText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .monospacedDigit()
            }

            content()
        }
    }

    func editorSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func counterText(_ count: Int, limit: Int) -> String {
        "\(count)/\(limit)"
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}


#Preview {
    NavigationStack {
        NewsEditorView(repository: MockNewsRepository(), onPublished: {})
    }
    .environmentObject(AuthState())
}

extension View {
    func newsEditorCompactInputStyle(minHeight: CGFloat) -> some View {
        self
            .font(.subheadline)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
            .frame(minHeight: minHeight, alignment: .leading)
            .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle)
            )
    }
}

extension AustrianFederalState {
    var newsEditorDisplayName: String {
        switch self {
        case .burgenland:
            "Burgenland"
        case .kaernten:
            "Kärnten"
        case .niederoesterreich:
            "Niederösterreich"
        case .oberoesterreich:
            "Oberösterreich"
        case .salzburg:
            "Salzburg"
        case .steiermark:
            "Steiermark"
        case .tirol:
            "Tirol"
        case .vorarlberg:
            "Vorarlberg"
        case .wien:
            "Wien"
        }
    }
}
