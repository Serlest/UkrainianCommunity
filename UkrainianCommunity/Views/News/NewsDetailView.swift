import SwiftUI
import UIKit

struct NewsDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.newsPresentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: NewsViewModel
    let postID: String
    let onNewsDeleted: () -> Void
    let onNavigateBack: (() -> Void)?
    let organizationRepository: OrganizationRepository
    @State var showDeleteConfirmation = false
    @State var deleteErrorMessage: String?
    @State var isDeleting = false
    @State var isShowingEditSheet = false
    @State var pendingRemovalPostID: String?
    @State var guestAccessAction: GuestAccessAction?
    @State var recordedViewKeys = Set<String>()
    @State var sharePayload: NewsSharePayload?
    @State var commentText = ""
    @State var editingCommentID: String?
    @State var pendingCommentDeleteID: String?
    @State var commentDeleteErrorMessage: String?
    @State var permissionOrganization: Organization?
    @FocusState var isCommentFieldFocused: Bool
    let detailImageHeight: CGFloat = 220
    let detailSectionSpacing: CGFloat = AppTheme.detailSectionSpacing

    init(
        viewModel: NewsViewModel,
        postID: String,
        onNewsDeleted: @escaping () -> Void,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onNavigateBack: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.postID = postID
        self.onNewsDeleted = onNewsDeleted
        self.onNavigateBack = onNavigateBack
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
            return PermissionService.canManageOrganizationRoles(organization, user: authState.user)
        }

        return PermissionService.canDeleteNews(post, user: authState.user)
    }


    @ViewBuilder
    var editSheetContent: some View {
        if let post = viewModel.post(for: postID) {
            NavigationStack {
                NewsEditorView(repository: viewModel.editorRepository, news: post) {
                    await viewModel.refresh()
                }
            }
            .environmentObject(authState)
        }
    }

    var body: some View {
        Group {
            if let post = viewModel.post(for: postID) {
                DetailScreenShell(
                    topPadding: 0,
                    contentSpacing: detailSectionSpacing,
                    backAction: navigateBack,
                    refreshAction: refreshNewsDetail
                ) {
                    newsHeaderActions(for: post)
                } content: {
                    articleHeader(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    heroImage(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    if !post.subtitle.isEmpty {
                        leadBlock(for: post)
                            .onTapGesture { isCommentFieldFocused = false }
                    }

                    articleBody(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    articleSourceSection(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    tagsSection(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    relatedSection(for: post)

                    actionsCard(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    managementCard(for: post)
                        .onTapGesture { isCommentFieldFocused = false }

                    commentsSection(for: post)
                }
            } else {
                ZStack {
                    AppBackgroundView()
                        .allowsHitTesting(false)

                    EmptyStateView(title: AppStrings.Common.noItems)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .confirmationDialog(AppStrings.News.deleteConfirmation, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(AppStrings.News.delete, role: .destructive) {
                Task {
                    await deleteCurrentNews()
                }
            }
            Button(AppStrings.News.cancel, role: .cancel) {}
        }
        .confirmationDialog(AppStrings.Common.deleteCommentConfirmation, isPresented: Binding(
            get: { pendingCommentDeleteID != nil },
            set: { if !$0 { pendingCommentDeleteID = nil } }
        ), titleVisibility: .visible) {
            Button(AppStrings.Action.delete, role: .destructive) {
                guard let pendingCommentDeleteID else { return }
                Task {
                    await deleteComment(commentID: pendingCommentDeleteID)
                }
            }
            Button(AppStrings.News.cancel, role: .cancel) {
                pendingCommentDeleteID = nil
            }
        }
        .alert(AppStrings.News.deleteFailed, isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button(AppStrings.News.dismissError, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert(AppStrings.Common.deleteCommentFailed, isPresented: Binding(
            get: { commentDeleteErrorMessage != nil },
            set: { if !$0 { commentDeleteErrorMessage = nil } }
        )) {
            Button(AppStrings.News.dismissError, role: .cancel) {}
        } message: {
            Text(commentDeleteErrorMessage ?? readableNewsErrorText(.unknown))
        }
        .sheet(isPresented: $isShowingEditSheet) {
            editSheetContent
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: payload.items)
        }
        .guestAccessAlert($guestAccessAction)
        .task {
            await viewModel.loadIfNeeded()
            guard let post = viewModel.post(for: postID) else { return }
            await loadPermissionOrganizationIfNeeded(organizationID: post.source.organizationId)
            await viewModel.loadComments(for: postID)
            guard !recordedViewKeys.contains(newsViewTaskID) else { return }
            recordedViewKeys.insert(newsViewTaskID)
            viewModel.recordView(for: postID)
            RecentViewRecorder.recordNews(post)
        }
        .onChange(of: authState.user?.id) { _, _ in
            guard let post = viewModel.post(for: postID) else { return }
            guard !recordedViewKeys.contains(newsViewTaskID) else { return }
            recordedViewKeys.insert(newsViewTaskID)
            viewModel.recordView(for: postID)
            RecentViewRecorder.recordNews(post)
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

    func refreshNewsDetail() async {
        await viewModel.refresh()
        guard let post = viewModel.post(for: postID) else { return }
        await loadPermissionOrganizationIfNeeded(organizationID: post.source.organizationId)
        await viewModel.loadComments(for: postID)
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
            permissionOrganization = try await organizationRepository.fetchOrganization(id: organizationID)
        } catch {
            permissionOrganization = nil
        }
    }

    @MainActor
    func deleteComment(commentID: String) async {
        pendingCommentDeleteID = nil
        await viewModel.deleteComment(postID: postID, commentID: commentID)
        if let error = viewModel.error {
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

struct NewsSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]

    init(post: NewsPost) {
        var text = post.title
        if !post.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += "\n\n\(post.subtitle)"
        }
        items = [text]
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
