import SwiftUI

struct DashboardSectionHeader<TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailingContent: TrailingContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingContent = trailingContent()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeaderBlock(title: title, subtitle: subtitle)
                    trailingContent
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    SectionHeaderBlock(title: title, subtitle: subtitle)
                    trailingContent
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DashboardSectionHeader where TrailingContent == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct DashboardFeedContainer<Data: RandomAccessCollection, RowContent: View>: View where Data.Element: Identifiable {
    let items: Data
    let spacing: CGFloat
    let onItemAppear: (Data.Element) -> Void
    @ViewBuilder let rowContent: (Data.Element) -> RowContent

    init(
        items: Data,
        spacing: CGFloat = 14,
        onItemAppear: @escaping (Data.Element) -> Void = { _ in },
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) {
        self.items = items
        self.spacing = spacing
        self.onItemAppear = onItemAppear
        self.rowContent = rowContent
    }

    var body: some View {
        AppAdaptiveGrid(spacing: spacing) {
            ForEach(items) { item in
                rowContent(item)
                    .onAppear {
                        onItemAppear(item)
                    }
            }
        }
    }
}

struct AppAdaptiveGrid<Content: View>: View {
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    let spacing: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        minimumWidth: CGFloat = AppTheme.adaptiveCardMinimumWidth,
        maximumWidth: CGFloat = AppTheme.adaptiveCardMaximumWidth,
        spacing: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        self.spacing = spacing
        self.content = content()
    }

    private var columns: [GridItem] {
        guard !dynamicTypeSize.isAccessibilitySize else {
            return [GridItem(.flexible())]
        }

        return [GridItem(
            .adaptive(minimum: minimumWidth, maximum: maximumWidth),
            spacing: spacing
        )]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            content
        }
    }
}

struct AppEventDateBlock: View {
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
                dateSurface {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(dayText)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimaryForeground)

                        Text(monthText.uppercased())
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.accentDestructiveForeground)

                        Text(weekdayText.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 3) {
                    dateSurface {
                        VStack(spacing: 1) {
                            Text(dayText)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppTheme.accentPrimaryForeground)

                            Text(monthText.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(AppTheme.accentDestructiveForeground)
                        }
                        .frame(width: AppTheme.eventsDateRailWidth, height: 52)
                    }

                    Text(weekdayText.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(width: AppTheme.eventsDateRailWidth)
            }
        }
    }

    private func dateSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .appGlassSurface(
                cornerRadius: AppTheme.cardRadius,
                usesNativeGlass: false,
                fallbackRole: .control,
                shadowRadius: 0,
                shadowY: 0
            )
    }

    private var dayText: String {
        "\(calendar.component(.day, from: date))"
    }

    private var monthText: String {
        LocalizationStore.dateString(from: date, localizedTemplate: "MMM")
    }

    private var weekdayText: String {
        LocalizationStore.dateString(from: date, localizedTemplate: "EEE")
    }
}

struct AppFeedThumbnail: View {
    let imageURL: String?
    let fallbackSystemImage: String
    let tint: Color
    let fill: Color
    let size: CGFloat
    let cornerRadius: CGFloat
    let source: String

    init(
        imageURL: String?,
        fallbackSystemImage: String,
        tint: Color,
        fill: Color,
        size: CGFloat = AppTheme.feedThumbnailSize,
        cornerRadius: CGFloat = AppTheme.feedThumbnailRadius,
        source: String = "AppFeedThumbnail"
    ) {
        self.imageURL = imageURL
        self.fallbackSystemImage = fallbackSystemImage
        self.tint = tint
        self.fill = fill
        self.size = size
        self.cornerRadius = cornerRadius
        self.source = source
    }

    var body: some View {
        Group {
            if imageURL != nil {
                RemoteCardImage(
                    imageURL: imageURL,
                    height: size,
                    cornerRadius: cornerRadius,
                    source: source,
                    isDecorative: true
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)

                    Image(systemName: fallbackSystemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct AppMetadataLine: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, systemImage: String, tint: Color = AppTheme.textSecondary) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AdaptiveCardGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    @ViewBuilder let content: (Data.Element) -> Content

    var body: some View {
        AppAdaptiveGrid {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(label)
                    Spacer()
                    Text(value)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                    Text(value)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accentPrimaryForeground)
        }
        .font(.subheadline)
    }
}

struct SectionHeaderBlock: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ContentMetadataPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(AppTheme.surfaceSecondary)
            )
    }
}

enum AppNavigationRowAccessory {
    case chevron
    case none
}

struct AppNavigationRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let accessory: AppNavigationRowAccessory

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = AppTheme.accentPrimaryForeground,
        accessory: AppNavigationRowAccessory = .chevron
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint == AppTheme.accentDestructiveForeground ? tint : AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if accessory == .chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
