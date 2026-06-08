import SwiftUI

struct DashboardSectionHeader<TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailingContent: TrailingContent

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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            SectionHeaderBlock(title: title, subtitle: subtitle)

            trailingContent
        }
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
        LazyVStack(spacing: spacing) {
            ForEach(items) { item in
                rowContent(item)
                    .onAppear {
                        onItemAppear(item)
                    }
            }
        }
    }
}

struct AppEventDateBlock: View {
    let date: Date
    let calendar: Calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(date: Date, calendar: Calendar = .current) {
        self.date = date
        self.calendar = calendar
    }

    var body: some View {
        VStack(spacing: 3) {
            VStack(spacing: 1) {
                Text(dayText)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .lineLimit(1)

                Text(monthText.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.accentDestructive)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: AppTheme.eventsDateRailWidth, height: 52)
            .background(
                reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
            )
            .background {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
            )

            Text(weekdayText.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.62))
                .lineLimit(1)
        }
        .frame(width: AppTheme.eventsDateRailWidth)
    }

    private var dayText: String {
        "\(calendar.component(.day, from: date))"
    }

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
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
    }
}

struct AppMetadataLine: View {
    let title: String
    let systemImage: String
    let tint: Color

    init(title: String, systemImage: String, tint: Color = AppTheme.textSecondary) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}

struct AdaptiveCardGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    @ViewBuilder let content: (Data.Element) -> Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: horizontalSizeClass == .regular ? 2 : 1)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
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
            HStack {
                Text(label)
                Spacer()
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accentPrimary)
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
        tint: Color = AppTheme.accentPrimary,
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
                    .foregroundStyle(tint == AppTheme.accentDestructive ? tint : AppTheme.textPrimary)
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
