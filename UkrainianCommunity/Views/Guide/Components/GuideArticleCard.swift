import SwiftUI

struct GuideArticleCard: View {
    let article: GuideArticle
    let emphasized: Bool

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.feedThumbnailRadius, style: .continuous)
                        .fill(AppTheme.badgeBlueFill)

                    Image(systemName: article.category.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
                .frame(width: AppTheme.organizationsThumbnailSize, height: AppTheme.organizationsThumbnailSize)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        AppInfoChip(
                            title: article.category.title,
                            systemImage: article.category.systemImage,
                            tint: AppTheme.accentPrimary,
                            fill: AppTheme.badgeBlueFill,
                            size: .small
                        )

                        if article.isPinned {
                            AppInfoChip(
                                title: AppStrings.Guide.pinnedTitle,
                                systemImage: "pin.fill",
                                tint: AppTheme.accentPrimary,
                                fill: AppTheme.badgeBlueFill,
                                size: .small
                            )
                        }

                        GuideReviewBadge(state: article.reviewState, size: .small)
                    }

                    Text(article.title)
                        .font(emphasized ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(article.summary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.84))
                        .lineLimit(2)

                    if let sourceName = article.sourceName, !sourceName.isEmpty {
                        AppMetadataLine(title: sourceName, systemImage: "link")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [article.title, article.summary, article.category.title]

        if article.isPinned {
            parts.append(AppStrings.Guide.pinnedTitle)
        }

        if let sourceName = article.sourceName, !sourceName.isEmpty {
            parts.append(sourceName)
        }

        if let reviewLabel = article.reviewState.accessibilityLabel {
            parts.append(reviewLabel)
        }

        return parts.joined(separator: ", ")
    }
}
