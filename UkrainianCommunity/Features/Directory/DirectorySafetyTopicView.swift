import SwiftUI

struct DirectorySafetyTopicView: View {
    @EnvironmentObject private var contentStore: DirectoryContentStore
    let topic: DirectoryTopic
    let guide: SafetyGuide
    @Binding var selectedFederalState: AustrianFederalState?
    let feedbackRepository: FeedbackRepository
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                    DirectoryPageHeading(title: topic.title.value(for: language),
                                         summary: guide.summary.value(for: language),
                                         isArticle: true)
                    DirectorySyncNoticeView(language: language)

                    if guide.sections.count > 5 {
                        DirectoryTopicOutlineView(
                            titles: guide.sections.map { $0.title.value(for: language) },
                            language: language
                        ) { index in
                            withAnimation(.easeInOut) { proxy.scrollTo(guide.sections[index].id, anchor: .top) }
                        }
                    }

                    ForEach(guide.sections) { section in
                        DirectoryGuideSectionCard(
                            section: .init(section.id, section.symbol,
                                           section.title.ukrainian, section.title.german,
                                           section.body.ukrainian, section.body.german),
                            language: language,
                            route: .section(categoryID: "safety", topicID: topic.id, sectionID: section.id, federalState: nil),
                            compactBody: false, contacts: section.contacts
                        )
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
                    DirectoryFeedbackView(kind: .correction(categoryID: "safety", topicID: topic.id, title: topic.title.value(for: language)), repository: feedbackRepository)
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.homeSectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
                .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
        }
        .background(AppBackgroundView())
        .anchorPreference(key: SeasonalHeaderAnchors.self, value: .bounds) { [.readingSurface: $0] }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DirectoryInformationShareButton(
                    title: topic.title.value(for: language),
                    text: ContentShareText.compose(title: topic.title.value(for: language),
                        introduction: guide.summary.value(for: language), body: "",
                        sources: guide.sources.map { Optional($0.url.absoluteString) }, language: language),
                    language: language
                )
            }
            if contentStore.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: DirectoryRoute.editTopic(categoryID: "safety", topicID: topic.id)) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }
}
