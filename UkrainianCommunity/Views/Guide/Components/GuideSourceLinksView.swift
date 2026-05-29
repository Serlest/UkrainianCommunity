import SwiftUI

struct GuideSourceLinksView: View {
    let links: [GuideSourceLink]
    let legacyURL: String?

    var body: some View {
        if !links.isEmpty {
            DetailCard {
                ForEach(links) { link in
                    GuideSourceLinkRow(link: link)
                }
            }
        } else if let legacyURL,
                  let url = URL(string: legacyURL) {
            DetailCard {
                Link(destination: url) {
                    DetailActionRow {
                        sourceText(title: AppStrings.Guide.officialSource, subtitle: legacyURL)
                    } trailingContent: {
                        sourceAccessory
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.Guide.officialSource)
            }
        }
    }

    private func sourceText(title: String, subtitle: String?, isOfficial: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sourceAccessory: some View {
        Image(systemName: "arrow.up.right.square")
            .foregroundStyle(AppTheme.accentPrimary)
    }
}
