import PhotosUI
import SwiftUI
import UIKit

extension OrganizationEditorView {
    var logoPicker: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
            logoPickerContent
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessingImage || organizationsViewModel.isSavingOrganization)
        .accessibilityLabel(AppStrings.Organizations.imageSectionTitle)
    }

    @ViewBuilder
    var logoPickerContent: some View {
        if let selectedImageData = viewModel.selectedImageData,
           let image = UIImage(data: selectedImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
                .overlay(logoBorder)
        } else if let existingImageURL = viewModel.existingImageURL {
            RemoteImageView(
                imageURL: existingImageURL,
                height: uploadMinHeight,
                cornerRadius: AppTheme.imageRadius,
                source: "OrganizationEditorView",
                placeholderStyle: .glassSkeleton
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        } else {
            VStack(spacing: 7) {
                Image(systemName: "photo.badge.plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary.opacity(0.78))

                Text(AppStrings.Organizations.logoUploadTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(AppStrings.Organizations.logoUploadHelper)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
            }
            .padding(editorCardPadding)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
            .overlay(logoBorder)
        }
    }

    var logoBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
            .stroke(AppTheme.glassBorder(for: colorScheme).opacity(0.82), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
    }

    func loadSelectedPhoto(item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run {
                viewModel.setImageProcessing(false)
            }
            return
        }

        await MainActor.run {
            viewModel.setImageProcessing(true)
        }

        do {
            let data = try await item.loadTransferable(type: Data.self)
            guard let data else {
                await MainActor.run {
                    ignoresNextPhotoClear = true
                    selectedPhoto = nil
                    viewModel.setImageProcessing(false)
                    viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
                }
                return
            }
            guard let sourceImage = UIImage(data: data) else {
                throw ImageProcessingError.invalidImageData
            }

            await MainActor.run {
                cropSourceLogoImage = sourceImage
                isShowingLogoCrop = true
                viewModel.setImageProcessing(false)
                viewModel.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                ignoresNextPhotoClear = true
                selectedPhoto = nil
                viewModel.setImageProcessing(false)
                viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
            }
        }
    }

    func applyCroppedLogoImage(_ processedImage: ProcessedImageSelection) {
        guard UIImage(data: processedImage.data) != nil else {
            viewModel.errorMessage = AppStrings.NewsEditor.imageLoadFailed
            return
        }

        viewModel.setSelectedImageData(processedImage.data)
        viewModel.errorMessage = nil
    }

    func resetLogoCropSelection() {
        cropSourceLogoImage = nil
        guard selectedPhoto != nil else { return }
        ignoresNextPhotoClear = true
        selectedPhoto = nil
    }
}
