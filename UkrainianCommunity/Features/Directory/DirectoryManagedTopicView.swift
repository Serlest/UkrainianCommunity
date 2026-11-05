import SwiftUI

struct DirectoryManagedTopicView: View {
    let categoryID: String
    let topic: DirectoryManagedTopic
    @Binding var selectedFederalState: AustrianFederalState?
    let feedbackRepository: FeedbackRepository
    var initialSectionID: String? = nil

    @EnvironmentObject private var contentStore: DirectoryContentStore
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var sections: [DirectoryManagedSection] {
        topic.sections.filter { !$0.isHidden }.sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                    DirectoryPageHeading(title: topic.title.value(for: language),
                                         summary: topic.summary.value(for: language), isArticle: true)
                    DirectorySyncNoticeView(language: language)
                    if sections.count > 5 {
                        DirectoryTopicOutlineView(
                            titles: sections.map { $0.title.value(for: language) },
                            language: language
                        ) { index in
                            withAnimation(.easeInOut) { proxy.scrollTo(sections[index].id, anchor: .top) }
                        }
                    }
                    ForEach(sections) { section in
                        sectionCard(section).id(section.id)
                    }
                    if !topic.regionalSections.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
                            Text(DirectoryText(ukrainian: "У вашій федеральній землі",
                                               german: "In Ihrem Bundesland").value(for: language))
                                .font(.title3.bold())
                                .foregroundStyle(AppTheme.textPrimary)
                            AppRegionFilterMenu(selection: $selectedFederalState)
                            if let selectedFederalState {
                                ForEach((topic.regionalSections[selectedFederalState.rawValue] ?? [])
                                    .filter { !$0.isHidden }.sorted { $0.order < $1.order }) { section in
                                    sectionCard(section, federalState: selectedFederalState).id(section.id)
                                }
                            } else {
                                Text(DirectoryText(
                                    ukrainian: "Оберіть землю, щоб побачити її офіційні служби та правила.",
                                    german: "Wählen Sie ein Bundesland für zuständige Stellen und Regeln."
                                ).value(for: language))
                                .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    DirectorySourceListView(
                        sources: topic.sources.filter { source in
                            !sections.contains { $0.source?.url == source.url }
                        }.compactMap(\.displaySource),
                        language: language,
                        checkedOn: contentStore.publicationDate(categoryID),
                        isPublicationDate: true
                    )
                    DirectoryFeedbackView(
                        kind: .correction(categoryID: categoryID, topicID: topic.id,
                                          title: topic.title.value(for: language)),
                        repository: feedbackRepository
                    )
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.homeSectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
                .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
            .task(id: initialSectionID) {
                guard let initialSectionID else { return }
                await Task.yield()
                proxy.scrollTo(initialSectionID, anchor: .top)
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
                        introduction: topic.summary.value(for: language), body: "",
                        sources: topic.sources.map { Optional($0.url) }, language: language),
                    language: language
                )
            }
            if contentStore.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: DirectoryRoute.editTopic(categoryID: categoryID, topicID: topic.id)) {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(DirectoryText(ukrainian: "Редагувати статтю", german: "Beitrag bearbeiten").value(for: language))
                }
            }
        }
    }

    @ViewBuilder private func sectionCard(_ section: DirectoryManagedSection, federalState: AustrianFederalState? = nil) -> some View {
        DirectoryGuideSectionCard(
            section: .init(section.id, section.symbol,
                           section.title.ukrainian, section.title.german,
                           section.body.ukrainian, section.body.german,
                           phoneNumber: section.phoneNumber,
                           source: section.source?.displaySource),
            language: language,
            route: .section(categoryID: categoryID, topicID: topic.id, sectionID: section.id,
                            federalState: federalState?.rawValue),
            compactBody: true,
            contacts: section.contacts.map {
                SafetyContact(number: $0.number, title: $0.title, detail: $0.detail)
            }
        )
    }
}
