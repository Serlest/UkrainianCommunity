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
                                         summary: guide.introduction.value(for: language),
                                         isArticle: true)

                    if guide.sections.count > 5 {
                        DirectoryTopicOutlineView(
                            titles: guide.sections.map { $0.title.value(for: language) },
                            language: language
                        ) { index in
                            withAnimation(.easeInOut) { proxy.scrollTo(guide.sections[index].id, anchor: .top) }
                        }
                    }

                    ForEach(guide.sections) { section in
                        DirectoryGuideSectionCard(section: section, language: language,
                                                  compactBody: ["first-steps", "registration", "housing", "residence", "documents", "citizenship", "health", "mental-health"].contains(categoryID))
                            .id(section.id)
                    }

                    if DirectoryRegionalContent.applies(categoryID: categoryID, topicID: topic.id) {
                        DirectoryRegionalSectionsView(
                            categoryID: categoryID, topicID: topic.id,
                            selectedFederalState: $selectedFederalState,
                            language: language
                        )
                    }

                    DirectorySourceListView(
                        sources: guide.sources.filter { source in
                            !guide.sections.contains { $0.source?.url == source.url }
                        },
                        language: language,
                        checkedOn: DirectoryGuideCatalog.checkedOn(for: categoryID)
                    )

                    DirectoryFeedbackView(kind: .correction(categoryID: categoryID, topicID: topic.id, title: topic.title.value(for: language)), repository: feedbackRepository)
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.homeSectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
                .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
        }
        .background(AppBackgroundView())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}
