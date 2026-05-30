import Combine
import PhotosUI
import SwiftUI

@MainActor
final class OrganizationPhotoGalleryViewModel: ObservableObject {
    @Published private(set) var photos: [OrganizationPhoto] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUploading = false
    @Published private(set) var deletingPhotoIDs = Set<String>()
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let organizationId: String
    private let repository: OrganizationPhotoRepository
    private var hasLoaded = false

    init(organizationId: String, repository: OrganizationPhotoRepository) {
        self.organizationId = organizationId
        self.repository = repository
    }

    var canAddMorePhotos: Bool {
        photos.count < 30
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            photos = try await repository.fetchPhotos(organizationId: organizationId)
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = AppStrings.Organizations.photosLoadFailed
            hasLoaded = true
        }
    }

    func addPhoto(imageData: Data, caption: String?, uploadedBy: String) async {
        guard !isUploading else { return }
        guard canAddMorePhotos else {
            errorMessage = AppStrings.Organizations.photosLimitReached
            return
        }

        isUploading = true
        errorMessage = nil
        statusMessage = nil
        defer { isUploading = false }

        do {
            let photo = try await repository.addPhoto(
                organizationId: organizationId,
                imageData: imageData,
                caption: caption,
                uploadedBy: uploadedBy
            )
            photos.insert(photo, at: 0)
            statusMessage = nil
            hasLoaded = true
        } catch let appError as AppError {
            errorMessage = readablePhotoErrorText(appError)
        } catch {
            errorMessage = AppStrings.Organizations.photosUploadFailed
        }
    }

    func deletePhoto(_ photo: OrganizationPhoto) async {
        guard !deletingPhotoIDs.contains(photo.id) else { return }
        deletingPhotoIDs.insert(photo.id)
        errorMessage = nil
        statusMessage = nil
        defer { deletingPhotoIDs.remove(photo.id) }

        do {
            try await repository.deletePhoto(photo)
            photos.removeAll { $0.id == photo.id }
        } catch {
            errorMessage = AppStrings.Organizations.photosDeleteFailed
        }
    }

    private func readablePhotoErrorText(_ error: AppError) -> String {
        switch error {
        case .validationFailed:
            AppStrings.Organizations.photosLimitReached
        case .permissionDenied:
            AppStrings.Organizations.actionPermissionError
        default:
            AppStrings.Organizations.photosUploadFailed
        }
    }
}

struct OrganizationPhotoGallerySection: View {
    let organizationId: String
    let canManage: Bool
    let currentUser: AppUser?
    let onPhotosChanged: ([OrganizationPhoto]) -> Void

    @StateObject private var viewModel: OrganizationPhotoGalleryViewModel
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var pendingPhotoData: Data?
    @State private var pendingCaption = ""
    @State private var isPreparingPhoto = false
    @State private var isShowingCaptionSheet = false
    @State private var pendingDeletePhoto: OrganizationPhoto?
    @State private var selectedPreviewPhoto: OrganizationPhoto?
    @State private var photoGridAvailableWidth: CGFloat = 0

    private let photoGridSpacing: CGFloat = 12

    init(
        organizationId: String,
        canManage: Bool,
        currentUser: AppUser?,
        repository: OrganizationPhotoRepository = FirestoreOrganizationPhotoRepository(),
        onPhotosChanged: @escaping ([OrganizationPhoto]) -> Void = { _ in }
    ) {
        self.organizationId = organizationId
        self.canManage = canManage
        self.currentUser = currentUser
        self.onPhotosChanged = onPhotosChanged
        _viewModel = StateObject(wrappedValue: OrganizationPhotoGalleryViewModel(organizationId: organizationId, repository: repository))
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                header
                content
                messages
            }
        }
        .task(id: organizationId) {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onChange(of: selectedPickerItem) { _, item in
            Task {
                await prepareSelectedPhoto(item)
            }
        }
        .onChange(of: viewModel.photos) { _, photos in
            onPhotosChanged(photos)
        }
        .sheet(isPresented: $isShowingCaptionSheet) {
            NavigationStack {
                captionSheet
            }
        }
        .confirmationDialog(
            AppStrings.Organizations.photosDeleteConfirmation,
            isPresented: Binding(
                get: { pendingDeletePhoto != nil },
                set: { if !$0 { pendingDeletePhoto = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDeletePhoto {
                Button(AppStrings.Organizations.photosDelete, role: .destructive) {
                    Task {
                        await viewModel.deletePhoto(pendingDeletePhoto)
                        self.pendingDeletePhoto = nil
                    }
                }
            }
            Button(AppStrings.Organizations.cancel, role: .cancel) {
                pendingDeletePhoto = nil
            }
        }
        .fullScreenCover(item: $selectedPreviewPhoto) { photo in
            OrganizationPhotoPreviewView(photos: viewModel.photos, initialPhoto: photo)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            AppEditorSectionTitle(title: AppStrings.Organizations.tabPhoto)

            Text("\(viewModel.photos.count)/30")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(AppTheme.surfaceControl.opacity(0.55), in: Capsule())
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.photos.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppTheme.dashboardSpacing)
        } else if viewModel.photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if canManage {
                    photoGrid
                }
                compactEmptyState
            }
        } else {
            photoGrid
        }
    }

    private var photoGrid: some View {
        let isPhotoPickingAllowed = canPickPhoto
        let isPhotoPickerBusy = viewModel.isUploading || isPreparingPhoto
        let metrics = photoGridMetrics(for: photoGridAvailableWidth)

        return LazyVGrid(columns: metrics.columns, alignment: .leading, spacing: photoGridSpacing) {
            if canManage {
                PhotosPicker(selection: $selectedPickerItem, matching: .images, photoLibrary: .shared()) {
                    OrganizationAddPhotoTile(
                        isDisabled: !isPhotoPickingAllowed,
                        isBusy: isPhotoPickerBusy,
                        cellSize: metrics.cellSize
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isPhotoPickingAllowed)
                .accessibilityLabel(AppStrings.Organizations.photosAdd)
            }

            ForEach(viewModel.photos) { photo in
                OrganizationPhotoTile(
                    photo: photo,
                    canManage: canManage,
                    isDeleting: viewModel.deletingPhotoIDs.contains(photo.id),
                    cellSize: metrics.cellSize,
                    onOpen: { selectedPreviewPhoto = photo },
                    onDelete: { pendingDeletePhoto = photo }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(.horizontal, 0)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updatePhotoGridWidth(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        updatePhotoGridWidth(width)
                    }
            }
        }
    }

    private var messages: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isPreparingPhoto {
                Label(AppStrings.Organizations.photosPreparing, systemImage: "photo")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if viewModel.isUploading {
                Label(AppStrings.Organizations.photosUploading, systemImage: "arrow.up.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.accentPrimary)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.accentDestructive)
            }
        }
    }

    private var compactEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(AppStrings.Organizations.photosEmptyTitle, systemImage: "photo.on.rectangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.Organizations.photosEmptyMessage)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var captionSheet: some View {
        Form {
            Section(AppStrings.Organizations.photosCaption) {
                TextField(AppStrings.Organizations.photosCaptionPlaceholder, text: $pendingCaption, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .navigationTitle(AppStrings.Organizations.photosAdd)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.Organizations.cancel) {
                    resetPendingPhoto()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(AppStrings.Organizations.photosUpload) {
                    uploadPendingPhoto()
                }
                .disabled(pendingPhotoData == nil || viewModel.isUploading)
            }
        }
    }

    private var canPickPhoto: Bool {
        canManage && !viewModel.isUploading && !isPreparingPhoto && viewModel.canAddMorePhotos
    }

    private func photoGridMetrics(for availableWidth: CGFloat) -> (columns: [GridItem], cellSize: CGFloat) {
        let safeWidth = max(1, availableWidth)
        let columnsCount = safeWidth >= 330 ? 3 : 2
        let totalSpacing = photoGridSpacing * CGFloat(columnsCount - 1)
        let cellSize = max(1, floor((safeWidth - totalSpacing) / CGFloat(columnsCount)))
        let columns = Array(
            repeating: GridItem(.fixed(cellSize), spacing: photoGridSpacing),
            count: columnsCount
        )
        return (columns, cellSize)
    }

    private func updatePhotoGridWidth(_ width: CGFloat) {
        let normalizedWidth = max(0, width)
        guard abs(photoGridAvailableWidth - normalizedWidth) > 0.5 else { return }
        photoGridAvailableWidth = normalizedWidth
    }

    private func prepareSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isPreparingPhoto = true
        defer {
            isPreparingPhoto = false
            selectedPickerItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.errorMessage = AppStrings.Organizations.photosSelectionFailed
                return
            }
            let processedImage = try await ImageProcessingService.process(data: data, profile: .galleryPhoto)
            pendingPhotoData = processedImage.data
            pendingCaption = ""
            isShowingCaptionSheet = true
        } catch {
            viewModel.errorMessage = AppStrings.Organizations.photosSelectionFailed
        }
    }

    private func uploadPendingPhoto() {
        guard let pendingPhotoData, let currentUser else { return }
        guard !viewModel.isUploading else { return }
        let caption = pendingCaption
        Task {
            await viewModel.addPhoto(imageData: pendingPhotoData, caption: caption, uploadedBy: currentUser.id)
            if viewModel.errorMessage == nil {
                resetPendingPhoto()
            }
        }
    }

    private func resetPendingPhoto() {
        pendingPhotoData = nil
        pendingCaption = ""
        isShowingCaptionSheet = false
    }
}

private struct OrganizationPhotoTile: View {
    let photo: OrganizationPhoto
    let canManage: Bool
    let isDeleting: Bool
    let cellSize: CGFloat
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            photoImage
        }
        .frame(width: cellSize, height: cellSize)
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(photo.caption ?? AppStrings.Organizations.tabPhoto)
        .overlay(alignment: .topTrailing) {
            deleteButton
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if canManage {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: isDeleting ? "hourglass" : "trash")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.accentDestructive.opacity(0.92), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .padding(6)
            .accessibilityLabel(AppStrings.Organizations.photosDelete)
        }
    }

    private var photoImage: some View {
        AsyncImage(url: URL(string: photo.imageURL)) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                fallbackImage
            default:
                AppTheme.surfaceControl.opacity(0.65)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(width: cellSize, height: cellSize)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.65))
        )
    }

    private var fallbackImage: some View {
        AppTheme.surfaceControl.opacity(0.65)
            .overlay(
                Image(systemName: "photo")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            )
    }
}

private struct OrganizationAddPhotoTile: View {
    let isDisabled: Bool
    let isBusy: Bool
    let cellSize: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 38, height: 38)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.accentPrimarySoft, in: Circle())
                }
            }

            Text(AppStrings.Organizations.photosAdd)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .lineLimit(1)
        }
        .frame(width: cellSize, height: cellSize)
        .background(AppTheme.surfaceSecondary.opacity(isDisabled ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.accentPrimary.opacity(isDisabled ? 0.10 : 0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .opacity(isDisabled ? 0.65 : 1)
    }
}

private struct OrganizationPhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [OrganizationPhoto]
    let initialPhoto: OrganizationPhoto
    @State private var selectedPhotoID: String

    init(photos: [OrganizationPhoto], initialPhoto: OrganizationPhoto) {
        self.photos = photos
        self.initialPhoto = initialPhoto
        _selectedPhotoID = State(initialValue: initialPhoto.id)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedPhotoID) {
                ForEach(photos) { photo in
                    VStack(spacing: AppTheme.dashboardSpacing) {
                        Spacer(minLength: 0)
                        AsyncImage(url: URL(string: photo.imageURL)) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(AppTheme.textSecondary)
                            default:
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if let caption = photo.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppTheme.pageHorizontal)
                        }
                        Spacer(minLength: 0)
                    }
                    .tag(photo.id)
                    .padding(.vertical, AppTheme.dashboardSpacing)
                }
            }
            .tabViewStyle(.page)
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppStrings.Common.done) {
                        dismiss()
                    }
                    .foregroundStyle(Color.white)
                }
            }
        }
    }
}
