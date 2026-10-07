import SwiftUI

struct DirectoryGuideTopicView: View {
    let categoryID: String
    let topic: DirectoryTopic
    let guide: DirectoryGuide
    @Binding var selectedFederalState: AustrianFederalState?
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                Text(topic.title.value(for: language))
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Text(guide.introduction.value(for: language))
                    .foregroundStyle(AppTheme.textSecondary)

                ForEach(guide.sections) { section in
                    DirectoryGuideSectionCard(section: section, language: language)
                }

                if DirectoryRegionalContent.applies(categoryID: categoryID, topicID: topic.id) {
                    DirectoryRegionalSectionsView(
                        categoryID: categoryID, topicID: topic.id,
                        selectedFederalState: $selectedFederalState,
                        language: language
                    )
                }

                if categoryID == "first-steps" {
                    NavigationLink(value: DirectoryRoute.category("registration")) {
                        Label(DirectoryText(ukrainian: "Детально про реєстрацію", german: "Mehr zur Anmeldung").value(for: language),
                              systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .appGlassCard()
                    }
                    .buttonStyle(.plain)
                }

                DirectorySourceListView(
                    sources: guide.sources,
                    language: language,
                    checkedOn: DirectoryGuideCatalog.checkedOn
                )
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
