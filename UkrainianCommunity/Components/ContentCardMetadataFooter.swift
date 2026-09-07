import SwiftUI

@MainActor
extension HomeFeedItem {
    var cardCategoryTitle: String {
        switch itemType {
        case .news: newsCategory.map(NewsBrowseStrings.topic) ?? AppStrings.News.title
        case .event: eventCategory?.title ?? AppStrings.Events.title
        case .organization:
            organizationType.flatMap(OrganizationEditorCategory.init(rawValue:))?.title
                ?? AppStrings.Organizations.detailBadge
        }
    }

    var cardRegionTitle: String? {
        if regionScope == .austria { return NewsBrowseStrings.text("austria") }
        if let federalState { return federalState.displayName }
        if regionScope == .city, let city, !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return city
        }
        // Missing geography is not evidence of nationwide coverage.
        return nil
    }
}

/// Kept outside the navigation link when the news topic is an independent action.
struct ContentCardMetadataFooter: View {
    let item: HomeFeedItem
    var selectNewsTopic: ((NewsCategory) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        category.fixedSize()
                        Spacer(minLength: 8)
                        region.fixedSize()
                    }
                    stacked
                }
            }
        }
        .frame(minHeight: AppTheme.minimumInteractiveTarget)
        .padding(.horizontal, AppTheme.homeFeedCardPadding)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("content.metadata.\(item.id)")
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            category
            HStack { Spacer(minLength: 0); region }
        }
    }

    @ViewBuilder private var category: some View {
        if let topic = item.newsCategory, let selectNewsTopic {
            Button { selectNewsTopic(topic) } label: { categoryLabel }
                .buttonStyle(.plain)

                .accessibilityIdentifier("home.news.topicLink.\(item.id)")
        } else {
            categoryLabel
        }
    }

    private var categoryLabel: some View {
        Label(item.cardCategoryTitle, systemImage: "tag")
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.accentPrimaryForeground)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var region: some View {
        if let title = item.cardRegionTitle {
            Text(title).font(.caption).foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
