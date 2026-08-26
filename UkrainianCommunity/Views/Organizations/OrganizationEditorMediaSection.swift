import PhotosUI
import SwiftUI
import UIKit

extension OrganizationEditorView {
    var logoPicker: some View {
        let imageData = viewModel.selectedImageData
        let imageURL = viewModel.existingImageURL
        return PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
            OrganizationLogoPickerLabel(
                selectedImageData: imageData,
                existingImageURL: imageURL
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isProcessingImage || organizationsViewModel.isSavingOrganization)
        .accessibilityLabel(AppStrings.Organizations.imageSectionTitle)
        .accessibilityIdentifier("organization.editor.logo")
    }

    var logoPickerContent: some View {
        OrganizationLogoThumbnail(
            selectedImageData: viewModel.selectedImageData,
            existingImageURL: viewModel.existingImageURL,
            size: 72
        )
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

// The upload instructions participate in normal vertical layout. They must not
// be forced into a square: long translations and Dynamic Type can exceed it.
struct OrganizationLogoPickerLabel: View {
    let selectedImageData: Data?
    let existingImageURL: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    var body: some View {
        layout {
            OrganizationLogoThumbnail(selectedImageData: selectedImageData, existingImageURL: existingImageURL, size: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedImageData == nil && existingImageURL == nil
                     ? AppStrings.Organizations.logoUploadTitle : AppStrings.Organizations.imageSectionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(AppStrings.Organizations.logoUploadHelper)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72),
                    in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.82),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
    }
}

struct OrganizationLogoThumbnail: View {
    let selectedImageData: Data?
    let existingImageURL: String?
    let size: CGFloat

    var body: some View {
        // The frame owns the layout size; both selected and remote images are
        // clipped inside it, including unusually wide or tall source photos.
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                if let selectedImageData, let image = UIImage(data: selectedImageData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let existingImageURL {
                    RemoteImageView(imageURL: existingImageURL, height: size,
                                    cornerRadius: AppTheme.imageRadius, source: "OrganizationEditorView",
                                    placeholderStyle: .glassSkeleton)
                } else {
                    AppTheme.accentPrimarySoft
                        .overlay {
                            Image(systemName: "photo.badge.plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(AppTheme.accentPrimaryForeground)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
    }
}
