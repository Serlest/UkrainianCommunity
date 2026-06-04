import Combine
import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct EventEditorView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @EnvironmentObject var authState: AuthState
    @StateObject var viewModel: EventEditorViewModel
    @StateObject var organizerOrganizationsViewModel: OrganizationsViewModel
    @StateObject var locationSearch = EventLocationSearchViewModel()
    @State var selectedPhoto: PhotosPickerItem?
    @State var selectedPreviewImage: UIImage?
    @State var cropSourceImage: UIImage?
    @State var isShowingImageCrop = false
    @State var ignoresNextPhotoClear = false
    @State var imageProcessingTask: Task<Void, Never>?
    @State var imageProcessingToken = UUID()
    @State var isShowingMapPicker = false
    @State var isShowingOrganizerPicker = false
    @State var isApplyingLocationSelection = false
    @State var activeDatePicker: EventEditorDatePicker?
    @State var isShowingDraftRecoveryDialog = false
    @State var isShowingDraftCloseConfirmation = false

    let onPublished: @MainActor () async -> Void
    let editorSectionSpacing: CGFloat = 8
    let editorCardSpacing: CGFloat = 8
    let editorCardPadding: CGFloat = 10
    let editorCardRadius: CGFloat = 16
    let compactInputHeight: CGFloat = 40
    let summaryInputHeight: CGFloat = 78
    let detailsInputHeight: CGFloat = 104
    let locationNoteInputHeight: CGFloat = 70
    let uploadMinHeight: CGFloat = 124
    let headerLogoSize = CGSize(width: 118, height: 42)
    let organizerLogoSize: CGFloat = 48

    init(
        repository: EventRepository,
        organizationId: String,
        organizationName: String,
        organizationImageURL: String?,
        organizationFederalState: AustrianFederalState? = nil,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: EventEditorViewModel(
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
        repository: EventRepository,
        event: Event,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onPublished: @escaping @MainActor () async -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: EventEditorViewModel(repository: repository, mode: .edit(existing: event)))
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
                mainCard
                imageCard
                dateTimeCard
                locationCard
                organizerCard
                organizerContactCard
                categoryCard
                tagsCard
                additionalSettingsCard
                publishNoticeCard
                bottomSubmitButton
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
        }
        .background(AppBackgroundView())
        .tint(AppTheme.accentPrimary)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnBackgroundTap()
        .sheet(isPresented: $isShowingMapPicker) {
            EventMapPickerView(
                initialCoordinate: viewModel.selectedCoordinate,
                initialQuery: viewModel.locationSearchQuery
            ) { selection in
                applyLocation(selection)
            }
        }
        .sheet(isPresented: $isShowingOrganizerPicker) {
            OrganizerPickerSheet(
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
                    instructions: AppStrings.Events.coverUploadHelper,
                    onCancel: {},
                    onApply: applyCroppedImage(_:)
                )
            }
        }
        .sheet(item: $activeDatePicker) { picker in
            EventDatePickerSheet(
                title: picker.title,
                selection: dateBinding(for: picker),
                displayedComponents: picker.displayedComponents
            )
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
            Text(AppStrings.DraftRecovery.eventRecoveryMessage)
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
            Text(AppStrings.DraftRecovery.eventCloseMessage)
        }
        .interactiveDismissDisabled(viewModel.shouldConfirmDraftBeforeDismiss)
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
        .onChange(of: viewModel.venue) { _, newValue in
            guard !isApplyingLocationSelection else { return }
            viewModel.clearResolvedCoordinates()
            locationSearch.updateQuery(newValue)
        }
        .onChange(of: viewModel.address) { _, _ in
            guard !isApplyingLocationSelection else { return }
            viewModel.clearResolvedCoordinates()
        }
        .onChange(of: viewModel.city) { _, _ in
            guard !isApplyingLocationSelection else { return }
            viewModel.clearResolvedCoordinates()
        }
        .onDisappear {
            imageProcessingTask?.cancel()
        }
        .task {
            await organizerOrganizationsViewModel.loadIfNeeded()
            applyDefaultOrganizerIfNeeded()
            await loadRecoverableDraftIfNeeded()
        }
        .onChange(of: organizerOrganizationsViewModel.contentVersion) { _, _ in
            applyDefaultOrganizerIfNeeded()
            Task {
                await loadRecoverableDraftIfNeeded()
            }
        }
        .onChange(of: authState.user?.id) { _, _ in
            applyDefaultOrganizerIfNeeded()
            Task {
                await loadRecoverableDraftIfNeeded()
            }
        }
    }

    var availableOrganizerOrganizations: [Organization] {
        guard let user = authState.user else { return [] }

        let organizations = organizerOrganizationsViewModel.organizations
            .filter { $0.id != Organization.systemOrganizationID }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        return PermissionService.manageableOrganizations(from: organizations, user: user)
    }

    var canSelectOrganizer: Bool {
        !viewModel.isEditing && availableOrganizerOrganizations.count > 1
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

    var organizerCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                editorSectionTitle(AppStrings.Events.editorPublisherSectionTitle)

                Button {
                    guard canSelectOrganizer else { return }
                    isShowingOrganizerPicker = true
                } label: {
                    HStack(spacing: AppTheme.dashboardSpacing) {
                        AppFeedThumbnail(
                            imageURL: viewModel.organizerImageURL,
                            fallbackSystemImage: "building.2",
                            tint: AppTheme.accentPrimary,
                            fill: AppTheme.accentPrimarySoft,
                            size: organizerLogoSize,
                            cornerRadius: AppTheme.feedThumbnailRadius,
                            source: "EventEditorOrganizer"
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.publishingOrganizationName ?? organizerPlaceholderTitle)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(2)

                            AppInfoChip(
                                title: organizerStatusTitle,
                                systemImage: "building.2",
                                tint: AppTheme.accentPrimary,
                                fill: AppTheme.accentPrimarySoft,
                                size: .small
                            )
                        }

                        Spacer(minLength: AppTheme.eventsMetadataSpacing)

                        organizerAccessory
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSelectOrganizer)
            }
        }
    }

    var organizerPlaceholderTitle: String {
        if organizerOrganizationsViewModel.isLoading {
            return AppStrings.Profile.loadingUserProfile
        }

        return AppStrings.Home.brandTitle
    }

    var organizerStatusTitle: String {
        if viewModel.publishingOrganizationName != nil {
            return AppStrings.Organizations.detailBadge
        }

        if availableOrganizerOrganizations.isEmpty {
            return AppStrings.Common.notAvailable
        }

        return AppStrings.Tabs.events
    }

    @ViewBuilder
    var organizerAccessory: some View {
        if canSelectOrganizer {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 32, height: 32)
                .background(AppTheme.glassControlSurface(for: colorScheme), in: Circle())
        } else if organizerOrganizationsViewModel.isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.accentPrimary)
                .frame(width: 32, height: 32)
                .background(AppTheme.glassControlSurface(for: colorScheme), in: Circle())
        } else {
            Label(AppStrings.Common.notAvailable, systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                .labelStyle(.iconOnly)
                .frame(width: 32, height: 32)
                .background(AppTheme.glassControlSurface(for: colorScheme), in: Circle())
        }
    }

    func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
    }

    func editorStatusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        editorCard {
            content()
        }
    }

    func editorField<Content: View>(title: String, counterText: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        AppEditorField(title: title, counterText: counterText) {
            content()
        }
    }

    func editorSectionTitle(_ title: String) -> some View {
        AppEditorSectionTitle(title: title)
    }

    var editorDivider: some View {
        Rectangle()
            .fill(AppTheme.borderSubtle)
            .frame(height: 1)
            .padding(.leading, AppTheme.metadataIconSize + AppTheme.dashboardSpacing)
    }

    func multilineInput(placeholder: String, text: Binding<String>, minHeight: CGFloat, counterText: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                    .lineSpacing(2)
                    .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                    .padding(.vertical, AppTheme.eventsMetadataSpacing)
            }

            TextEditor(text: text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(minHeight: minHeight, alignment: .topLeading)

            Text(counterText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, AppTheme.eventsControlGroupSpacing)
                .padding(.bottom, AppTheme.eventsMetadataSpacing)
        }
        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.82))
        )
    }

    func disabledWideButton(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.searchControlHeight)
            .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
            )
            .opacity(0.66)
            .accessibilityHint(AppStrings.Action.comingSoon)
    }


    func settingsRow(systemImage: String, title: String, value: String, showsChevron: Bool) -> some View {
        HStack(spacing: AppTheme.dashboardSpacing) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            Text(value.isEmpty ? AppStrings.Events.regionPlaceholder : value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(value.isEmpty ? AppTheme.textSecondary.opacity(0.68) : AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
            }
        }
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    func eventEditorCompactInputStyle(minHeight: CGFloat) -> some View {
        self.appEditorInputStyle(minHeight: minHeight)
    }
}

extension AustrianFederalState {
    var displayName: String {
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


#Preview {
    NavigationStack {
        EventEditorView(
            repository: MockEventRepository(),
            organizationId: "preview-organization",
            organizationName: "Preview Organization",
            organizationImageURL: nil,
            organizationFederalState: .wien
        )
    }
}
