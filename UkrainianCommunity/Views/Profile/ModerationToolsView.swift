import SwiftUI

struct ModerationToolsView: View {
    let newsRepository: NewsRepository

    init(newsRepository: NewsRepository = AppContainer.development.newsRepository) {
        self.newsRepository = newsRepository
    }

    var body: some View {
        List {
            Section {
                Text(AppStrings.Moderation.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label(AppStrings.Profile.reviewPendingContent, systemImage: "clock.badge.exclamationmark")
                NavigationLink {
                    NewsEditorView(repository: newsRepository)
                } label: {
                    Label(AppStrings.Profile.manageNews, systemImage: "newspaper")
                }
                Label(AppStrings.Profile.manageEvents, systemImage: "calendar")
                Label(AppStrings.Profile.manageOrganizations, systemImage: "building.2")
                Label(AppStrings.Profile.manageMarketplace, systemImage: "storefront")
            }
        }
        .navigationTitle(AppStrings.Moderation.title)
    }
}

#Preview {
    NavigationStack {
        ModerationToolsView(newsRepository: MockNewsRepository())
    }
}
