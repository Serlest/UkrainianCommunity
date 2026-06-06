import PhotosUI
import SwiftUI
import UIKit

extension NewsEditorView {
        var coverImageCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.coverSectionTitle)

                    PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                        coverPickerContent
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isProcessingImage || viewModel.isPublishing)
                    .overlay {
                        if viewModel.isProcessingImage {
                            imageProcessingOverlay
                        }
                    }
                }
            }
        }

        @ViewBuilder
        var coverPickerContent: some View {
            if let selectedPreviewImage {
                let image = selectedPreviewImage
                Rectangle()
                    .fill(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                            .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                    )
            } else if let existingImageURL = viewModel.existingImageURL {
                RemoteImageView(
                    imageURL: existingImageURL,
                    height: uploadMinHeight,
                    cornerRadius: AppTheme.imageRadius,
                    source: "NewsEditorView",
                    placeholderStyle: .glassSkeleton
                )
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    Text(AppStrings.NewsEditor.replacePhoto)
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

        var imageProcessingOverlay: some View {
            ProgressView()
                .controlSize(.regular)
                .tint(AppTheme.accentPrimary)
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
                .allowsHitTesting(false)
        }

        var uploadPlaceholder: some View {
            VStack(spacing: 7) {
                Image(systemName: "photo.badge.plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary.opacity(0.78))

                Text(AppStrings.NewsEditor.coverUploadTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(AppStrings.NewsEditor.coverUploadHelper)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                    .stroke(AppTheme.glassBorder(for: colorScheme).opacity(0.82), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
        }

        func loadSelectedPhoto(item: PhotosPickerItem?, token: UUID) async {
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
                        viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
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
                    viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
                }
            }
        }

        func applyCroppedImage(_ processedImage: ProcessedImageSelection) {
            guard let previewImage = UIImage(data: processedImage.data) else {
                viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
                return
            }

            selectedPreviewImage = previewImage
            viewModel.setSelectedImageSelection(processedImage)
            viewModel.errorMessage = nil
        }

        func resetCropSelection() {
            cropSourceImage = nil
            guard selectedPhoto != nil else { return }
            ignoresNextPhotoClear = true
            selectedPhoto = nil
        }
}
