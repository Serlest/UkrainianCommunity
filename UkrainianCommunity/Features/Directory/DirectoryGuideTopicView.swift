import SwiftUI

struct DirectoryGuideTopicView: View {
    let categoryID: String
    let topic: DirectoryTopic
    let guide: DirectoryGuide
    @Binding var selectedFederalState: AustrianFederalState?
    let feedbackRepository: FeedbackRepository
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                    DirectoryPageHeading(title: topic.title.value(for: language),
                                         summary: guide.cardSummary.value(for: language))
                    Text(guide.introduction.value(for: language))
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    DirectoryTopicOutlineView(
                        titles: guide.sections.map { $0.title.value(for: language) },
                        language: language
                    ) { index in
                        withAnimation(.easeInOut) { proxy.scrollTo(guide.sections[index].id, anchor: .top) }
                    }

                    ForEach(guide.sections) { section in
                        DirectoryGuideSectionCard(section: section, language: language)
                            .id(section.id)
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

                    DirectoryFeedbackView(kind: .correction(categoryID: categoryID, topicID: topic.id, title: topic.title.value(for: language)), repository: feedbackRepository)

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
        }
        .background(AppBackgroundView())
        .navigationTitle(topic.title.value(for: language))
        .navigationBarTitleDisplayMode(.inline)
    }
}
