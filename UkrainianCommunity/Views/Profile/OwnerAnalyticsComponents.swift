import Charts
import Foundation
import SwiftUI

enum OwnerAnalyticsDateFormatting {
    static let analyticsCalendar = AnalyticsFirestoreSchema.analyticsCalendar
    static let analyticsTimeZone = AnalyticsFirestoreSchema.analyticsTimeZone

    static func isSameAnalyticsDay(_ lhs: Date, _ rhs: Date) -> Bool {
        analyticsCalendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func analyticsDayText(_ date: Date, locale: Locale = LocalizationStore.locale) -> String {
        date.formatted(
            Date.FormatStyle(
                locale: locale,
                calendar: analyticsCalendar,
                timeZone: analyticsTimeZone
            )
            .day()
            .month(.abbreviated)
        )
    }

    static func relativeFreshnessText(
        _ date: Date,
        relativeTo referenceDate: Date = Date(),
        locale: Locale = LocalizationStore.locale
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func absoluteFreshnessText(
        _ date: Date,
        locale: Locale = LocalizationStore.locale,
        timeZone: TimeZone = .current
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                locale: locale,
                calendar: .current,
                timeZone: timeZone
            )
        )
    }
}

struct OwnerAnalyticsMetricTile: View {
    let title: String
    let value: Int
    var previousValue: Int? = nil
    let systemImage: String
    var accentStyle: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: 30, height: 30)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(OwnerAnalyticsFormatting.integer(value, locale: locale))
                    .font((accentStyle ? Font.title2 : Font.title3).weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if let deltaPresentation {
                    Label(deltaPresentation.text, systemImage: deltaPresentation.systemImage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(deltaPresentation.color)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(AppTheme.metricCardPadding)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(AppTheme.surfaceControl, in: RoundedRectangle(cornerRadius: AppTheme.rowCardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.rowCardCornerRadius, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
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
        let formattedPercentage = OwnerAnalyticsFormatting.percent(percentage, locale: locale)
        return OwnerAnalyticsDeltaPresentation(
            text: AppStrings.OwnerAnalytics.deltaVsPreviousPeriod(formattedPercentage),
            systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right",
            color: delta > 0 ? AppTheme.accentPrimaryForeground : AppTheme.accentDestructiveForeground
        )
    }

    private var accessibilityValue: String {
        [OwnerAnalyticsFormatting.integer(value, locale: locale), deltaPresentation?.text]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

struct OwnerAnalyticsTrendChart: View {
    let points: [OwnerAnalyticsTrendPoint]
    @Binding var selectedMetric: AnalyticsMetricType
    let metricOptions: [AnalyticsMetricType]
    @State private var selectedDate: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartHeader

            if let selectedPoint {
                Text(AppStrings.OwnerAnalytics.trendSelection(
                    metric: selectedMetric.analyticsTitle,
                    date: OwnerAnalyticsDateFormatting.analyticsDayText(selectedPoint.date, locale: locale),
                    value: selectedPoint.value
                ))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
            }

            Chart(points) { point in
                BarMark(
                    x: .value(AppStrings.OwnerAnalytics.date, point.date, unit: .day),
                    y: .value(selectedMetric.analyticsTitle, point.value)
                )
                .foregroundStyle(AppTheme.accentPrimaryForeground.gradient)
                .cornerRadius(3)
                .accessibilityLabel(OwnerAnalyticsDateFormatting.analyticsDayText(point.date, locale: locale))
                .accessibilityValue("\(selectedMetric.analyticsTitle), \(OwnerAnalyticsFormatting.integer(point.value, locale: locale))")

                if let selectedDate,
                   OwnerAnalyticsDateFormatting.isSameAnalyticsDay(point.date, selectedDate) {
                    RuleMark(x: .value(AppStrings.OwnerAnalytics.date, point.date, unit: .day))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .accessibilityHidden(true)
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(points.count, 6))) { value in
                    AxisGridLine().foregroundStyle(AppTheme.borderSubtle)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(OwnerAnalyticsDateFormatting.analyticsDayText(date, locale: locale))
                        }
                    }
                }
            }
            .environment(\.calendar, OwnerAnalyticsDateFormatting.analyticsCalendar)
            .environment(\.timeZone, OwnerAnalyticsDateFormatting.analyticsTimeZone)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 250 : 190)
            .accessibilityLabel(AppStrings.OwnerAnalytics.trendAccessibilityLabel)
            .accessibilityValue(chartAccessibilityValue)
            .accessibilityAdjustableAction(adjustSelection)
            .accessibilityIdentifier("ownerAnalytics.trendChart")
        }
        .onChange(of: selectedMetric) { _, _ in selectedDate = nil }
        .onChange(of: points) { _, updatedPoints in
            selectedDate = OwnerAnalyticsTrendSelection.normalizedDate(
                selectedDate,
                in: updatedPoints
            )
        }
    }

    @ViewBuilder
    private var chartHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                chartTitle
                metricPicker
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                chartTitle
                Spacer(minLength: 8)
                metricPicker
            }
        }
    }

    private var chartTitle: some View {
        Text(AppStrings.OwnerAnalytics.trendTitle)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
    }

    private var metricPicker: some View {
        Picker(AppStrings.OwnerAnalytics.trendMetricPicker, selection: $selectedMetric) {
            ForEach(metricOptions) { metric in
                Text(metric.analyticsTitle).tag(metric)
            }
        }
        .pickerStyle(.menu)
    }

    private var chartAccessibilityValue: String {
        guard let selectedPoint else { return selectedMetric.analyticsTitle }
        return [
            selectedMetric.analyticsTitle,
            OwnerAnalyticsDateFormatting.analyticsDayText(selectedPoint.date, locale: locale),
            OwnerAnalyticsFormatting.integer(selectedPoint.value, locale: locale)
        ].joined(separator: ", ")
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        let sortedPoints = points.sorted { $0.date < $1.date }
        guard !sortedPoints.isEmpty else { return }

        let currentIndex = selectedPoint.flatMap { selectedPoint in
            sortedPoints.firstIndex(where: { OwnerAnalyticsDateFormatting.isSameAnalyticsDay($0.date, selectedPoint.date) })
        }

        switch direction {
        case .increment:
            let nextIndex = min((currentIndex ?? -1) + 1, sortedPoints.count - 1)
            selectedDate = sortedPoints[nextIndex].date
        case .decrement:
            let nextIndex = max((currentIndex ?? sortedPoints.count) - 1, 0)
            selectedDate = sortedPoints[nextIndex].date
        @unknown default:
            break
        }
    }

    private var selectedPoint: OwnerAnalyticsTrendPoint? {
        OwnerAnalyticsTrendSelection.point(for: selectedDate, in: points)
    }
}

enum OwnerAnalyticsTrendSelection {
    static func normalizedDate(
        _ selectedDate: Date?,
        in points: [OwnerAnalyticsTrendPoint]
    ) -> Date? {
        point(for: selectedDate, in: points) == nil ? nil : selectedDate
    }

    static func point(
        for selectedDate: Date?,
        in points: [OwnerAnalyticsTrendPoint]
    ) -> OwnerAnalyticsTrendPoint? {
        guard let selectedDate else { return nil }
        return points.first {
            OwnerAnalyticsDateFormatting.isSameAnalyticsDay($0.date, selectedDate)
        }
    }
}

struct OwnerAnalyticsFreshnessLabel: View {
    let updatedAt: Date?
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Label(displayText(relativeTo: context.date), systemImage: "clock")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(relativeTo: context.date))
        }
    }

    private func displayText(relativeTo referenceDate: Date) -> String {
        guard let updatedAt else {
            return AppStrings.OwnerAnalytics.updateTimeUnavailable
        }
        return AppStrings.OwnerAnalytics.updatedAt(
            OwnerAnalyticsDateFormatting.relativeFreshnessText(
                updatedAt,
                relativeTo: referenceDate,
                locale: locale
            )
        )
    }

    private func accessibilityText(relativeTo referenceDate: Date) -> String {
        guard let updatedAt else { return displayText(relativeTo: referenceDate) }
        return [
            displayText(relativeTo: referenceDate),
            OwnerAnalyticsDateFormatting.absoluteFreshnessText(
                updatedAt,
                locale: locale,
                timeZone: timeZone
            )
        ].joined(separator: ", ")
    }
}

struct OwnerAnalyticsStaleDataBanner: View {
    let message: String
    let isRetrying: Bool
    let retryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineMessageCard(style: .error, message: message)
                .accessibilityElement(children: .combine)

            Button(action: retryAction) {
                Label(AppStrings.OwnerAnalytics.retry, systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: AppTheme.minimumInteractiveTarget)
            .disabled(isRetrying)
        }
    }
}

struct OwnerAnalyticsPartialDataBanner: View {
    let message: String

    var body: some View {
        InlineMessageCard(style: .info, message: message)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ownerAnalytics.partialData")
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
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppTheme.minimumInteractiveTarget)
        .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct OwnerAnalyticsContentRow: View {
    let item: AnalyticsTopContentItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        OwnerAnalyticsResponsiveValueRow(
            value: item.viewCount,
            label: AppStrings.OwnerAnalytics.views
        ) {
            rankBadge

            VStack(alignment: .leading, spacing: 6) {
                Text(item.analyticsDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                metadataText
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.analyticsDisplayTitle)
        .accessibilityValue([
            AppStrings.OwnerAnalytics.rank(OwnerAnalyticsFormatting.integer(item.rank, locale: locale)),
            AppStrings.OwnerAnalytics.metricValue(AppStrings.OwnerAnalytics.views, item.viewCount),
            item.analyticsMetadataText
        ].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private var rankBadge: some View {
        Text("#\(OwnerAnalyticsFormatting.integer(item.rank, locale: locale))")
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.accentPrimaryForeground)
            .padding(.horizontal, 8)
            .frame(minWidth: 34, minHeight: 34)
            .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private var metadataText: some View {
        if item.analyticsMetadataText.isEmpty {
            EmptyView()
        } else {
            Text(item.analyticsMetadataText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OwnerAnalyticsRegionRow: View {
    let row: OwnerAnalyticsRegionRowModel

    var body: some View {
        OwnerAnalyticsResponsiveValueRow(
            value: row.viewCount,
            label: AppStrings.OwnerAnalytics.views
        ) {
            Image(systemName: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !row.breakdownLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(row.breakdownLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(([AppStrings.OwnerAnalytics.metricValue(AppStrings.OwnerAnalytics.views, row.viewCount)] + row.breakdownLines).joined(separator: ", "))
        .accessibilityIdentifier("ownerAnalytics.region.\(row.id)")
    }
}

struct OwnerAnalyticsFederalStateUserRow: View {
    let row: OwnerAnalyticsFederalStateUserRowModel

    var body: some View {
        OwnerAnalyticsResponsiveValueRow(
            value: row.userCount,
            label: AppStrings.OwnerAnalytics.users
        ) {
            Image(systemName: "person.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            Text(AppStrings.FederalStates.title(for: row.federalState))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppStrings.FederalStates.title(for: row.federalState))
        .accessibilityValue(AppStrings.OwnerAnalytics.metricValue(AppStrings.OwnerAnalytics.users, row.userCount))
        .accessibilityIdentifier("ownerAnalytics.userRegion.\(row.federalState.rawValue)")
    }
}

struct OwnerAnalyticsResponsiveValueRow<Leading: View>: View {
    let value: Int
    let label: String
    @ViewBuilder let leading: Leading
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    init(
        value: Int,
        label: String,
        @ViewBuilder leading: () -> Leading
    ) {
        self.value = value
        self.label = label
        self.leading = leading()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        leading
                    }

                    trailingValue(alignment: .leading)
                        .padding(.leading, 46)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    leading
                    Spacer(minLength: 10)
                    trailingValue(alignment: .trailing)
                }
            }
        }
    }

    private func trailingValue(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(OwnerAnalyticsFormatting.integer(value, locale: locale))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        case .activeRegions:
            AppStrings.OwnerAnalytics.activeRegions
        case .newsLikes:
            AppStrings.OwnerAnalytics.newsLikes
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
        case .activeRegions:
            "map"
        case .newsLikes:
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
