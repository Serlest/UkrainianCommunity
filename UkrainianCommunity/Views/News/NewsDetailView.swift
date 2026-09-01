import SwiftUI

struct NewsDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var analyticsScenePhase
    @Environment(\.newsPresentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.contentReportPresentation) var contentReportPresentation
    @Environment(\.userBlockingPresentation) var userBlockingPresentation
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: NewsViewModel
    let postID: String
    let onNewsDeleted: () -> Void
    let onNavigateBack: (() -> Void)?
    let analyticsSourceScreen: String
    let organizationRepository: OrganizationRepository
    @State private var detailLoadState: ContentDetailLoadState = .loading
    @State private var refreshError: AppError?
    @State var showDeleteConfirmation = false
    @State var deleteErrorMessage: String?
    @State var isDeleting = false
    @State var isShowingEditSheet = false
    @State var pendingRemovalPostID: String?
    @State var guestAccessAction: GuestAccessAction?
    @State var recordedViewKeys = Set<String>()
    @State var pendingCommentDeleteID: String?
    @State var commentDeleteErrorMessage: String?
    @State var permissionOrganization: Organization?
    @State var relatedNewsCandidates: [NewsPost] = []
    @State var relatedNewsRecommendations: [NewsContentRecommendation] = []
    @FocusState var isCommentFieldFocused: Bool
    let detailImageHeight: CGFloat = 220
    let detailSectionSpacing: CGFloat = AppTheme.detailSectionSpacing

    init(
        viewModel: NewsViewModel,
        postID: String,
        onNewsDeleted: @escaping () -> Void,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onNavigateBack: (() -> Void)? = nil,
        analyticsSourceScreen: String = "news_detail"
    ) {
        self.viewModel = viewModel
        self.postID = postID
        self.onNewsDeleted = onNewsDeleted
        self.onNavigateBack = onNavigateBack
        self.analyticsSourceScreen = analyticsSourceScreen
        self.organizationRepository = organizationRepository
    }

    var canEditNews: Bool {
        guard let post = viewModel.post(for: postID) else { return false }
        if PermissionService.canEditNews(user: authState.user) {
            return true
        }

        guard let organizationID = post.source.organizationId else {
            return false
        }

        if let organization = organizationForPermissions(organizationID: organizationID) {
            return PermissionService.canEditOrganizationNews(organization, user: authState.user)
        }

        return false
    }

    var canDeleteNews: Bool {
        guard let post = viewModel.post(for: postID) else { return false }
        guard let organizationID = post.source.organizationId else {
            return PermissionService.canDeleteNews(post, user: authState.user)
        }

        if let organization = organizationForPermissions(organizationID: organizationID) {
            return PermissionService.canDeleteOrganizationContent(organization, user: authState.user)
        }

        return PermissionService.canDeleteNews(post, user: authState.user)
    }


    @ViewBuilder
    var editSheetContent: some View {
        if let post = viewModel.post(for: postID) {
            NavigationStack {
                NewsEditorView(repository: viewModel.editorRepository, news: post) { _ in
                    await viewModel.refresh()
                    return true
                }
            }
            .environmentObject(authState)
        }
    }

    var body: some View {
        Group {
            if let post = viewModel.post(for: postID) {
                DetailScreenShell(
                    contentSpacing: detailSectionSpacing,
                    backAction: navigateBack,
                    refreshAction: refreshNewsDetail
                ) {
                    newsHeaderActions(for: post)
                } content: {
                    if let refreshError {
                        InlineMessageCard(style: .error, message: readableNewsErrorText(refreshError))
                    }
                    articleHeader(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    heroImage(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    if !post.localizedSubtitle.isEmpty {
                        leadBlock(for: post)
                            .onTapGesture { isCommentFieldFocused = false }
                    }

                    articleBody(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    articleSourceSection(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    articleExternalActionSection(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    tagsSection(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    relatedSection(for: post)

                    actionsCard(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    commentsSection(for: post)
                }
            } else {
                DetailScreenShell(backAction: navigateBack) {
                    ContentDetailLoadStateCard(
                        state: unresolvedDetailLoadState,
                        accessibilityPrefix: "news.detail.state",
                        retryAction: retryNewsDetail
                    )
                }
            }
        }
        .appDestructiveActionDialog(Binding(
            get: {
                guard showDeleteConfirmation else { return nil }
                return AppDestructiveActionDialog(
                    title: AppStrings.News.deleteConfirmation,
                    message: "",
                    destructiveActionTitle: AppStrings.News.delete,
                    cancelTitle: AppStrings.News.cancel
                ) {
                    Task {
                        await deleteCurrentNews()
                    }
                }
            },
            set: { if $0 == nil { showDeleteConfirmation = false } }
        ))
        .appDestructiveActionDialog(Binding(
            get: {
                guard let commentID = pendingCommentDeleteID else { return nil }
                return AppDestructiveActionDialog(
                    title: AppStrings.Common.deleteCommentConfirmation,
                    message: "",
                    destructiveActionTitle: AppStrings.Action.delete,
                    cancelTitle: AppStrings.News.cancel
                ) {
                    Task {
                        await deleteComment(commentID: commentID)
                    }
                }
            },
            set: { if $0 == nil { pendingCommentDeleteID = nil } }
        ))
        .appErrorDialog(Binding(
            get: {
                deleteErrorMessage.map {
                    AppErrorDialog(
                        title: AppStrings.News.deleteFailed,
                        message: $0,
                        okTitle: AppStrings.News.dismissError
                    )
                }
            },
            set: { if $0 == nil { deleteErrorMessage = nil } }
        ))
        .appErrorDialog(Binding(
            get: {
                commentDeleteErrorMessage.map {
                    AppErrorDialog(
                        title: AppStrings.Common.deleteCommentFailed,
                        message: $0,
                        okTitle: AppStrings.News.dismissError
                    )
                }
            },
            set: { if $0 == nil { commentDeleteErrorMessage = nil } }
        ))
        .sheet(isPresented: $isShowingEditSheet) {
            editSheetContent
        }
        .guestAccessAlert($guestAccessAction)
        .appErrorDialog(Binding(
            get: {
                viewModel.interactionError.map {
                    AppErrorDialog(message: readableNewsErrorText($0))
                }
            },
            set: { if $0 == nil { viewModel.dismissInteractionError() } }
        ))
        .task(id: analyticsScenePhase == .active ? viewModel.post(for: postID)?.id : nil) {
            guard analyticsScenePhase == .active,
                  let post = viewModel.post(for: postID) else { return }
            await viewModel.trackViewWhileVisible(for: post, sourceScreen: analyticsSourceScreen)
        }
        .task(id: newsViewTaskID) {
            await loadNewsDetail(force: false, loadsRecommendations: true)
        }
        .onChange(of: viewModel.contentVersion) { _, _ in
            refreshRelatedNewsRecommendations()
            if viewModel.post(for: postID) == nil, detailLoadState == .content {
                detailLoadState = .failed(.notFound)
            }
        }
        .onDisappear {
            viewModel.stopListeningComments(for: postID)
            guard let pendingRemovalPostID else { return }
            withTransaction(Transaction(animation: nil)) {
                viewModel.removeDeletedNews(id: pendingRemovalPostID)
            }
            self.pendingRemovalPostID = nil
        }
    }

    func refreshRelatedNewsRecommendations() {
        guard let post = viewModel.post(for: postID) else {
            relatedNewsRecommendations = []
            return
        }
        relatedNewsRecommendations = ContentRecommendationEngine.newsRecommendations(
            for: post,
            candidates: relatedNewsCandidates
        )
    }

    func refreshNewsDetail() async {
        await loadNewsDetail(force: true, loadsRecommendations: false)
    }

    private var unresolvedDetailLoadState: ContentDetailLoadState {
        guard viewModel.post(for: postID) == nil else { return .content }
        return detailLoadState == .content ? .loading : detailLoadState
    }

    private func retryNewsDetail() {
        Task {
            await loadNewsDetail(force: true, loadsRecommendations: true)
        }
    }

    @MainActor
    private func loadNewsDetail(force: Bool, loadsRecommendations: Bool) async {
        if viewModel.post(for: postID) == nil {
            detailLoadState = .loading
        }
        refreshError = nil

        let outcome = await viewModel.loadPostDetail(postID: postID, force: force)
        guard !Task.isCancelled else { return }

        switch outcome {
        case .loaded:
            detailLoadState = .content
        case .failed(let error):
            if viewModel.post(for: postID) != nil {
                detailLoadState = .content
                refreshError = error
            } else {
                detailLoadState = .failed(error)
            }
            return
        case .cancelled:
            return
        }

        guard let post = viewModel.post(for: postID) else { return }
        await loadPermissionOrganizationIfNeeded(organizationID: post.source.organizationId)
        await viewModel.loadComments(for: postID, forceRefresh: force)
        if loadsRecommendations {
            relatedNewsCandidates = await viewModel.recommendationCandidates(for: post)
            refreshRelatedNewsRecommendations()
        }
        guard !recordedViewKeys.contains(newsViewTaskID) else { return }
        recordedViewKeys.insert(newsViewTaskID)
        viewModel.recordView(for: postID)
        RecentViewRecorder.recordNews(post)
    }

    func organizationForPermissions(organizationID: String) -> Organization? {
        guard permissionOrganization?.id == organizationID else { return nil }
        return permissionOrganization
    }

    @MainActor
    func loadPermissionOrganizationIfNeeded(organizationID: String?) async {
        guard let organizationID else {
            permissionOrganization = nil
            return
        }
        guard permissionOrganization?.id != organizationID else { return }

        do {
            permissionOrganization = try await RefreshRequest.run { [self] in try await organizationRepository.fetchOrganization(id: organizationID) }
        } catch {
            permissionOrganization = nil
        }
    }

    @MainActor
    func deleteComment(commentID: String) async {
        pendingCommentDeleteID = nil
        if case .failure(let error) = await viewModel.deleteComment(postID: postID, commentID: commentID) {
            commentDeleteErrorMessage = readableNewsErrorText(error)
        }
    }

    func newsDateText(for post: NewsPost) -> String {
        LocalizationStore.dateString(from: post.createdAt, dateStyle: .medium, timeStyle: .none)
    }

    func newsTimeText(for post: NewsPost) -> String {
        LocalizationStore.dateString(from: post.createdAt, dateStyle: .none, timeStyle: .short)
    }

    func viewCountText(for post: NewsPost) -> String {
        AppStrings.News.viewCount(post.viewCount)
    }

    func newsSourceText(for post: NewsPost) -> String {
        if let organizationName = post.source.displayOrganizationName?.trimmingCharacters(in: .whitespacesAndNewlines), !organizationName.isEmpty {
            return organizationName
        }

        return AppStrings.News.missingOrganization
    }

    func detailGlassCard<Content: View>(padding: CGFloat = AppTheme.detailCardPadding, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(
            cornerRadius: AppTheme.cardRadius,
            material: .ultraThinMaterial,
            surface: AppTheme.glassSurface(for: colorScheme),
            borderOpacity: 0.62,
            shadowRadius: 8,
            shadowY: 4
        )
    }

    func sanitizedImageURL(_ imageURL: String?) -> String? {
        guard let imageURL = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
            return nil
        }
        return imageURL
    }

    @MainActor
    func deleteCurrentNews() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await viewModel.deleteNews(id: postID)
            pendingRemovalPostID = postID
            dismiss()
            onNewsDeleted()
        } catch let appError as AppError {
            deleteErrorMessage = readableNewsErrorText(appError)
        } catch {
            deleteErrorMessage = readableNewsErrorText(.unknown)
        }
    }

    func handleLike(for postID: String) {
        guard authState.isAuthenticated else {
            guestAccessAction = .likes
            return
        }

        viewModel.toggleLike(for: postID)
    }

    func handleBookmark(for postID: String) {
        guard authState.isAuthenticated else {
            guestAccessAction = .bookmarks
            return
        }

        viewModel.toggleBookmark(for: postID)
    }
}
