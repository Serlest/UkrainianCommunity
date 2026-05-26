import Combine
import SwiftUI
import UIKit

private struct NewsNavigationRoute: Hashable {
    let postID: String
}

enum NewsPresentationMode {
    case `public`
    case management

    var allowsManagementControls: Bool {
        self == .management
    }
}

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
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                newsHeader
                    .padding(.horizontal, AppTheme.pageHorizontal)

                Group {
                    if viewModel.posts.isEmpty && viewModel.isLoading {
                VStack {
                    LoadingStateCard(title: nil)
                }
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
                VStack(spacing: 16) {
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
                            .padding(.trailing, 18)
                            .padding(.bottom, 18)
                        }
                        .modifier(NewsDeleteSwipeActions(isEnabled: canDeleteNews) {
                            pendingDeletePostID = post.id
                        })
                    }
                    .padding()
                }
                }
            }
        }
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
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
        .confirmationDialog(
            AppStrings.News.deleteConfirmation,
            isPresented: Binding(
                get: { pendingDeletePostID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletePostID = nil
                    }
                }
            )
        ) {
            Button(AppStrings.News.delete, role: .destructive) {
                guard let postID = pendingDeletePostID else { return }
                Task {
                    do {
                        try await viewModel.deleteNews(id: postID)
                        viewModel.removeDeletedNews(id: postID)
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
            Button(AppStrings.News.cancel, role: .cancel) {
                pendingDeletePostID = nil
            }
        }
        .alert(AppStrings.News.deleteFailed, isPresented: $isShowingDeleteError) {
            Button(AppStrings.News.dismissError) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? readableNewsErrorText(.unknown))
        }
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

    private var newsHeader: some View {
        AppBrandHeader {
            AppNotificationBellButton()
        }
    }

    private func handleLike(for postID: String) {
        guard authState.isAuthenticated else {
            guestAccessAction = .likes
            return
        }

        viewModel.toggleLike(for: postID)
    }
}
private func readableNewsErrorText(_ error: AppError?) -> String {
    switch error {
    case .network:
        AppStrings.News.loadNetworkError
    case .permissionDenied:
        AppStrings.News.actionPermissionError
    case .validationFailed:
        AppStrings.News.actionValidationError
    case .notFound:
        AppStrings.News.actionNotFoundError
    case .unknown:
        AppStrings.News.actionUnknownError
    case nil:
        AppStrings.News.actionUnknownError
    }
}

private func sanitizedAuthorName(_ rawValue: String) -> String {
    let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
        return AppStrings.NewsEditor.authorFallback
    }

    if looksLikeRawAuthorIdentifier(trimmedValue) {
        return AppStrings.NewsEditor.authorFallback
    }

    return trimmedValue
}

private func looksLikeRawAuthorIdentifier(_ value: String) -> Bool {
    guard value.count >= 20 else { return false }
    guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }

    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return value.rangeOfCharacter(from: allowedCharacters.inverted) == nil
}

private func newsPublisherText(for post: NewsPost) -> String {
    let authorName = sanitizedAuthorName(post.authorName)
    let trimmedOrganizationName = post.source.displayOrganizationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let sourceName = trimmedOrganizationName.isEmpty ? AppStrings.News.missingOrganization : trimmedOrganizationName

    guard authorName != AppStrings.NewsEditor.authorFallback else {
        return sourceName
    }

    return "\(authorName) · \(sourceName)"
}

private struct NewsCard: View {
    let post: NewsPost

    var body: some View {
        CommunityCard {
            RemoteCardImage(imageURL: post.imageURL, height: 220, source: "NewsCard")

            VStack(alignment: .leading, spacing: 10) {
                Text(post.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !post.subtitle.isEmpty {
                    Text(post.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(newsPublisherText(for: post), systemImage: "person.crop.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.trailing, 88)
            }
        }
    }
}

struct NewsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.newsPresentationMode) private var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: NewsViewModel
    let postID: String
    let onNewsDeleted: () -> Void
    let onNavigateBack: (() -> Void)?
    private let organizationRepository: OrganizationRepository
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var isDeleting = false
    @State private var isShowingEditSheet = false
    @State private var pendingRemovalPostID: String?
    @State private var guestAccessAction: GuestAccessAction?
    @State private var recordedViewKeys = Set<String>()
    @State private var sharePayload: NewsSharePayload?
    @State private var commentText = ""
    @State private var editingCommentID: String?
    @State private var pendingCommentDeleteID: String?
    @State private var commentDeleteErrorMessage: String?
    @State private var permissionOrganization: Organization?
    @FocusState private var isCommentFieldFocused: Bool
    private let detailImageHeight: CGFloat = 220
    private let detailActionButtonSize = AppTheme.iconButtonSize
    private let detailActionButtonRadius = AppTheme.iconButtonRadius
    private let detailSectionSpacing: CGFloat = 13
    private let detailCardPadding: CGFloat = 14
    private let detailCardRadius: CGFloat = 18

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

    private var canEditNews: Bool {
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

        return PermissionService.canEditOrganizationNews(organizationId: organizationID, user: authState.user)
    }

    private var canDeleteNews: Bool {
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
    private var editSheetContent: some View {
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
                GeometryReader { proxy in
                    let contentHorizontalPadding = AppTheme.pageHorizontal
                    let contentWidth = max(proxy.size.width - (contentHorizontalPadding * 2), 0)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: detailSectionSpacing) {
                            newsDetailHeader()

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

                            tagsSection(for: post)
                                .onTapGesture { isCommentFieldFocused = false }

                            relatedSection(for: post)
                                .onTapGesture { isCommentFieldFocused = false }

                            actionsCard(for: post)
                                .onTapGesture { isCommentFieldFocused = false }

                            managementCard(for: post)
                                .onTapGesture { isCommentFieldFocused = false }

                            commentsSection(for: post)
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(.horizontal, contentHorizontalPadding)
                        .padding(.bottom, AppTheme.homeBottomContentPadding + 160)
                    }
                    .frame(width: proxy.size.width)
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        await refreshNewsDetail()
                    }
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppStrings.Common.done) {
                    isCommentFieldFocused = false
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

    private func refreshNewsDetail() async {
        await viewModel.refresh()
        guard let post = viewModel.post(for: postID) else { return }
        await loadPermissionOrganizationIfNeeded(organizationID: post.source.organizationId)
        await viewModel.loadComments(for: postID)
    }

    private func newsDetailHeader() -> some View {
        AppCenteredBrandHeader {
            detailIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                navigateBack()
            }
        } trailingContent: {
            headerActions()
        }
        .zIndex(10)
    }

    private func navigateBack() {
        if let onNavigateBack {
            onNavigateBack()
        } else {
            dismiss()
        }
    }

    private func headerActions() -> some View {
        HStack(spacing: 10) {
            detailIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: AppStrings.Action.share) {
                guard let post = viewModel.post(for: postID) else { return }
                sharePayload = NewsSharePayload(post: post)
            }

            if let post = viewModel.post(for: postID) {
                detailIconButton(
                    systemImage: post.isBookmarked ? "bookmark.fill" : "bookmark",
                    accessibilityLabel: AppStrings.Action.save
                ) {
                    handleBookmark(for: post.id)
                }
            }
        }
    }

    private func detailIconButton(
        systemImage: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        isPlaceholder: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        AppGlassIconButton(
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel,
            role: role,
            isPlaceholder: isPlaceholder
        ) {
            action()
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .zIndex(2)
    }

    private func articleHeader(for post: NewsPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            newsBadge

            Text(post.title)
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(AppTheme.accentPrimary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            metadataRow(for: post)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var newsBadge: some View {
        Label {
            Text(AppStrings.News.detailBadge.uppercased())
                .font(.caption2.weight(.bold))
        } icon: {
            Image(systemName: "newspaper")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(AppTheme.badgePurpleFill, in: Capsule())
    }

    private func metadataRow(for post: NewsPost) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                metadataItems(for: post)
            }

            VStack(alignment: .leading, spacing: 7) {
                metadataItems(for: post)
            }
        }
    }

    private func metadataItems(for post: NewsPost) -> some View {
        Group {
            detailMetadataItem(systemImage: "calendar", text: newsDateText(for: post))
            detailMetadataItem(systemImage: "clock", text: newsTimeText(for: post))
            detailMetadataItem(systemImage: "eye", text: viewCountText(for: post))
        }
    }

    private func detailMetadataItem(systemImage: String, text: String) -> some View {
        Label {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 15, height: 15)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.accentPrimary.opacity(0.88))
    }

    @ViewBuilder
    private func heroImage(for post: NewsPost) -> some View {
        if let imageURL = sanitizedImageURL(post.imageURL) {
            RemoteImageView(
                imageURL: imageURL,
                height: detailImageHeight,
                cornerRadius: AppTheme.imageRadius,
                source: "NewsDetailView",
                placeholderStyle: .glassSkeleton
            )
            .frame(maxWidth: .infinity, minHeight: detailImageHeight, maxHeight: detailImageHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.78))
            )
            .shadow(color: AppTheme.glassShadow(for: colorScheme).opacity(0.55), radius: 8, y: 4)
        }
    }

    private func leadBlock(for post: NewsPost) -> some View {
        detailGlassCard(padding: 12) {
            HStack(alignment: .top, spacing: AppTheme.dashboardSpacing) {
                Image(systemName: "info.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.News.summarySectionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(post.subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func articleBody(for post: NewsPost) -> some View {
        detailGlassCard(padding: detailCardPadding) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.News.bodySectionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)

                Text(post.body)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.accentPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func tagsSection(for post: NewsPost) -> some View {
        if !post.tags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.News.tagsSectionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)

                AppHorizontalChipRow {
                    ForEach(post.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.accentPrimarySoft, in: Capsule())
                    }
                }
            }
        }
    }

    private func actionsCard(for post: NewsPost) -> some View {
        detailGlassCard(padding: 9) {
            HStack(spacing: 12) {
                detailMetricButton(
                    systemImage: post.likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                    count: post.likeCount,
                    accessibilityLabel: post.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like,
                    isSelected: post.likeState.isLiked
                ) {
                    handleLike(for: post.id)
                }
                .disabled(viewModel.pendingNewsLikeIDs.contains(post.id))
                .accessibilityIdentifier("news.like.\(post.id)")
                .accessibilityHint(AppStrings.Common.likes)

                detailMetricButton(
                    systemImage: "bubble.left",
                    count: post.commentCount,
                    accessibilityLabel: AppStrings.Common.comments
                ) {
                    isCommentFieldFocused = true
                }

                Spacer(minLength: 0)

                publisherLine(for: post)
            }
        }
    }

    @ViewBuilder
    private func managementCard(for post: NewsPost) -> some View {
        if canEditNews || canDeleteNews {
            detailGlassCard(padding: 9) {
                HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                    if canEditNews {
                        managementActionButton(systemImage: "pencil", title: AppStrings.Action.edit) {
                            isShowingEditSheet = true
                        }
                        .accessibilityHint(AppStrings.News.detailTitle)
                    }

                    if canDeleteNews {
                        managementActionButton(systemImage: "trash", title: AppStrings.Action.delete, role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(isDeleting)
                        .accessibilityHint(AppStrings.News.detailTitle)
                    }
                }
            }
        }
    }

    private func managementActionButton(
        systemImage: String,
        title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(role == .destructive ? AppTheme.accentDestructive : AppTheme.accentPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func detailMetricButton(
        systemImage: String,
        count: Int,
        accessibilityLabel: String,
        isSelected: Bool = false,
        isPlaceholder: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? AppTheme.accentDestructive : AppTheme.accentPrimary)

                Text("\(count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
            }
            .frame(minWidth: 74, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPlaceholder)
        .opacity(isPlaceholder ? 0.72 : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(count)")
        .accessibilityHint(isPlaceholder ? AppStrings.Action.comingSoon : "")
    }

    private func publisherLine(for post: NewsPost) -> some View {
        Label(newsPublisherText(for: post), systemImage: "person.crop.circle")
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.86))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 190, alignment: .trailing)
            .accessibilityLabel(newsPublisherText(for: post))
    }

    @ViewBuilder
    private func relatedSection(for post: NewsPost) -> some View {
        let relatedPosts = relatedNewsPosts(for: post)
        if !relatedPosts.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(AppStrings.News.relatedSectionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.accentPrimary)

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Text(AppStrings.News.relatedSectionAction)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(relatedPosts) { relatedPost in
                            relatedNewsCard(relatedPost)
                        }
                    }
                }
            }
        }
    }

    private func relatedNewsCard(_ post: NewsPost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL = sanitizedImageURL(post.imageURL) {
                RemoteImageView(
                    imageURL: imageURL,
                    height: 82,
                    cornerRadius: 12,
                    source: "NewsDetailRelated",
                    placeholderStyle: .glassSkeleton
                )
                .overlay(alignment: .topLeading) {
                    Label(AppStrings.News.detailBadge.uppercased(), systemImage: "newspaper")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(AppTheme.accentPrimary, in: Capsule())
                        .padding(7)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(post.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .padding(8)
                        .background(
                            reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassSurface(for: colorScheme),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .background {
                            if !reduceTransparency {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        .padding(7)
                }
            }
        }
        .frame(width: 170, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func relatedNewsPosts(for post: NewsPost) -> [NewsPost] {
        viewModel.posts
            .filter { candidate in
                candidate.id != post.id && sanitizedImageURL(candidate.imageURL) != nil
            }
            .sorted { lhs, rhs in
                if lhs.category == post.category && rhs.category != post.category { return true }
                if lhs.category != post.category && rhs.category == post.category { return false }
                return lhs.publishedAt > rhs.publishedAt
            }
            .prefix(6)
            .map { $0 }
    }

    private func commentsSection(for post: NewsPost) -> some View {
        detailGlassCard(padding: detailCardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.Common.comments)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)

                commentComposer(parentID: post.id)

                if post.comments.isEmpty {
                    Text(AppStrings.Common.noCommentsYet)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(post.comments.enumerated()), id: \.element.id) { index, comment in
                            commentRow(comment)

                            if index < post.comments.count - 1 {
                                Divider()
                                    .padding(.vertical, AppTheme.eventsControlGroupSpacing)
                            }
                        }
                    }
                }
            }
        }
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            commentAvatar(comment)

            VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                Text(sanitizedAuthorName(comment.authorName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                Text(LocalizationStore.dateString(from: comment.createdAt, dateStyle: .short, timeStyle: .short))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                    if canEditComment(comment) || canDeleteComment(comment) {
                        commentActionMenu(for: comment)
                    }
            }

            Text(comment.text)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentActionMenu(for comment: Comment) -> some View {
        Menu {
            if canEditComment(comment) {
                Button(AppStrings.Action.edit, systemImage: "pencil") {
                    editingCommentID = comment.id
                    commentText = comment.text
                    isCommentFieldFocused = true
                }
            }
            if canDeleteComment(comment) {
                Button(AppStrings.Action.delete, systemImage: "trash", role: .destructive) {
                    pendingCommentDeleteID = comment.id
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.Action.delete)
    }

    private func commentComposer(parentID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if authState.isAuthenticated {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(AppStrings.Common.commentInputPlaceholder, text: $commentText, axis: .vertical)
                        .focused($isCommentFieldFocused)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                        )

                    Button {
                        submitComment(parentID: parentID)
                    } label: {
                        Image(systemName: editingCommentID == nil ? "paperplane.fill" : "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.accentPrimary, in: Circle())
                    }
                    .disabled(trimmedCommentText.isEmpty || viewModel.pendingNewsCommentIDs.contains(parentID))
                    .opacity(trimmedCommentText.isEmpty ? 0.55 : 1)
                }

                Text("\(commentText.count)/1000")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Button {
                    guestAccessAction = .comments
                } label: {
                    Label(AppStrings.Common.signInToComment, systemImage: "person.crop.circle.badge.plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trimmedCommentText: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var newsViewTaskID: String {
        "\(postID)-\(authState.user?.id ?? "guest")"
    }

    private func submitComment(parentID: String) {
        guard let user = authState.user else {
            guestAccessAction = .comments
            return
        }
        let text = String(trimmedCommentText.prefix(1000))
        guard !text.isEmpty else { return }
        let editingID = editingCommentID
        Task {
            if let editingID {
                await viewModel.updateComment(postID: parentID, commentID: editingID, text: text)
            } else {
                await viewModel.addComment(to: parentID, text: text, author: user)
            }
            await MainActor.run {
                commentText = ""
                editingCommentID = nil
                isCommentFieldFocused = false
            }
        }
    }

    private func commentAvatar(_ comment: Comment) -> some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentPrimarySoft)
            if let authorPhotoURL = comment.authorPhotoURL, !authorPhotoURL.isEmpty {
                AsyncImage(url: URL(string: authorPhotoURL)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Text(commentInitials(comment))
                            .font(.caption.weight(.bold))
                    }
                }
            } else {
                Text(commentInitials(comment))
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(AppTheme.accentPrimary)
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private func commentInitials(_ comment: Comment) -> String {
        let name = sanitizedAuthorName(comment.authorName)
        return String(name.prefix(1)).uppercased()
    }

    private func canEditComment(_ comment: Comment) -> Bool {
        guard let user = authState.user else { return false }
        return comment.authorId == user.id
    }

    private func canDeleteComment(_ comment: Comment) -> Bool {
        guard let user = authState.user else { return false }
        if comment.authorId == user.id {
            return true
        }
        if PermissionService.canModerate(section: .comments, user: user) || PermissionService.canModerate(section: .news, user: user) {
            return true
        }
        guard let post = viewModel.post(for: postID), let organizationId = post.source.organizationId else {
            return false
        }
        if let organization = organizationForPermissions(organizationID: organizationId) {
            return PermissionService.canModerateOrganizationContent(organization, user: user)
        }
        return PermissionService.canModerateOrganizationComments(organizationId: organizationId, user: user)
    }

    private func organizationForPermissions(organizationID: String) -> Organization? {
        guard permissionOrganization?.id == organizationID else { return nil }
        return permissionOrganization
    }

    @MainActor
    private func loadPermissionOrganizationIfNeeded(organizationID: String?) async {
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
    private func deleteComment(commentID: String) async {
        pendingCommentDeleteID = nil
        await viewModel.deleteComment(postID: postID, commentID: commentID)
        if let error = viewModel.error {
            commentDeleteErrorMessage = readableNewsErrorText(error)
        }
    }

    private func newsDateText(for post: NewsPost) -> String {
        LocalizationStore.dateString(from: post.createdAt, dateStyle: .medium, timeStyle: .none)
    }

    private func newsTimeText(for post: NewsPost) -> String {
        LocalizationStore.dateString(from: post.createdAt, dateStyle: .none, timeStyle: .short)
    }

    private func viewCountText(for post: NewsPost) -> String {
        AppStrings.News.viewCount(post.viewCount)
    }

    private func newsSourceText(for post: NewsPost) -> String {
        if let organizationName = post.source.displayOrganizationName?.trimmingCharacters(in: .whitespacesAndNewlines), !organizationName.isEmpty {
            return organizationName
        }

        return AppStrings.News.missingOrganization
    }

    private func detailGlassCard<Content: View>(padding: CGFloat = 14, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(
            cornerRadius: detailCardRadius,
            material: .ultraThinMaterial,
            surface: AppTheme.glassSurface(for: colorScheme),
            borderOpacity: 0.62,
            shadowRadius: 8,
            shadowY: 4
        )
    }

    private func sanitizedImageURL(_ imageURL: String?) -> String? {
        guard let imageURL = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
            return nil
        }
        return imageURL
    }

    @MainActor
    private func deleteCurrentNews() async {
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

    private func handleLike(for postID: String) {
        guard authState.isAuthenticated else {
            guestAccessAction = .likes
            return
        }

        viewModel.toggleLike(for: postID)
    }

    private func handleBookmark(for postID: String) {
        guard authState.isAuthenticated else {
            guestAccessAction = .bookmarks
            return
        }

        viewModel.toggleBookmark(for: postID)
    }
}

private struct NewsSharePayload: Identifiable {
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

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

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

private struct NewsDeleteSwipeActions: ViewModifier {
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

private struct NewsPresentationModeKey: EnvironmentKey {
    static let defaultValue: NewsPresentationMode = .public
}

extension EnvironmentValues {
    var newsPresentationMode: NewsPresentationMode {
        get { self[NewsPresentationModeKey.self] }
        set { self[NewsPresentationModeKey.self] = newValue }
    }
}
