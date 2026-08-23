import PhotosUI
import SwiftUI
import UIKit

struct FeaturedBannerEditorView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: FeaturedBannerEditorViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPreviewImage: UIImage?
    @State private var cropSourceImage: UIImage?
    @State private var isShowingImageCrop = false
    @State private var ignoresNextPhotoClear = false
    @State private var imageProcessingTask: Task<Void, Never>?
    @State private var imageProcessingToken = UUID()
    @State private var isShowingActionTargetPicker = false
    @State private var actionTargetSearchText = ""
    @State private var isShowingDiscardConfirmation = false
    let onSave: @MainActor () async -> Void

    init(
        repository: FeaturedBannerRepository,
        mode: FeaturedBannerEditorViewModel.Mode = .create,
        newsRepository: NewsRepository? = nil,
        eventRepository: EventRepository? = nil,
        organizationRepository: OrganizationRepository? = nil,
        onSave: @escaping @MainActor () async -> Void
    ) {
        _viewModel = StateObject(wrappedValue: FeaturedBannerEditorViewModel(
            repository: repository,
            mode: mode,
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository
        ))
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
            FeaturedBannerEditorPreviewSection(viewModel: viewModel, previewImage: selectedPreviewImage)
            FeaturedBannerEditorBasicsSection(viewModel: viewModel)
            imageCard
            FeaturedBannerEditorTargetingSection(viewModel: viewModel)
            FeaturedBannerEditorActionSection(viewModel: viewModel) {
                actionTargetSearchText = ""
                isShowingActionTargetPicker = true
            }
            FeaturedBannerEditorSchedulingSection(viewModel: viewModel)
        }
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
        .tint(AppTheme.accentPrimary)
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
        .sheet(isPresented: $isShowingImageCrop, onDismiss: resetCropSelection) {
            if let cropSourceImage {
                ImageCropView(
                    sourceImage: cropSourceImage,
                    profile: .hero16x9,
                    title: AppStrings.Images.Crop.title,
                    instructions: AppStrings.FeaturedEditor.cropInstructions,
                    onCancel: {},
                    onApply: applyCroppedImage(_:)
                )
            }
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
        .confirmationDialog(
            AppStrings.FeaturedEditor.discardConfirmationTitle,
            isPresented: $isShowingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.FeaturedEditor.discardChanges, role: .destructive) {
                dismiss()
            }
            Button(AppStrings.Action.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.FeaturedEditor.discardConfirmationMessage)
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

    private var imageCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.imageSection)

                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    imagePickerContent
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessingImage || viewModel.isSaving)
                .overlay {
                    if viewModel.isProcessingImage {
                        imageProcessingOverlay
                    }
                }

                Text(AppStrings.FeaturedEditor.imageHelper)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var imagePickerContent: some View {
        if let selectedPreviewImage {
            Rectangle()
                .fill(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72))
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    Image(uiImage: selectedPreviewImage)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
        } else if let existingImageURL = viewModel.existingImageURL {
            RemoteImageView(
                imageURL: existingImageURL,
                height: AppTheme.heroBannerHeight,
                cornerRadius: AppTheme.heroRadius,
                source: "FeaturedBannerEditorView",
                placeholderStyle: .glassSkeleton
            )
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                Text(AppStrings.FeaturedEditor.replaceImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                    .padding(.vertical, AppTheme.eventsMetadataSpacing)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(AppTheme.dashboardSpacing)
            }
        } else {
            uploadPlaceholder
        }
    }

    private var imageProcessingOverlay: some View {
        ProgressView()
            .controlSize(.regular)
            .tint(AppTheme.accentPrimary)
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
            .allowsHitTesting(false)
    }

    private var uploadPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)

            Text(AppStrings.FeaturedEditor.uploadImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.FeaturedEditor.uploadImageHelper)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72), in: RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                .stroke(AppTheme.glassBorder(for: colorScheme).opacity(0.82), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        )
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            PrimaryActionButton(
                title: viewModel.saveButtonTitle,
                loadingTitle: AppStrings.FeaturedEditor.saving,
                isEnabled: viewModel.canSave,
                isLoading: viewModel.isSaving,
                systemImage: "checkmark"
            ) {
                Task {
                    let didSave = await viewModel.save(updatedBy: authState.user?.id)
                    guard didSave else { return }
                    await onSave()
                    dismiss()
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.eventsMetadataSpacing)
            .padding(.bottom, AppTheme.eventsMetadataSpacing)
            .background(.ultraThinMaterial)
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

            guard let sourceImage = UIImage(data: originalData) else {
                throw ImageProcessingError.invalidImageData
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard imageProcessingToken == token else { return }
                cropSourceImage = sourceImage
                isShowingImageCrop = true
                viewModel.setImageProcessing(false)
                viewModel.errorMessage = nil
            }
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

    private func applyCroppedImage(_ processedImage: ProcessedImageSelection) {
        guard let previewImage = UIImage(data: processedImage.data) else {
            viewModel.errorMessage = AppStrings.FeaturedEditor.imageLoadFailed
            return
        }

        selectedPreviewImage = previewImage
        viewModel.setSelectedImageSelection(processedImage)
        viewModel.errorMessage = nil
    }

    private func resetCropSelection() {
        cropSourceImage = nil
        guard selectedPhoto != nil else { return }
        ignoresNextPhotoClear = true
        selectedPhoto = nil
    }

    private func requestDismiss() {
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
