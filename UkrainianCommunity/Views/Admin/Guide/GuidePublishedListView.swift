import SwiftUI

struct GuidePublishedListView: View {
    let repository: GuideRepository
    let currentUserId: String?

    @StateObject private var viewModel: GuideListViewModel
    @State private var deleteCandidate: GuideArticle?

    init(repository: GuideRepository, currentUserId: String?) {
        self.repository = repository
        self.currentUserId = currentUserId
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
        .background(AppBackgroundView().allowsHitTesting(false))
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
        .alert(
            AppStrings.GuideManagement.deleteConfirmationTitle,
            isPresented: deleteConfirmationIsPresented
        ) {
            Button(AppStrings.Common.cancel, role: .cancel) {}
            Button(AppStrings.GuideManagement.deleteAction, role: .destructive) {
                guard let article = deleteCandidate else { return }
                Task {
                    await viewModel.delete(article, currentUserId: currentUserId)
                }
            }
        } message: {
            Text(AppStrings.GuideManagement.deleteConfirmationMessage(deleteCandidate?.title ?? ""))
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
                if let deleteError = viewModel.deleteError {
                    GuideErrorStateView(error: deleteError, retryAction: viewModel.reload)
                }

                ForEach(viewModel.articles) { article in
                    HStack(alignment: .center, spacing: AppTheme.eventsMetadataSpacing) {
                        NavigationLink {
                            GuideDetailView(article: article)
                        } label: {
                            GuideArticleCard(article: article, emphasized: false)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            GuideEditorView(viewModel: GuideEditorViewModel(
                                article: article,
                                repository: repository,
                                currentUserId: currentUserId
                            ))
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.accentPrimary)
                                .frame(width: 44, height: 44)
                                .background(
                                    AppTheme.surfaceGlass,
                                    in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppStrings.GuideManagement.editAction)

                        Button {
                            deleteCandidate = article
                        } label: {
                            Image(systemName: viewModel.isDeleting(article) ? "clock" : "trash")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.accentDestructive)
                                .frame(width: 44, height: 44)
                                .background(
                                    AppTheme.surfaceGlass,
                                    in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isDeleting(article))
                        .accessibilityLabel(AppStrings.GuideManagement.deleteAction)
                    }
                }
            }
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    deleteCandidate = nil
                }
            }
        )
    }
}
