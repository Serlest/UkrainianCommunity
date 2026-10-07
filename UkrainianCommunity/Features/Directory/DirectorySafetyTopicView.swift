import SwiftUI

struct DirectorySafetyTopicView: View {
    let topic: DirectoryTopic
    let guide: SafetyGuide
    @Binding var selectedFederalState: AustrianFederalState?
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                    DirectoryPageHeading(title: topic.title.value(for: language),
                                         summary: guide.summary.value(for: language))

                    DirectoryTopicOutlineView(
                        titles: guide.sections.map { $0.title.value(for: language) },
                        language: language
                    ) { index in
                        withAnimation(.easeInOut) { proxy.scrollTo(guide.sections[index].id, anchor: .top) }
                    }

                    ForEach(guide.sections) { section in
                        SafetyInfoCard(
                            title: section.title.value(for: language), symbol: section.symbol
                        ) {
                            DirectoryGuideBodyView(text: section.body.value(for: language))
                            ForEach(section.contacts) { contact in
                                SafetyCallButton(contact: contact, language: language)
                            }
                        }
                        .id(section.id)
                    }
                    if DirectoryRegionalContent.applies(categoryID: "safety", topicID: topic.id) {
                        DirectoryRegionalSectionsView(
                            categoryID: "safety", topicID: topic.id,
                            selectedFederalState: $selectedFederalState, language: language
                        )
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
        }
        .background(AppBackgroundView())
        .navigationTitle(topic.title.value(for: language))
        .navigationBarTitleDisplayMode(.inline)
    }
}
