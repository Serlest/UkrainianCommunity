import SwiftUI

struct GuidePublishedListView: View {
    let repository: GuideRepository

    @StateObject private var viewModel: GuideListViewModel

    init(repository: GuideRepository) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: GuideListViewModel(repository: repository))
    }

    var body: some View {
        DetailPageContainer {
            AppEditorSectionCard {
                SectionHeaderBlock(
                    title: AppStrings.GuideManagement.published,
                    subtitle: AppStrings.GuideManagement.publishedSubtitle
                )
            }

            content
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.GuideManagement.published)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .guideChanged)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.articles.isEmpty {
            GuideLoadingView()
        } else if let error = viewModel.error, viewModel.articles.isEmpty {
            GuideErrorStateView(error: error, retryAction: viewModel.reload)
        } else if viewModel.articles.isEmpty {
            EmptyStateCard(
                systemImage: "checkmark.seal.fill",
                title: AppStrings.GuideManagement.published,
                message: AppStrings.GuideManagement.publishedSubtitle
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ForEach(viewModel.articles) { article in
                    NavigationLink {
                        GuideDetailView(article: article)
                    } label: {
                        GuideArticleCard(article: article, emphasized: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
