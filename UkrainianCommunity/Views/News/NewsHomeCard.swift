import SwiftUI

struct NewsHomeCard: View {
    let post: NewsPost
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SoftContentCard(padding: AppTheme.homeFeedCardPadding, shadowRadius: 0, shadowY: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacing) {
                    HStack(alignment: .top, spacing: AppTheme.compactCardInnerSpacing) {
                        thumbnail
                        Spacer(minLength: 0)
                        dateLabel
                    }
                    details
                }
            } else {
                HStack(alignment: .center, spacing: AppTheme.compactCardInnerSpacing) {
                    thumbnail
                    details
                    Spacer(minLength: 2)
                    dateLabel
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var thumbnail: some View {
        AppFeedThumbnail(imageURL: post.imageURL, fallbackSystemImage: "newspaper",
                         tint: AppTheme.accentSuccessForeground, fill: AppTheme.badgeGreenFill,
                         size: thumbnailSize, source: "NewsHomeCard")
            .frame(width: thumbnailSize, height: thumbnailSize)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            AppInfoChip(title: AppStrings.News.title.uppercased(), systemImage: "newspaper",
                        tint: AppTheme.accentSuccessForeground, fill: AppTheme.badgeGreenFill,
                        size: .small, fallbackUsesMaterial: false, shadowRadius: 0, shadowY: 0)

            Text(post.localizedTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if !post.localizedSubtitle.isEmpty {
                Text(post.localizedSubtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(publisherText, systemImage: "person.crop.circle")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateLabel: some View {
        Text(NewsHomeRelativeDate.string(for: post.publishedAt))
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 1)
    }

    private var thumbnailSize: CGFloat { AppTheme.feedThumbnailSize + 14 }

    private var publisherText: String {
        let sourceName = normalizedName(post.source.displayOrganizationName) ?? AppStrings.News.missingOrganization
        guard let author = normalizedName(post.authorName) else { return sourceName }
        return "\(author) · \(sourceName)"
    }

    private func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == AppStrings.NewsEditor.authorFallback ? nil : name
    }

    private var accessibilitySummary: String {
        [AppStrings.News.title, post.localizedTitle, post.localizedSubtitle, publisherText,
         post.city, "\(post.likeCount) \(AppStrings.Common.likes)"]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

@MainActor
private enum NewsHomeRelativeDate {
    private static let formatter = RelativeDateTimeFormatter()
    private static var configuredLocaleIdentifier: String?

    static func string(for date: Date, relativeTo referenceDate: Date = Date()) -> String {
        let locale = LocalizationStore.locale
        if configuredLocaleIdentifier != locale.identifier {
            formatter.locale = locale
            formatter.unitsStyle = .short
            configuredLocaleIdentifier = locale.identifier
        }
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
