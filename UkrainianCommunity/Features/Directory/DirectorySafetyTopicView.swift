import SwiftUI

struct DirectorySafetyTopicView: View {
    let topic: DirectoryTopic
    let guide: SafetyGuide
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                Text(topic.title.value(for: language))
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text(guide.summary.value(for: language))
                    .foregroundStyle(AppTheme.textSecondary)

                ForEach(guide.sections) { section in
                    SafetyInfoCard(
                        title: section.title.value(for: language), symbol: section.symbol
                    ) {
                        Text(section.body.value(for: language))
                            .foregroundStyle(AppTheme.textSecondary)
                        ForEach(section.contacts) { contact in
                            SafetyCallButton(contact: contact, language: language)
                        }
                    }
                }
                DirectorySourceListView(
                    sources: guide.sources, language: language,
                    checkedOn: DirectorySafetyContent.reviewedOn)
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.homeSectionSpacing)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
            .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
        }
        .background(AppBackgroundView())
        .navigationTitle(topic.title.value(for: language))
        .navigationBarTitleDisplayMode(.inline)
    }
}
