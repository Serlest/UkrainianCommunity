import SwiftUI

struct OrganizerPickerSheet: View {
    @Environment(\.dismiss) var dismiss

    let organizations: [Organization]
    let selectedOrganizationID: String?
    let onSelect: (Organization) -> Void

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                    ForEach(organizations) { organization in
                        Button {
                            onSelect(organization)
                        } label: {
                            organizerRow(for: organization)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
            .background(AppBackgroundView())
            .navigationTitle(AppStrings.Events.editorPublisherSectionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) {
                        dismiss()
                    }
                }
            }
        }
    }

    func organizerRow(for organization: Organization) -> some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .top, spacing: AppTheme.eventsCardHorizontalSpacing) {
                AppFeedThumbnail(
                    imageURL: organization.imageURL,
                    fallbackSystemImage: "building.2",
                    tint: AppTheme.accentPrimary,
                    fill: AppTheme.badgeBlueFill,
                    size: AppTheme.organizationsThumbnailSize,
                    cornerRadius: AppTheme.feedThumbnailRadius,
                    source: "OrganizerPickerSheet"
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(organization.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if !organization.shortDescription.isEmpty {
                        Text(organization.shortDescription)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.82))
                            .lineLimit(2)
                    }

                    AppInfoChip(
                        title: organization.city,
                        systemImage: "mappin.and.ellipse",
                        tint: AppTheme.textSecondary,
                        fill: AppTheme.surfaceControl.opacity(0.62),
                        size: .small
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if organization.id == selectedOrganizationID {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
            }
        }
    }
}
