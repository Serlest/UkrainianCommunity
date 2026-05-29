import SwiftUI

struct GuideInReviewListView: View {
    let repository: GuideRepository

    @StateObject private var viewModel: GuideInReviewListViewModel

    init(repository: GuideRepository) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: GuideInReviewListViewModel(repository: repository))
    }

    var body: some View {
        DetailPageContainer {
            AppEditorSectionCard {
                SectionHeaderBlock(
                    title: AppStrings.GuideManagement.inReview,
                    subtitle: AppStrings.GuideManagement.inReviewSubtitle
                )
            }

            content
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .navigationTitle(AppStrings.GuideManagement.inReview)
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
                systemImage: "clock.badge.exclamationmark",
                title: AppStrings.GuideManagement.inReview,
                message: AppStrings.GuideManagement.inReviewSubtitle
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ForEach(viewModel.articles) { article in
                    NavigationLink {
                        GuideAdminReviewPreviewView(article: article, repository: repository)
                    } label: {
                        GuideArticleCard(article: article, emphasized: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
