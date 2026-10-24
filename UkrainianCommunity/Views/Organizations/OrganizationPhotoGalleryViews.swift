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
    @Published private(set) var supportsReplacement = false
    @Published private(set) var hasReplacementConflict = false

    private let organizationId: String
    private let repository: OrganizationPhotoRepository
    private(set) var hasLoaded = false

    init(organizationId: String, repository: OrganizationPhotoRepository) {
        self.organizationId = organizationId
        self.repository = repository
    }

    var canAddMorePhotos: Bool {
        photos.count < 30
    }

    func refreshReplacementAvailability() async {
        supportsReplacement = (try? await repository.supportsPhotoReplacement(organizationId: organizationId)) == true
    }

    func replacePhoto(_ original: OrganizationPhoto, imageData: Data, caption: String?) async {
        guard !isUploading else { return }
        isUploading = true
        errorMessage = nil
        hasReplacementConflict = false
        defer { isUploading = false }
        do {
            let replacement = try await repository.replacePhoto(original, imageData: imageData, caption: caption)
            if let index = photos.firstIndex(where: { $0.id == original.id }) { photos[index] = replacement }
        } catch let failure as OrganizationAccessFailure {
            errorMessage = failure.localizedDescription
            hasReplacementConflict = failure.reason == "object_changed"
        }
        catch { errorMessage = AppStrings.Organizations.photosUploadFailed }
    }

    func reloadReplacementTarget(id: String) async -> OrganizationPhoto? {
        guard !isLoading, !isUploading else { return nil }
        isLoading = true
        defer { isLoading = false }
        do {
            let latest = try await RefreshRequest.run { [self] in try await repository.fetchPhotos(organizationId: organizationId) }
            photos = latest
            guard let photo = latest.first(where: { $0.id == id }) else {
                hasReplacementConflict = false
                errorMessage = OrganizationAccessFailure(reason: "object_missing").localizedDescription
                return nil
            }
            clearEditorFailure()
            return photo
        } catch {
            errorMessage = AppStrings.Organizations.photosLoadFailed
            return nil
        }
    }

    func clearEditorFailure() {
        errorMessage = nil
        hasReplacementConflict = false
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            photos = try await RefreshRequest.run { [self] in try await repository.fetchPhotos(organizationId: organizationId) }
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
        } catch let failure as OrganizationAccessFailure {
            errorMessage = failure.localizedDescription
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
        } catch let failure as OrganizationAccessFailure {
            errorMessage = failure.localizedDescription
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
    let refreshToken: Int

    @StateObject private var viewModel: OrganizationPhotoGalleryViewModel
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var replacementPickerItem: PhotosPickerItem?
    @State private var replacementTarget: OrganizationPhoto?
    @State private var isShowingReplacementPicker = false
    @State private var photoEditorGeneration = UUID()
    @State private var pendingPhotoData: Data?
    @State private var pendingCaption = ""
    @State private var isPreparingPhoto = false
    @State private var isShowingCaptionSheet = false
    @State private var pendingDeletePhoto: OrganizationPhoto?
    @State private var selectedPreviewPhoto: OrganizationPhoto?
    @State private var photoGridAvailableWidth: CGFloat = 0

    private let photoGridSpacing: CGFloat = 12
    private let maximumCaptionLength = 500

    init(
        organizationId: String,
        canManage: Bool,
        currentUser: AppUser?,
        repository: OrganizationPhotoRepository = OrganizationPhotoRepositoryFactory.make(),
        refreshToken: Int = 0,
        onPhotosChanged: @escaping ([OrganizationPhoto]) -> Void = { _ in }
    ) {
        self.organizationId = organizationId
        self.canManage = canManage
        self.currentUser = currentUser
        self.onPhotosChanged = onPhotosChanged
        self.refreshToken = refreshToken
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
        .task(id: "\(organizationId):\(refreshToken)") {
            if refreshToken == 0 { await viewModel.loadIfNeeded() }
            else { await viewModel.refresh() }
            if canManage { await viewModel.refreshReplacementAvailability() }
        }
        .appRefreshable {
            await viewModel.refresh()
            if canManage { await viewModel.refreshReplacementAvailability() }
        }
        .onChange(of: canManage) { _, allowed in
            if !allowed { revokePhotoEditor() }
        }
        .onChange(of: currentUser?.id) { _, _ in revokePhotoEditor() }
        .onChange(of: selectedPickerItem) { _, item in
            replacementTarget = nil
            Task {
                await prepareSelectedPhoto(item)
            }
        }
        .photosPicker(isPresented: $isShowingReplacementPicker, selection: $replacementPickerItem, matching: .images)
        .onChange(of: replacementPickerItem) { _, item in
            Task { await prepareSelectedPhoto(item) }
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
                    let generation = photoEditorGeneration
                    Task {
                        guard canManage, photoEditorGeneration == generation else { return }
                        await viewModel.deletePhoto(pendingDeletePhoto)
                        if photoEditorGeneration == generation { self.pendingDeletePhoto = nil }
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

            Text(canManage ? "\(viewModel.photos.count)/30" : "\(viewModel.photos.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(AppTheme.surfaceControl.opacity(0.55), in: Capsule())
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.photos.isEmpty && (viewModel.isLoading || (!viewModel.hasLoaded && viewModel.errorMessage == nil)) {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppTheme.dashboardSpacing)
        } else if viewModel.photos.isEmpty && viewModel.errorMessage != nil {
            EmptyView()
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
                    onReplace: canManage && viewModel.supportsReplacement && !viewModel.isUploading ? {
                        replacementTarget = photo
                        isShowingReplacementPicker = true
                    } : nil,
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
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.accentDestructiveForeground)
                Button(AppStrings.Organizations.retry) { Task { await viewModel.refresh() } }
                    .disabled(viewModel.isLoading)
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
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.accentDestructiveForeground)
                        .accessibilityIdentifier("organization.photo.editor.error")
                    if viewModel.hasReplacementConflict, let target = replacementTarget {
                        Button(AppStrings.Organizations.photosReloadCurrent) {
                            Task {
                                if let latest = await viewModel.reloadReplacementTarget(id: target.id),
                                   isShowingCaptionSheet, replacementTarget?.id == target.id {
                                    replacementTarget = latest
                                }
                            }
                        }
                        .disabled(viewModel.isLoading)
                        .accessibilityIdentifier("organization.photo.editor.reload")
                    }
                }
            }
            Section {
                TextField(AppStrings.Organizations.photosCaptionPlaceholder, text: $pendingCaption, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: pendingCaption) { _, value in
                        if value.count > maximumCaptionLength {
                            pendingCaption = String(value.prefix(maximumCaptionLength))
                        }
                    }
            } header: {
                Text(AppStrings.Organizations.photosCaption)
            } footer: {
                Text("\(pendingCaption.count)/\(maximumCaptionLength)")
                    .monospacedDigit()
            }
        }
        .navigationTitle(replacementTarget == nil ? AppStrings.Organizations.photosAdd : AppStrings.Organizations.photosReplace)
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
                .disabled(pendingPhotoData == nil || viewModel.isUploading || viewModel.isLoading)
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
        guard canManage, let item else { return }
        let generation = photoEditorGeneration
        isPreparingPhoto = true
        defer {
            if photoEditorGeneration == generation {
                isPreparingPhoto = false
                if replacementTarget == nil { selectedPickerItem = nil }
                replacementPickerItem = nil
            }
        }

        do {
            let selection = try await item.loadTransferable(type: Data.self)
            guard photoEditorGeneration == generation, !Task.isCancelled else { return }
            guard let data = selection else {
                viewModel.errorMessage = AppStrings.Organizations.photosSelectionFailed
                return
            }
            let processedImage = try await ImageProcessingService.process(data: data, profile: .galleryPhoto)
            guard photoEditorGeneration == generation, !Task.isCancelled else { return }
            viewModel.clearEditorFailure()
            pendingPhotoData = processedImage.data
            pendingCaption = replacementTarget?.caption ?? ""
            isShowingCaptionSheet = true
        } catch {
            guard photoEditorGeneration == generation else { return }
            viewModel.errorMessage = AppStrings.Organizations.photosSelectionFailed
        }
    }

    private func uploadPendingPhoto() {
        guard canManage, let pendingPhotoData, let currentUser else { return }
        guard !viewModel.isUploading else { return }
        let generation = photoEditorGeneration
        let caption = pendingCaption
        let target = replacementTarget
        Task {
            guard photoEditorGeneration == generation else { return }
            if let target {
                await viewModel.replacePhoto(target, imageData: pendingPhotoData, caption: caption)
            } else {
                await viewModel.addPhoto(imageData: pendingPhotoData, caption: caption, uploadedBy: currentUser.id)
            }
            if photoEditorGeneration == generation, viewModel.errorMessage == nil {
                resetPendingPhoto()
            }
        }
    }

    private func revokePhotoEditor() {
        photoEditorGeneration = UUID()
        isPreparingPhoto = false
        isShowingReplacementPicker = false
        pendingDeletePhoto = nil
        selectedPickerItem = nil
        replacementPickerItem = nil
        resetPendingPhoto()
    }

    private func resetPendingPhoto() {
        pendingPhotoData = nil
        pendingCaption = ""
        isShowingCaptionSheet = false
        replacementTarget = nil
    }
}

private struct OrganizationPhotoTile: View {
    let photo: OrganizationPhoto
    let canManage: Bool
    let isDeleting: Bool
    let cellSize: CGFloat
    let onOpen: () -> Void
    let onReplace: (() -> Void)?
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
        .contextMenu {
            if let onReplace {
                Button(AppStrings.Organizations.photosReplace, systemImage: "arrow.triangle.2.circlepath", action: onReplace)
                    .disabled(isDeleting)
            }
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
            .frame(
                width: AppTheme.minimumInteractiveTarget,
                height: AppTheme.minimumInteractiveTarget
            )
            .contentShape(Rectangle())
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
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.accentPrimarySoft, in: Circle())
                }
            }

            Text(AppStrings.Organizations.photosAdd)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
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
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
