import SwiftUI

struct DirectoryGuideCategoryView: View {
    let category: DirectoryCategory
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                Image(systemName: category.symbol)
                    .font(.system(size: 36))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .padding(18)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)
                Text(category.title.value(for: language))
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text(category.summary.value(for: language))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(DirectoryStrings.inCategory)
                    .font(.title3.bold())
                ForEach(category.topics) { topic in
                    if let guide = DirectoryGuideCatalog.guide(categoryID: category.id, topicID: topic.id) {
                        NavigationLink(value: DirectoryRoute.topic(categoryID: category.id, topicID: topic.id)) {
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: guide.sections.first?.symbol ?? category.symbol)
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                                    .frame(width: 32)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(topic.title.value(for: language))
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text(guide.cardSummary.value(for: language))
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(16)
                            .appGlassCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("directory.topic.\(topic.id)")
                    }
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
