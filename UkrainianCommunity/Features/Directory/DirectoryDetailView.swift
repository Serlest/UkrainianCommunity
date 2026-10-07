import SwiftUI

enum DirectoryRoute: Hashable {
    case category(String)
    case topic(categoryID: String, topicID: String)
}

struct DirectoryCategoryView: View {
    let category: DirectoryCategory
    let feedbackRepository: FeedbackRepository
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

                Text(DirectoryStrings.preparing)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 12))

                DirectoryFeedbackView(kind: .question(categoryID: category.id, title: category.title.value(for: language)), repository: feedbackRepository)

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
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
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
                DirectoryFeedbackView(kind: .question(categoryID: categoryID, title: topic.title.value(for: language)), repository: feedbackRepository)
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
