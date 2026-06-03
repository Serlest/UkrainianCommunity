import SwiftUI

struct GuideSourceLinksView: View {
    let links: [GuideSourceLink]
    let legacyURL: String?
    var highlightsPrimarySource: Bool = false

    private var officialLinks: [GuideSourceLink] {
        links.filter(\.isOfficial)
    }

    private var supportingLinks: [GuideSourceLink] {
        links.filter { !$0.isOfficial }
    }

    var body: some View {
        if !links.isEmpty {
            DetailCard {
                header(
                    title: AppStrings.Guide.sourceSectionTitle,
                    subtitle: sourcesSubtitle
                )

                if !officialLinks.isEmpty && !highlightsPrimarySource {
                    header(
                        title: AppStrings.Guide.sourceSectionPrimaryTitle,
                        subtitle: AppStrings.Guide.sourceSectionPrimarySubtitle
                    )

                    ForEach(officialLinks) { link in
                        GuideSourceLinkRow(link: link)
                    }
                }

                if !supportingLinks.isEmpty {
                    header(
                        title: AppStrings.Guide.sourceSectionSupportingTitle,
                        subtitle: AppStrings.Guide.sourceSectionSupportingSubtitle
                    )

                    ForEach(supportingLinks) { link in
                        GuideSourceLinkRow(link: link)
                    }
                }
            }
        } else if let legacyURL,
                  let url = URL(string: legacyURL) {
            DetailCard {
                header(
                    title: AppStrings.Guide.sourceSectionTitle,
                    subtitle: AppStrings.Guide.sourceSectionSubtitle
                )

                header(
                    title: AppStrings.Guide.sourceSectionPrimaryTitle,
                    subtitle: AppStrings.Guide.sourceSectionPrimarySubtitle
                )

                Link(destination: url) {
                    DetailActionRow {
                        sourceText(title: AppStrings.Guide.officialSource, subtitle: legacyURL, isOfficial: true)
                    } trailingContent: {
                        sourceAccessory
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.Guide.officialSource)
            }
        }
    }

    private func header(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sourceText(title: String, subtitle: String?, isOfficial: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if isOfficial {
                    AppInfoChip(
                        title: AppStrings.Guide.officialSource,
                        systemImage: "checkmark.seal",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.badgeBlueFill,
                        size: .small
                    )
                    .opacity(0.95)
                }
            }

            Text(AppStrings.Guide.openOfficialSourceAction)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(AppStrings.Guide.opensExternalWebsiteHint)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.9))
        }
    }

    private var sourceAccessory: some View {
        Image(systemName: "arrow.up.right.square.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
    }

    private var sourcesSubtitle: String {
        if highlightsPrimarySource, !officialLinks.isEmpty {
            return AppStrings.Guide.sourceSectionSupportingSubtitle
        }

        return AppStrings.Guide.sourceSectionSubtitle
    }
}
