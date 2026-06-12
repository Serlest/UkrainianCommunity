import SwiftUI

struct OwnerAnalyticsMetricTile: View {
    let title: String
    let value: Int
    var previousValue: Int? = nil
    let systemImage: String
    var accentStyle: Bool = false

    var body: some View {
        AppGlassCard(padding: 14, spacing: 8, shadowRadius: 8, shadowY: 4) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer(minLength: 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(value.formatted())
                        .font((accentStyle ? Font.title2 : Font.title3).weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let deltaPresentation {
                        Label(deltaPresentation.text, systemImage: deltaPresentation.systemImage)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(deltaPresentation.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }
            }
        }
    }

    private var deltaPresentation: OwnerAnalyticsDeltaPresentation? {
        guard let previousValue, previousValue > 0 else { return nil }

        let delta = value - previousValue
        guard delta != 0 else {
            return OwnerAnalyticsDeltaPresentation(
                text: AppStrings.OwnerAnalytics.deltaNoChange,
                systemImage: "checkmark",
                color: AppTheme.textSecondary
            )
        }

        let percentage = Double(delta) / Double(previousValue)
        let formattedPercentage = percentage.formatted(.percent.precision(.fractionLength(0)))
        return OwnerAnalyticsDeltaPresentation(
            text: AppStrings.OwnerAnalytics.deltaVsPreviousPeriod(formattedPercentage),
            systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right",
            color: delta > 0 ? AppTheme.accentPrimary : AppTheme.accentDestructive
        )
    }
}

private struct OwnerAnalyticsDeltaPresentation {
    let text: String
    let systemImage: String
    let color: Color
}

struct OwnerAnalyticsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        AppGlassCard(spacing: AppTheme.eventsMetadataSpacing) {
            SectionHeaderBlock(title: title, subtitle: subtitle)
            content
        }
    }
}

struct OwnerAnalyticsInlineEmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OwnerAnalyticsShowMoreButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct OwnerAnalyticsContentRow: View {
    let item: AnalyticsTopContentItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rankBadge

            VStack(alignment: .leading, spacing: 6) {
                Text(item.analyticsDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                metadataText
            }

            Spacer(minLength: 10)

            trailingValue(item.viewCount, label: AppStrings.OwnerAnalytics.views)
        }
        .padding(.vertical, 6)
    }

    private var rankBadge: some View {
        Text("#\(item.rank)")
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.accentPrimary)
            .frame(width: 34, height: 34)
            .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var metadataText: some View {
        if item.analyticsMetadataText.isEmpty {
            EmptyView()
        } else {
            Text(item.analyticsMetadataText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OwnerAnalyticsRegionRow: View {
    let row: OwnerAnalyticsRegionRowModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if !row.breakdownLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(row.breakdownLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 10)

            trailingValue(row.viewCount, label: AppStrings.OwnerAnalytics.views)
        }
        .padding(.vertical, 6)
    }
}

struct OwnerAnalyticsFederalStateUserRow: View {
    let row: OwnerAnalyticsFederalStateUserRowModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(AppStrings.FederalStates.title(for: row.federalState))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 10)

            trailingValue(row.userCount, label: AppStrings.OwnerAnalytics.users)
        }
        .padding(.vertical, 6)
    }
}

@ViewBuilder
private func trailingValue(_ value: Int, label: String) -> some View {
    VStack(alignment: .trailing, spacing: 2) {
        Text(value.formatted())
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)

        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
    }
}

extension AnalyticsTopContentItem {
    var analyticsDisplayTitle: String {
        guard !title.isAnalyticsUnavailableTitle(comparedTo: contentID) else {
            return AppStrings.OwnerAnalytics.titleUnavailable
        }

        return title
    }

    var analyticsMetadataText: String {
        var metadata = [contentType.analyticsTitle]

        if let regionTitle = analyticsRegionTitle {
            metadata.append(regionTitle)
        }

        if let organizationName, !organizationName.isAnalyticsUnavailableTitle(comparedTo: organizationID ?? "") {
            metadata.append(organizationName)
        }

        return metadata.joined(separator: " · ")
    }

    var analyticsRegionTitle: String? {
        if let federalState {
            return AppStrings.FederalStates.title(for: federalState)
        }

        guard let regionScope else { return nil }

        switch regionScope {
        case .austria:
            return AppStrings.OwnerAnalytics.regionAustria
        case .federalState:
            return AppStrings.OwnerAnalytics.regionFederalState
        case .city:
            return AppStrings.OwnerAnalytics.regionCity
        }
    }
}

extension AnalyticsContentType {
    var analyticsTitle: String {
        switch self {
        case .news:
            AppStrings.OwnerAnalytics.contentTypeNews
        case .event:
            AppStrings.OwnerAnalytics.contentTypeEvent
        case .organization:
            AppStrings.OwnerAnalytics.contentTypeOrganization
        case .guideArticle:
            AppStrings.OwnerAnalytics.contentTypeGuideMaterial
        }
    }
}

extension AnalyticsMetricType {
    var analyticsTitle: String {
        switch self {
        case .totalViews:
            AppStrings.OwnerAnalytics.totalViews
        case .newsViews:
            AppStrings.OwnerAnalytics.newsViews
        case .eventViews:
            AppStrings.OwnerAnalytics.eventViews
        case .organizationViews:
            AppStrings.OwnerAnalytics.organizationViews
        case .guideArticleViews:
            AppStrings.OwnerAnalytics.guideViews
        case .activeRegions:
            AppStrings.OwnerAnalytics.activeRegions
        case .totalLikes:
            AppStrings.OwnerAnalytics.totalLikes
        case .totalBookmarks:
            AppStrings.OwnerAnalytics.totalBookmarks
        case .eventRegistrations:
            AppStrings.OwnerAnalytics.eventRegistrations
        case .cancelledEventRegistrations:
            AppStrings.OwnerAnalytics.cancelledEventRegistrations
        case .organizationFollows:
            AppStrings.OwnerAnalytics.organizationFollows
        case .organizationUnfollows:
            AppStrings.OwnerAnalytics.organizationUnfollows
        }
    }

    var systemImage: String {
        switch self {
        case .totalViews:
            "eye"
        case .newsViews:
            "newspaper"
        case .eventViews:
            "calendar"
        case .organizationViews:
            "building.2"
        case .guideArticleViews:
            "book.closed"
        case .activeRegions:
            "map"
        case .totalLikes:
            "heart"
        case .totalBookmarks:
            "bookmark"
        case .eventRegistrations:
            "checkmark.circle"
        case .cancelledEventRegistrations:
            "xmark.circle"
        case .organizationFollows:
            "person.crop.circle.badge.plus"
        case .organizationUnfollows:
            "person.crop.circle.badge.minus"
        }
    }
}

extension String {
    func isAnalyticsUnavailableTitle(comparedTo contentID: String) -> Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return true
        }

        if !contentID.isEmpty && trimmed == contentID {
            return true
        }

        return trimmed.range(
            of: #"^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$"#,
            options: .regularExpression
        ) != nil
    }
}
