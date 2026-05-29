import SwiftUI

struct GuideDraftListView: View {
    let repository: GuideRepository
    let currentUserId: String?

    @StateObject private var viewModel: GuideDraftListViewModel
    @State private var archiveCandidate: GuideArticle?

    init(repository: GuideRepository, currentUserId: String?) {
        self.repository = repository
        self.currentUserId = currentUserId
        _viewModel = StateObject(wrappedValue: GuideDraftListViewModel(repository: repository))
    }

    var body: some View {
        DetailPageContainer {
            AppEditorSectionCard {
                SectionHeaderBlock(
                    title: AppStrings.GuideManagement.drafts,
                    subtitle: AppStrings.GuideManagement.draftsSubtitle
                )
            }

            content
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .navigationTitle(AppStrings.GuideManagement.drafts)
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
            AppStrings.GuideManagement.archiveDraftConfirmationTitle,
            isPresented: archiveConfirmationIsPresented
        ) {
            Button(AppStrings.Common.cancel, role: .cancel) {}
            Button(AppStrings.GuideManagement.archiveDraftAction, role: .destructive) {
                guard let article = archiveCandidate else { return }
                Task {
                    await viewModel.archive(article, currentUserId: currentUserId)
                }
            }
        } message: {
            Text(AppStrings.GuideManagement.archiveDraftConfirmationMessage(archiveCandidate?.title ?? ""))
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.drafts.isEmpty {
            GuideLoadingView()
        } else if let error = viewModel.error, viewModel.drafts.isEmpty {
            GuideErrorStateView(error: error, retryAction: viewModel.reload)
        } else if viewModel.drafts.isEmpty {
            EmptyStateCard(
                systemImage: "doc.text",
                title: AppStrings.GuideManagement.drafts,
                message: AppStrings.GuideManagement.draftsSubtitle
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                if let archiveError = viewModel.archiveError {
                    GuideErrorStateView(error: archiveError, retryAction: viewModel.reload)
                }

                ForEach(viewModel.drafts) { article in
                    HStack(alignment: .center, spacing: AppTheme.eventsMetadataSpacing) {
                        NavigationLink {
                            GuideEditorView(viewModel: GuideEditorViewModel(
                                article: article,
                                repository: repository,
                                currentUserId: currentUserId
                            ))
                        } label: {
                            GuideArticleCard(article: article, emphasized: false)
                        }
                        .buttonStyle(.plain)

                        Button {
                            archiveCandidate = article
                        } label: {
                            Image(systemName: viewModel.isArchiving(article) ? "clock" : "archivebox")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.accentDestructive)
                                .frame(width: 44, height: 44)
                                .background(
                                    AppTheme.surfaceGlass,
                                    in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isArchiving(article))
                        .accessibilityLabel(AppStrings.GuideManagement.archiveDraftAction)
                    }
                }
            }
        }
    }

    private var archiveConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { archiveCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    archiveCandidate = nil
                }
            }
        )
    }
}
