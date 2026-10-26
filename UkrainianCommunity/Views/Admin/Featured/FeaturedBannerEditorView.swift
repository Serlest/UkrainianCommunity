import PhotosUI
import SwiftUI
import UIKit

struct FeaturedBannerEditorView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FeaturedBannerEditorViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPreviewImage: UIImage?
    @State private var imageProcessingTask: Task<Void, Never>?
    @State private var imageProcessingToken = UUID()
    @State private var isShowingActionTargetPicker = false
    @State private var actionTargetSearchText = ""
    @State private var isShowingDiscardConfirmation = false
    private let measurementRepository: BannerMeasurementReportRepository
    private let bannerRepository: FeaturedBannerRepository
    private let statisticsBanner: FeaturedBanner?
    let onSave: @MainActor () async -> Void

    init(
        repository: FeaturedBannerRepository,
        mode: FeaturedBannerEditorViewModel.Mode = .create,
        newsRepository: NewsRepository? = nil,
        eventRepository: EventRepository? = nil,
        organizationRepository: OrganizationRepository? = nil,
        measurementRepository: BannerMeasurementReportRepository = FirestoreBannerMeasurementReportRepository(),
        onSave: @escaping @MainActor () async -> Void
    ) {
        _viewModel = StateObject(wrappedValue: FeaturedBannerEditorViewModel(
            repository: repository,
            mode: mode,
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository
        ))
        self.measurementRepository = measurementRepository
        self.bannerRepository = repository
        if case .edit(let banner) = mode { statisticsBanner = banner } else { statisticsBanner = nil }
        self.onSave = onSave
    }

    var body: some View {
        EditorScreenShell(
            title: viewModel.navigationTitle,
            subtitle: AppStrings.FeaturedEditor.subtitle,
            closeStyle: .back,
            closeAction: requestDismiss
        ) {
            statusContent
            if let banner = statisticsBanner, PermissionService.isAppOwner(user: authState.user) {
                NavigationLink {
                    BannerMeasurementReportView(repository: measurementRepository, bannerRepository: bannerRepository, initialPeriod: .thirtyDays,
                        bannerID: banner.id, bannerTitle: banner.internalName ?? banner.localizedTitle)
                } label: { Label(AppStrings.BannerReport.openStatistics, systemImage: "chart.bar.xaxis") }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("bannerEditor.statistics")
            }
            FeaturedBannerEditorPreviewSection(viewModel: viewModel, previewImage: selectedPreviewImage)
            FeaturedBannerEditorBasicsSection(viewModel: viewModel)
            FeaturedBannerEditorImageSection(
                viewModel: viewModel,
                selectedPhoto: $selectedPhoto,
                previewImage: selectedPreviewImage
            )
            FeaturedBannerEditorTargetingSection(viewModel: viewModel)
            FeaturedBannerEditorActionSection(viewModel: viewModel) {
                actionTargetSearchText = ""
                isShowingActionTargetPicker = true
            }
            FeaturedBannerEditorCountdownSection(viewModel: viewModel)
            FeaturedBannerEditorSchedulingSection(viewModel: viewModel)
            saveButton
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(viewModel.isSaving || !PermissionService.canManageFeaturedBanners(user: authState.user))
        .tint(AppTheme.accentPrimaryForeground)
        .onChange(of: selectedPhoto) { _, newItem in
            imageProcessingTask?.cancel()
            let token = UUID()
            imageProcessingToken = token
            imageProcessingTask = Task {
                await loadSelectedPhoto(item: newItem, token: token)
            }
        }
        .onChange(of: viewModel.actionType) { oldValue, newValue in
            actionTargetSearchText = ""
            viewModel.handleActionTypeChanged(from: oldValue, to: newValue)
            Task {
                await viewModel.loadActionTargetsIfNeeded()
            }
        }
        .onDisappear {
            imageProcessingTask?.cancel()
        }
        .sheet(isPresented: $isShowingActionTargetPicker) {
            FeaturedBannerActionTargetPickerSheet(
                viewModel: viewModel,
                searchText: $actionTargetSearchText,
                onSelect: { item in
                    viewModel.selectActionTarget(item)
                    isShowingActionTargetPicker = false
                }
            )
        }
        .sheet(isPresented: $isShowingDiscardConfirmation) {
            NotificationConfirmationSheet(title: AppStrings.FeaturedEditor.discardConfirmationTitle,
                message: AppStrings.FeaturedEditor.discardConfirmationMessage, cancel: { isShowingDiscardConfirmation = false }) {
                NotificationConfirmationAction(title: AppStrings.FeaturedEditor.discardChanges, id: "bannerEditor.discard", role: .destructive) { dismiss() }
                NotificationConfirmationAction(title: AppStrings.Action.cancel, id: "bannerEditor.keepEditing", role: .cancel) { isShowingDiscardConfirmation = false }
            }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if let message = viewModel.errorMessage {
            InlineMessageCard(style: .error, message: message)
        } else if let message = viewModel.successMessage {
            InlineMessageCard(style: .success, message: message)
        } else if let validationMessage = viewModel.validationMessage {
            InlineMessageCard(style: .info, message: validationMessage)
        } else if viewModel.isMigratingLegacyBanner {
            InlineMessageCard(
                style: .info,
                message: viewModel.isRepairingMalformedBanner
                    ? AppStrings.FeaturedEditor.dataRepairMessage
                    : AppStrings.FeaturedEditor.legacyMigrationMessage
            )
        }
    }

    private var saveButton: some View {
        PrimaryActionButton(
            title: viewModel.saveButtonTitle,
            loadingTitle: AppStrings.FeaturedEditor.saving,
            isEnabled: viewModel.canSave,
            isLoading: viewModel.isSaving,
            systemImage: "checkmark"
        ) {
            save()
        }.accessibilityIdentifier("bannerEditor.save")
    }

    private func save() {
        Task {
            let principal = authState.user?.id
            let didSave = await viewModel.save(updatedBy: principal) {
                authState.user?.id == principal && PermissionService.canManageFeaturedBanners(user: authState.user)
            }
            guard didSave, authState.user?.id == principal else { return }
            await onSave()
            dismiss()
        }
    }

    private func loadSelectedPhoto(item: PhotosPickerItem?, token: UUID) async {
        guard let item else {
            await MainActor.run {
                guard imageProcessingToken == token else { return }
                viewModel.setImageProcessing(false)
                viewModel.setSelectedImageData(nil)
                selectedPreviewImage = nil
            }
            return
        }

        await MainActor.run {
            guard imageProcessingToken == token else { return }
            viewModel.setImageProcessing(true)
        }

        do {
            let originalData = try await item.loadTransferable(type: Data.self)
            guard !Task.isCancelled else { return }
            guard let originalData else {
                await MainActor.run {
                    guard imageProcessingToken == token else { return }
                    selectedPhoto = nil
                    viewModel.setImageProcessing(false)
                    viewModel.errorMessage = AppStrings.FeaturedEditor.imageLoadFailed
                }
                return
            }

            guard !Task.isCancelled else { return }
            let processedImage = try await ImageProcessingService.process(
                data: originalData,
                profile: .adaptiveBanner
            )
            guard !Task.isCancelled else { return }
            applyProcessedImage(processedImage, token: token)
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard imageProcessingToken == token else { return }
                selectedPhoto = nil
                viewModel.setImageProcessing(false)
                viewModel.errorMessage = AppStrings.FeaturedEditor.imageLoadFailed
            }
        }
    }

    @MainActor
    private func applyProcessedImage(_ processedImage: ProcessedImageSelection, token: UUID) {
        guard imageProcessingToken == token else { return }
        guard let previewImage = UIImage(data: processedImage.data) else {
            selectedPhoto = nil
            viewModel.setImageProcessing(false)
            viewModel.errorMessage = AppStrings.FeaturedEditor.imageLoadFailed
            return
        }

        selectedPreviewImage = previewImage
        viewModel.setSelectedImageSelection(processedImage)
        viewModel.setImageProcessing(false)
        viewModel.errorMessage = nil
    }

    private func requestDismiss() {
        guard !viewModel.isSaving else { return }
        if viewModel.hasUnsavedChanges {
            isShowingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        FeaturedBannerEditorView(repository: MockFeaturedBannerRepository()) {}
            .environmentObject(AuthState())
    }
}
