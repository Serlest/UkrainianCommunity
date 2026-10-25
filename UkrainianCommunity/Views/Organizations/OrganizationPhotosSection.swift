import SwiftUI

extension OrganizationDetailView {
    var highlightedPhotosSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            organizationHighlightHeader(title: AppStrings.Organizations.latestPhotosTitle, actionTitle: AppStrings.Organizations.tabPhoto) {
                Button {
                    switchToSection(.photos)
                } label: {
                    highlightActionLabel(AppStrings.Organizations.tabPhoto)
                }
                .buttonStyle(.plain)
            }

            AppHorizontalChipRow {
                ForEach(Array(previewPhotos.prefix(5))) { photo in
                    Button {
                        switchToSection(.photos)
                    } label: {
                        highlightPhotoTile(photo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func highlightPhotoTile(_ photo: OrganizationPhoto) -> some View {
        OrganizationGalleryImage(photo: photo, height: 86, fit: false)
        .frame(width: 86, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.65))
        )
        .accessibilityLabel(photo.caption ?? AppStrings.Organizations.tabPhoto)
    }
}
