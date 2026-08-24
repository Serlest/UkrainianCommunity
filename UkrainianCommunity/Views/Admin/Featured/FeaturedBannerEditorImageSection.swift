import PhotosUI
import SwiftUI
import UIKit

struct FeaturedBannerEditorImageSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel
    @Binding var selectedPhoto: PhotosPickerItem?
    let previewImage: UIImage?

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.imageSection)

                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    imageContent
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessingImage || viewModel.isSaving)
                .overlay {
                    if viewModel.isProcessingImage {
                        processingOverlay
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
    private var imageContent: some View {
        if let previewImage {
            Rectangle()
                .fill(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72))
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .clipShape(cardShape)
                .overlay(cardShape.strokeBorder(AppTheme.glassBorder(for: colorScheme)))
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
                    .background(AppTheme.mediaOverlayFill, in: Capsule())
                    .padding(AppTheme.dashboardSpacing)
            }
        } else {
            uploadPlaceholder
        }
    }

    private var processingOverlay: some View {
        ProgressView()
            .controlSize(.regular)
            .tint(AppTheme.accentPrimary)
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(AppTheme.emptyMediaFill, in: cardShape)
            .allowsHitTesting(false)
    }

    private var uploadPlaceholder: some View {
        VStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "photo.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)

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
        .background(AppTheme.glassControlSurface(for: colorScheme).opacity(0.72), in: cardShape)
        .overlay(
            cardShape.stroke(
                AppTheme.glassBorder(for: colorScheme).opacity(0.82),
                style: StrokeStyle(lineWidth: 1, dash: [5, 5])
            )
        )
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
    }
}
