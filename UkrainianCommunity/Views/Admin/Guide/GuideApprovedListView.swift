import SwiftUI

struct GuideApprovedListView: View {
    let repository: GuideRepository

    @StateObject private var viewModel: GuideApprovedListViewModel

    init(repository: GuideRepository) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: GuideApprovedListViewModel(repository: repository))
    }

    var body: some View {
        DetailPageContainer {
            AppEditorSectionCard {
                SectionHeaderBlock(
                    title: AppStrings.GuideManagement.approved,
                    subtitle: AppStrings.GuideManagement.approvedSubtitle
                )
            }

            content
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.GuideManagement.approved)
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
                systemImage: "checkmark.seal",
                title: AppStrings.GuideManagement.approved,
                message: AppStrings.GuideManagement.approvedSubtitle
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
