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
                    Spacer(minLength: 0)
                    ProgressView()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if viewModel.posts.isEmpty && viewModel.error != nil {
                NewsStateView(
                    systemImage: "newspaper",
                    title: AppStrings.News.title,
                    subtitle: errorText
                ) {
                    Button(AppStrings.News.retry) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if viewModel.posts.isEmpty {
                NewsStateView(
                    systemImage: "newspaper",
                    title: AppStrings.News.title,
                    subtitle: AppStrings.News.empty
                ) {
                    Button(AppStrings.News.retry) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 16) {
                    if viewModel.error != nil {
                        VStack(spacing: 8) {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button(AppStrings.News.retry) {
                                Task {
                                    await viewModel.refresh()
                                }
                            }
                            .buttonStyle(.bordered)
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
                NavigationLink {
                    NewsEditorView(repository: newsRepository, onPublished: onNewsPublished)
                } label: {
                    Image(systemName: "plus")
                }
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

private struct NewsStateView<ActionContent: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    @ViewBuilder let actionContent: ActionContent

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                actionContent
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
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
    @State private var pendingRemovalPostID: String?
    private let detailImageHeight: CGFloat = 260

    private var canDeleteNews: Bool {
        authState.user?.role.permissions.canDeleteNews == true
    }

    var body: some View {
        Group {
            if let post = viewModel.post(for: postID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GradientHeroCard(title: post.title, subtitle: post.subtitle) {
                            Text(sanitizedAuthorName(post.authorName))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        if let imageURL = post.imageURL {
                            RemoteCardImage(imageURL: imageURL, height: detailImageHeight, cornerRadius: 22, source: "NewsDetailView")
                        }

                        CommunityCard {
                            Text(post.body)
                                .font(.body)
                            LikeButton(isLiked: post.likeState.isLiked, count: post.likeCount) {
                                viewModel.toggleLike(for: post.id)
                            }
                        }

                        CommunityCard {
                            Text(AppStrings.Common.comments)
                                .font(.headline)
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
                            Text(AppStrings.Common.commentsPlaceholder)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .navigationTitle(AppStrings.News.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canDeleteNews {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isDeleting)
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
