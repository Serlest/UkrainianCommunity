import SwiftUI

struct GuideHierarchyHeaderCard: View {
    let title: String
    let subtitle: String?
    let badgeSystemImage: String
    let badgeTitle: String
    let contextText: String?

    var body: some View {
        DetailHeaderCard(title: title, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                ContentMetadataPill(systemImage: badgeSystemImage, text: badgeTitle.uppercased())

                if let contextText, !contextText.isEmpty {
                    Text(contextText)
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct GuideSectionCard: View {
    let node: GuideNode

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .top, spacing: AppTheme.eventsCardHorizontalSpacing) {
                GuideReaderCardIcon(systemImage: node.displaySystemImage)

                VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacingTight) {
                    Text(node.title)
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if !node.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(node.summary)
                            .font(AppTheme.cardSubtitleFont)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.84))
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                    .padding(.top, 4)
            }
        }
    }
}

struct GuideMaterialCard: View {
    let material: GuideMaterial

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .top, spacing: AppTheme.eventsCardHorizontalSpacing) {
                GuideReaderCardIcon(systemImage: "doc.text")

                VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacingTight) {
                    Text(material.title)
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if !material.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(material.summary)
                            .font(AppTheme.cardSubtitleFont)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.84))
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                    .padding(.top, 4)
            }
        }
    }
}

private struct GuideReaderCardIcon: View {
    let systemImage: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.feedThumbnailRadius, style: .continuous)
                .fill(AppTheme.badgeBlueFill)

            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
        }
        .frame(width: AppTheme.organizationsThumbnailSize, height: AppTheme.organizationsThumbnailSize)
    }
}
