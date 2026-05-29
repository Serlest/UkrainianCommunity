import SwiftUI

#Preview("News List") {
    NavigationStack {
        NewsListView(
            viewModel: NewsViewModel(repository: MockNewsRepository()),
            newsRepository: MockNewsRepository(),
            onNewsPublished: {},
            onNewsChanged: {},
            presentationMode: .management
        )
    }
}

#Preview("News Detail") {
    NavigationStack {
        NewsDetailView(
            viewModel: NewsViewModel(repository: MockNewsRepository()),
            postID: MockContentBuilder.newsPosts().first!.id,
            onNewsDeleted: {}
        )
        .environment(\.newsPresentationMode, .management)
    }
}
