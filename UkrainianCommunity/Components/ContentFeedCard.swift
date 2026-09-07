import SwiftUI
import UIKit

@MainActor
private enum HomeFeedRelativeDateFormatter {
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

struct ContentFeedCard: View {
    let item: HomeFeedItem
    var previewImage: UIImage? = nil
    var includesFooter = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardBody
            if includesFooter { ContentCardMetadataFooter(item: item) }
        }
    }

    private var cardBody: some View {
        SoftContentCard(
            padding: AppTheme.homeFeedCardPadding,
            shadowRadius: 0,
            shadowY: 0
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if dynamicTypeSize.isAccessibilitySize {
                    cardDetails
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        leadingMedia
                        cardDetails
                    }
                }
                if item.itemType == .event {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let publisherText { publisherLine(title: publisherText) }
                            metadataLine
                            if let secondaryMetadataText {
                                AppMetadataLine(title: secondaryMetadataText, systemImage: "mappin.and.ellipse")
                            }
                        }
                        Spacer(minLength: 0)
                        if let eventStartDate = item.eventStartDate {
                            HomeEventDateBadge(date: eventStartDate)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var cardDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(itemTypeTitle).font(.caption.weight(.semibold)).foregroundStyle(itemTypeTint)
            } else { typeChip }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)

            if item.itemType == .organization {
                organizationMetadataLine
                    .padding(.top, 1)
            }

            if shouldShowPreview, !item.summary.isEmpty {
                Text(item.summary)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if item.itemType == .news {
                if let publisherText { publisherLine(title: publisherText) }
                timestampText
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var leadingMedia: some View {
        if let previewImage {
            Image(uiImage: previewImage).resizable().scaledToFill()
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius))
                .accessibilityHidden(true)
        } else {
        AppFeedThumbnail(
            imageURL: item.imageURL,
            fallbackSystemImage: itemTypeSystemImage,
            tint: itemTypeTint,
            fill: itemTypeFill,
            size: thumbnailSize,
            source: "ContentFeedCard"
        )
        .frame(width: thumbnailSize, height: thumbnailSize, alignment: .center)
        }
    }

    private var typeChip: some View {
        AppInfoChip(
            title: itemTypeTitle.uppercased(),
            systemImage: itemTypeSystemImage,
            tint: itemTypeTint,
            fill: itemTypeFill,
            size: .small,
            fallbackUsesMaterial: false,
            shadowRadius: 0,
            shadowY: 0
        )
    }

    private var timestampText: some View {
        Text(publishedDateText)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func publisherLine(title: String) -> some View {
        Label(title, systemImage: "person.crop.circle")
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var metadataLine: some View {
        if let start = item.eventStartDate, let end = item.eventEndDate,
           let schedule = EventMultiDaySchedule(startDate: start, endDate: end, isAllDay: item.eventIsAllDay) {
            EventMultiDayScheduleLabel(schedule: schedule)
        } else {
            AppMetadataLine(title: primaryMetadataText, systemImage: primaryMetadataIcon)
        }
    }

    private var organizationMetadataLine: some View {
        Text(organizationMetadataText)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var itemTypeTitle: String {
        switch item.itemType {
        case .news:
            AppStrings.News.title
        case .event:
            AppStrings.Tabs.events
        case .organization:
            AppStrings.Tabs.organizations
        }
    }

    private var itemTypeSystemImage: String {
        switch item.itemType {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .organization:
            "building.2"
        }
    }

    private var itemTypeTint: Color {
        switch item.itemType {
        case .news:
            AppTheme.accentSuccessForeground
        case .event:
            AppTheme.accentPrimaryForeground
        case .organization:
            AppTheme.accentIndigoForeground
        }
    }

    private var itemTypeFill: Color {
        switch item.itemType {
        case .news:
            AppTheme.badgeGreenFill
        case .event:
            AppTheme.badgeBlueFill
        case .organization:
            AppTheme.badgePurpleFill
        }
    }

    private var thumbnailSize: CGFloat {
        64
    }

    private var shouldShowPreview: Bool {
        item.itemType == .news || item.itemType == .event
    }

    private var publishedDateText: String {
        HomeFeedRelativeDateFormatter.string(for: item.publishedAt)
    }

    private var primaryMetadataText: String {
        if item.itemType == .event, let eventStartDate = item.eventStartDate {
            return LocalizationStore.timeRangeString(startDate: eventStartDate, endDate: item.eventEndDate, isAllDay: item.eventIsAllDay)
        }

        if let city = item.city, !city.isEmpty {
            return city
        }

        if let organizationName = item.organizationName, !organizationName.isEmpty {
            return organizationName
        }

        return sourceTypeTitle
    }

    private var primaryMetadataIcon: String {
        item.itemType == .event ? "clock" : "mappin.and.ellipse"
    }

    private var organizationMetadataText: String {
        [
            item.city,
            subscriberCountText
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " • ")
    }

    private var organizationRegionText: String? {
        if let federalState = item.federalState {
            return AppStrings.FederalStates.title(for: federalState)
        }

        if let city = item.city, !city.isEmpty {
            return city
        }

        return nil
    }

    private var organizationCategoryText: String? {
        guard let organizationType = item.organizationType,
              let category = OrganizationEditorCategory(rawValue: organizationType) else {
            return AppStrings.Organizations.detailBadge
        }

        return category.title
    }

    private var subscriberCountText: String {
        let count = item.subscriberCount
        let mod10 = count % 10
        let mod100 = count % 100
        let suffix: String

        if mod10 == 1 && mod100 != 11 {
            suffix = AppStrings.Home.subscriberSuffixOne
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            suffix = AppStrings.Home.subscriberSuffixFew
        } else {
            suffix = AppStrings.Home.subscriberSuffixMany
        }

        return "\(count) \(suffix)"
    }

    private var secondaryMetadataText: String? {
        guard item.itemType == .event else { return nil }
        if let city = item.city, !city.isEmpty { return city }
        return item.eventVenue?.isEmpty == false ? item.eventVenue : nil
    }

    private var publisherText: String? {
        guard item.itemType == .news || item.itemType == .event else { return nil }

        let authorName = normalizedPublisherName(item.authorName)
        let sourceName = normalizedPublisherName(item.organizationName) ?? (item.itemType == .news ? AppStrings.News.missingOrganization : AppStrings.Home.brandTitle)

        guard let authorName else {
            return sourceName
        }

        return "\(authorName) · \(sourceName)"
    }

    private func normalizedPublisherName(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != AppStrings.NewsEditor.authorFallback else {
            return nil
        }

        return trimmed
    }

    private var sourceTypeTitle: String {
        switch item.sourceType {
        case .app:
            AppStrings.Common.app
        case .organization:
            AppStrings.Tabs.organizations
        }
    }

    private var accessibilitySummary: String {
        var parts = [itemTypeTitle, item.title]

        if !item.summary.isEmpty {
            parts.append(item.summary)
        }

        if let publisherText {
            parts.append(publisherText)
        }

        parts.append(primaryMetadataText)
        if let title = item.eventRegistrationTitle { parts.append(title) }

        if item.itemType == .organization {
            parts.append(subscriberCountText)
        } else {
            parts.append("\(item.likeCount) \(AppStrings.Common.likes)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct HomeEventDateBadge: View {
    let date: Date
    let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(date: Date, calendar: Calendar = .current) {
        self.date = date
        self.calendar = calendar
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(weekdayText), \(dayText) \(monthText)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                            .strokeBorder(AppTheme.borderSubtle)
                    )
            } else {
                VStack(spacing: 3) {
                    VStack(spacing: 1) {
                        Text(dayText)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimaryForeground)

                        Text(monthText.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.accentDestructiveForeground)
                    }
                    .frame(width: AppTheme.homeFeedDateBadgeSize, height: AppTheme.homeFeedDateBadgeSize)
                    .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                            .strokeBorder(AppTheme.borderSubtle)
                    )
                    .shadow(color: AppTheme.textPrimary.opacity(0.06), radius: 5, y: 2)

                    Text(weekdayText.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: AppTheme.homeFeedDateBadgeSize)
            }
        }
    }

    private var dayText: String {
        "\(calendar.component(.day, from: date))"
    }

    private var weekdayText: String {
        LocalizationStore.dateString(from: date, localizedTemplate: "EEE")
    }

    private var monthText: String {
        LocalizationStore.dateString(from: date, localizedTemplate: "MMM")
    }
}

