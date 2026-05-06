import SwiftUI

struct NewsListView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: NewsViewModel
    let newsRepository: NewsRepository
    let onNewsPublished: @MainActor () async -> Void
    let onNewsChanged: () -> Void
    @State private var pendingDeletePostID: String?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false
    @State private var isShowingCreateSheet = false

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
        authState.user?.role.permissions.canCreateNews == true
    }

    private var canDeleteNews: Bool {
        authState.user?.role.permissions.canDeleteNews == true
    }

    var body: some View {
        ScrollView {
            if viewModel.posts.isEmpty && viewModel.isLoading {
                VStack {
                    LoadingStateCard(title: nil)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
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
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if viewModel.posts.isEmpty {
                EmptyStateCard(
                    systemImage: "newspaper",
                    title: AppStrings.News.title,
                    message: AppStrings.News.empty
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                VStack(spacing: 16) {
                    if viewModel.error != nil {
                        ErrorStateCard(
                            title: AppStrings.News.title,
                            message: errorText,
                            retryTitle: AppStrings.News.retry
                        ) {
                            Task {
                                await viewModel.refresh()
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    AdaptiveCardGrid(items: viewModel.posts) { post in
                        ZStack(alignment: .bottomTrailing) {
                            NavigationLink {
                                NewsDetailView(viewModel: viewModel, postID: post.id, onNewsDeleted: onNewsChanged)
                            } label: {
                                NewsCard(post: post)
                            }
                            .buttonStyle(.plain)

                            LikeButton(isLiked: post.likeState.isLiked, count: post.likeCount) {
                                viewModel.toggleLike(for: post.id)
                            }
                            .disabled(viewModel.pendingNewsLikeIDs.contains(post.id))
                            .accessibilityLabel(post.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like)
                            .accessibilityHint(AppStrings.Common.likes)
                            .padding(.trailing, 18)
                            .padding(.bottom, 18)
                        }
                        .swipeActions(edge: .trailing) {
                            if canDeleteNews {
                                Button(AppStrings.News.delete, role: .destructive) {
                                    pendingDeletePostID = post.id
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(AppStrings.News.title)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
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
                    Label(sanitizedAuthorName(post.authorName), systemImage: "person")
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
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: NewsViewModel
    let postID: String
    let onNewsDeleted: () -> Void
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var isDeleting = false
    @State private var isShowingEditSheet = false
    @State private var pendingRemovalPostID: String?
    private let detailImageHeight: CGFloat = 260

    private var canEditNews: Bool {
        authState.user?.role.permissions.canEditNews == true
    }

    private var canDeleteNews: Bool {
        authState.user?.role.permissions.canDeleteNews == true
    }

    private func newsCreatedDateText(for post: NewsPost) -> String {
        LocalizationStore.dateString(from: post.createdAt, dateStyle: .medium, timeStyle: .short)
    }

    private var detailCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(post.title)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.primary)

                                if !post.subtitle.isEmpty {
                                    Text(post.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(alignment: .center, spacing: 12) {
                                    Label(sanitizedAuthorName(post.authorName), systemImage: "person")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)

                                    Spacer(minLength: 12)

                                    Label(newsCreatedDateText(for: post), systemImage: "calendar")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(detailCardShape)
                            .overlay(
                                detailCardShape
                                    .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
                            )

                            if let imageURL = post.imageURL {
                                VStack(alignment: .leading, spacing: 0) {
                                    RemoteImageView(
                                        imageURL: imageURL,
                                        height: detailImageHeight,
                                        cornerRadius: 18,
                                        source: "NewsDetailView"
                                    )
                                    .frame(maxWidth: .infinity)
                                    .frame(height: detailImageHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.cardBackground)
                                .clipShape(detailCardShape)
                                .overlay(
                                    detailCardShape
                                        .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
                                )
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text(post.body)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(detailCardShape)
                            .overlay(
                                detailCardShape
                                    .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
                            )

                            HStack(alignment: .center, spacing: 12) {
                                Text(AppStrings.Common.likes)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 0)

                                LikeButton(isLiked: post.likeState.isLiked, count: post.likeCount) {
                                    viewModel.toggleLike(for: post.id)
                                }
                                .disabled(viewModel.pendingNewsLikeIDs.contains(post.id))
                                .accessibilityLabel(post.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like)
                                .accessibilityHint(AppStrings.Common.likes)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(detailCardShape)
                            .overlay(
                                detailCardShape
                                    .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
                            )

                            VStack(alignment: .leading, spacing: 12) {
                                Text(AppStrings.Common.comments)
                                    .font(.headline)

                                if post.comments.isEmpty {
                                    Text(AppStrings.Common.commentsPlaceholder)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(post.comments) { comment in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(sanitizedAuthorName(comment.authorName))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Text(comment.body)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(detailCardShape)
                            .overlay(
                                detailCardShape
                                    .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                        .frame(width: proxy.size.width, alignment: .leading)
                    }
                    .frame(width: proxy.size.width)
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .navigationTitle(AppStrings.News.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEditNews, viewModel.post(for: postID) != nil {
                Button {
                    isShowingEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(AppStrings.Action.edit)
                .accessibilityHint(AppStrings.News.detailTitle)
            }

            if canDeleteNews {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isDeleting)
                .accessibilityLabel(AppStrings.Action.delete)
                .accessibilityHint(AppStrings.News.detailTitle)
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
        .alert(AppStrings.News.deleteFailed, isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button(AppStrings.News.dismissError, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .sheet(isPresented: $isShowingEditSheet) {
            editSheetContent
        }
        .onDisappear {
            guard let pendingRemovalPostID else { return }
            withTransaction(Transaction(animation: nil)) {
                viewModel.removeDeletedNews(id: pendingRemovalPostID)
            }
            self.pendingRemovalPostID = nil
        }
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
}

#Preview("News List") {
    NavigationStack {
        NewsListView(
            viewModel: NewsViewModel(repository: MockNewsRepository()),
            newsRepository: MockNewsRepository(),
            onNewsPublished: {},
            onNewsChanged: {}
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
    }
}
