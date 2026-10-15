import SwiftUI

nonisolated enum DirectoryRoute: Hashable {
    case manage
    case edit(String)
    case editTopic(categoryID: String, topicID: String)
    case create(DirectoryManagedCategory.Placement)
    case category(String)
    case topic(categoryID: String, topicID: String)

    static func visiblePrefix(_ path: [DirectoryRoute], categories: [DirectoryCategory]) -> [DirectoryRoute] {
        let firstUnavailable = path.firstIndex { route in
            switch route {
            case let .category(id):
                !categories.contains { $0.id == id }
            case let .topic(categoryID, topicID):
                !categories.contains { category in
                    category.id == categoryID && category.topics.contains { $0.id == topicID }
                }
            case .manage, .edit, .editTopic, .create:
                false
            }
        }
        return firstUnavailable.map { Array(path.prefix($0)) } ?? path
    }
}

struct DirectoryCategoryView: View {
    @EnvironmentObject private var contentStore: DirectoryContentStore
    let category: DirectoryCategory
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                Image(systemName: category.symbol)
                    .font(.system(size: 37))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .padding(18)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)

                Text(category.title.value(for: language))
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text(category.summary.value(for: language))
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                DirectorySyncNoticeView(language: language)

                Text(DirectoryStrings.preparing)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 12))

                Text(DirectoryStrings.inCategory)
                    .font(.title3.bold())
                    .padding(.top, 8)

                ForEach(category.topics) { topic in
                    NavigationLink(value: DirectoryRoute.topic(categoryID: category.id, topicID: topic.id)) {
                        HStack(spacing: 12) {
                            Text(topic.title.value(for: language))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                        }
                        .padding(16)
                        .appGlassCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("directory.topic.\(topic.id)")
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.homeSectionSpacing)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
            .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
        }
        .background(AppBackgroundView())
        .navigationTitle(category.title.value(for: language))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if contentStore.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: DirectoryRoute.edit(category.id)) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }
}

struct DirectoryTopicView: View {
    let topic: DirectoryTopic
    let categoryID: String
    let feedbackRepository: FeedbackRepository
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .padding(20)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)
                Text(topic.title.value(for: language))
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                DirectorySyncNoticeView(language: language)
                AppGlassCard {
                    Text(DirectoryStrings.topicPending)
                        .font(.headline)
                    Text(DirectoryStrings.topicPendingDetail)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.homeSectionSpacing)
            .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
        }
        .background(AppBackgroundView())
        .navigationTitle(topic.title.value(for: language))
        .navigationBarTitleDisplayMode(.inline)
    }
}
