import Combine
import SwiftUI

struct NewsNavigationRoute: Hashable {
    let postID: String
}

/// Internal management list for app news. Public news discovery is surfaced through Home.
struct NewsListView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: NewsViewModel
    let newsRepository: NewsRepository
    let onNewsPublished: @MainActor () async -> Void
    let onNewsChanged: () -> Void
    let presentationMode: NewsPresentationMode
    @State private var pendingDeletePostID: String?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false
    @State private var isShowingCreateSheet = false
    @State private var guestAccessAction: GuestAccessAction?

    init(
        viewModel: NewsViewModel,
        newsRepository: NewsRepository,
        onNewsPublished: @escaping @MainActor () async -> Void,
        onNewsChanged: @escaping () -> Void,
        presentationMode: NewsPresentationMode = .public
    ) {
        self.viewModel = viewModel
        self.newsRepository = newsRepository
        self.onNewsPublished = onNewsPublished
        self.onNewsChanged = onNewsChanged
        self.presentationMode = presentationMode
    }

    private var errorText: String {
        switch viewModel.error {
        case .network:
            AppStrings.News.loadNetworkError
        case .permissionDenied:
            AppStrings.News.loadPermissionError
        case .validationFailed:
            AppStrings.News.loadValidationError
        case .notFound:
            AppStrings.News.empty
        case .unknown:
            AppStrings.News.loadUnknownError
        case nil:
            ""
        }
    }

    private var canCreateNews: Bool {
        presentationMode.allowsManagementControls && PermissionService.canCreateNews(user: authState.user)
    }

    private var canDeleteNews: Bool {
        presentationMode.allowsManagementControls && PermissionService.canDeleteNews(user: authState.user)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.eventsHeaderContentSpacing) {
                newsHero

                AppGroupedContentPlane {
                    newsContent
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: NewsNavigationRoute.self) { route in
            NewsDetailView(viewModel: viewModel, postID: route.postID, onNewsDeleted: onNewsChanged)
                .environment(\.newsPresentationMode, presentationMode)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .guestAccessAlert($guestAccessAction)
        .appDestructiveActionDialog(Binding(
            get: {
                guard let postID = pendingDeletePostID else { return nil }
                return AppDestructiveActionDialog(
                    title: AppStrings.News.deleteConfirmation,
                    message: "",
                    destructiveActionTitle: AppStrings.News.delete,
                    cancelTitle: AppStrings.News.cancel
                ) {
                    Task {
                        do {
                            try await viewModel.deleteNews(id: postID)
                            onNewsChanged()
                        } catch let appError as AppError {
                            deleteErrorMessage = readableNewsErrorText(appError)
                            isShowingDeleteError = true
                        } catch {
                            deleteErrorMessage = readableNewsErrorText(.unknown)
                            isShowingDeleteError = true
                        }
                        pendingDeletePostID = nil
                    }
                }
            },
            set: { if $0 == nil { pendingDeletePostID = nil } }
        ))
        .appErrorDialog(Binding(
            get: {
                guard isShowingDeleteError else { return nil }
                return AppErrorDialog(
                    title: AppStrings.News.deleteFailed,
                    message: deleteErrorMessage ?? readableNewsErrorText(.unknown),
                    okTitle: AppStrings.News.dismissError
                )
            },
            set: {
                if $0 == nil {
                    isShowingDeleteError = false
                    deleteErrorMessage = nil
                }
            }
        ))
        .toolbar {
            if canCreateNews {
                Button {
                    isShowingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(AppStrings.Action.create)
                .accessibilityHint(AppStrings.News.title)
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            NavigationStack {
                NewsEditorView(repository: newsRepository, onPublished: onNewsPublished)
            }
        }
    }

    @ViewBuilder
    private var newsContent: some View {
        if viewModel.posts.isEmpty && viewModel.isLoading {
            LoadingStateCard(title: nil)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.posts.isEmpty && viewModel.error != nil {
            ErrorStateCard(
                systemImage: "newspaper",
                title: AppStrings.News.title,
                message: errorText,
                retryTitle: AppStrings.News.retry
            ) {
                Task {
                    await viewModel.refresh()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.posts.isEmpty {
            EmptyStateCard(
                systemImage: "newspaper",
                title: AppStrings.News.title,
                message: AppStrings.News.empty
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            newsGrid
        }
    }

    private var newsGrid: some View {
        AdaptiveCardGrid(items: viewModel.posts) { post in
            ZStack(alignment: .bottomTrailing) {
                NavigationLink(value: NewsNavigationRoute(postID: post.id)) {
                    NewsCard(post: post)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("news.card.\(post.id)")

                LikeButton(isLiked: post.likeState.isLiked, count: post.likeCount) {
                    handleLike(for: post.id)
                }
                .disabled(viewModel.pendingNewsLikeIDs.contains(post.id))
                .accessibilityIdentifier("news.like.\(post.id)")
                .accessibilityLabel(post.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like)
                .accessibilityHint(AppStrings.Common.likes)
                .padding(.trailing, AppTheme.cardPadding)
                .padding(.bottom, AppTheme.cardPadding)
            }
            .modifier(NewsDeleteSwipeActions(isEnabled: canDeleteNews) {
                pendingDeletePostID = post.id
            })
            .onAppear {
                Task {
                    await viewModel.loadNextPageIfNeeded(currentItemID: post.id)
                }
            }
        }
        .padding(AppTheme.homeFeedPlanePadding)
    }

    private var newsHero: some View {
        AppHeroBanner(
            title: AppStrings.News.heroTitle,
            subtitle: AppStrings.News.heroSubtitle,
            imageSource: .none,
            displaysTextOverImage: true
        )
    }

    private func handleLike(for postID: String) {
        guard authState.isAuthenticated else {
            guestAccessAction = .likes
            return
        }

        viewModel.toggleLike(for: postID)
    }
}

struct NewsDeleteSwipeActions: ViewModifier {
    let isEnabled: Bool
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.swipeActions(edge: .trailing) {
                Button(AppStrings.News.delete, role: .destructive) {
                    onDelete()
                }
            }
        } else {
            content
        }
    }
}
