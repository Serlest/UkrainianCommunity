import SwiftUI

struct GuideSourceLinkRow: View {
    let link: GuideSourceLink

    var body: some View {
        if let url = URL(string: link.url) {
            Link(destination: url) {
                rowContent(accessory: externalLinkIcon)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(link.title)
        } else {
            rowContent(accessory: fallbackLinkIcon)
        }
    }

    private func rowContent<Accessory: View>(accessory: Accessory) -> some View {
        DetailActionRow {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(link.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if link.isOfficial {
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

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } trailingContent: {
            accessory
        }
    }

    private var subtitle: String {
        [link.sourceName, link.url]
            .compactMap { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var externalLinkIcon: some View {
        Image(systemName: "arrow.up.right.square")
            .foregroundStyle(AppTheme.accentPrimary)
    }

    private var fallbackLinkIcon: some View {
        Image(systemName: "link")
            .foregroundStyle(AppTheme.textSecondary)
    }
}
