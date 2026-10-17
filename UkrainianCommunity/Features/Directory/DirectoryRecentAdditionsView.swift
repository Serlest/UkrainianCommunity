import SwiftUI

struct DirectoryRecentAdditionsView: View {
    @ObservedObject var store: DirectoryRecentAdditionsStore
    let language: AppLanguage

    private func text(_ uk: String, _ de: String) -> String {
        DirectoryText(ukrainian: uk, german: de).value(for: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text("Останнє додане", "Zuletzt hinzugefügt"))
                .font(.title2.bold()).foregroundStyle(AppTheme.textPrimary)
            ForEach(store.items) { item in
                NavigationLink(value: DirectoryRoute.recent(item)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title.value(for: language)).font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text([item.categoryTitle.value(for: language),
                              item.kind == .section ? item.topicTitle.value(for: language) : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                        HStack {
                            Text(item.federalState.flatMap(AustrianFederalState.init(rawValue:))?.displayName
                                 ?? text("Уся Австрія", "Ganz Österreich"))
                            if let date = item.date {
                                Text(date, format: .dateTime.day().month().year())
                            }
                        }
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("directory.recent.\(item.id)")
            }
            if store.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if store.failed {
                Text(text("Не вдалося завантажити нові матеріали.", "Neue Inhalte konnten nicht geladen werden."))
                    .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                Button(text("Повторити", "Erneut versuchen")) {
                    Task { await store.retry() }
                }
            } else if store.items.isEmpty {
                Text(text("Нові матеріали з’являться тут після публікації.", "Neue Inhalte erscheinen hier nach der Veröffentlichung."))
                    .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
            } else if store.hasMore {
                Button(text("Показати ще", "Weitere anzeigen")) {
                    Task { await store.load(reset: false) }
                }
                .accessibilityIdentifier("directory.recent.more")
            }
        }
        .accessibilityIdentifier("directory.recent")
    }
}

/// The destination owns its region: opening a regional addition never changes the feed filter.
struct DirectoryRecentDestinationView: View {
    let item: DirectoryRecentAddition
    let feedbackRepository: FeedbackRepository
    @EnvironmentObject private var contentStore: DirectoryContentStore
    @State private var region: AustrianFederalState?
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue

    init(item: DirectoryRecentAddition, feedbackRepository: FeedbackRepository) {
        self.item = item
        self.feedbackRepository = feedbackRepository
        _region = State(initialValue: item.federalState.flatMap(AustrianFederalState.init(rawValue:)))
    }

    var body: some View {
        if let topic = contentStore.managedTopic(categoryID: item.categoryID, topicID: item.topicID),
           item.isAvailable(in: topic) {
            DirectoryManagedTopicView(categoryID: item.categoryID, topic: topic,
                                      selectedFederalState: $region, feedbackRepository: feedbackRepository,
                                      initialSectionID: item.sectionID)
        } else if contentStore.syncState == .loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppBackgroundView())
        } else {
            ContentUnavailableView(
                DirectoryText(ukrainian: "Матеріал більше недоступний", german: "Inhalt nicht mehr verfügbar")
                    .value(for: AppLanguage(rawValue: languageCode) ?? .german),
                systemImage: "doc.text.magnifyingglass")
            .background(AppBackgroundView())
        }
    }
}
