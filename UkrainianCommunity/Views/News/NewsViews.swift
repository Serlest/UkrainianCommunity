import SwiftUI

struct NewsListView: View {
    @ObservedObject var viewModel: NewsViewModel

    private var errorText: String {
        switch viewModel.error {
        case .network:
            "Unable to load news. Check your connection and try again."
        case .permissionDenied:
            "You do not have permission to view this news."
        case .validationFailed:
            "The news data could not be loaded."
        case .notFound:
            "No news available yet."
        case .unknown:
            "Something went wrong while loading news."
        case nil:
            ""
        }
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView()
                    .padding(.top, 60)
            } else if viewModel.error != nil {
                VStack(spacing: 16) {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        viewModel.reload()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
                .padding(.horizontal, 24)
            } else if viewModel.posts.isEmpty {
                VStack(spacing: 16) {
                    Text("No news available yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        viewModel.reload()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
                .padding(.horizontal, 24)
            } else {
                AdaptiveCardGrid(items: viewModel.posts) { post in
                    VStack(spacing: 10) {
                        NavigationLink {
                            NewsDetailView(viewModel: viewModel, postID: post.id)
                        } label: {
                            NewsCard(post: post)
                        }
                        .buttonStyle(.plain)

                        HStack {
                            Spacer()
                            LikeButton(isLiked: post.likeState.isLiked, count: post.likeCount) {
                                viewModel.toggleLike(for: post.id)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding()
            }
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(AppStrings.News.title)
        .onAppear {
            viewModel.reload()
        }
        .refreshable {
            viewModel.reload()
        }
    }
}

private struct NewsCard: View {
    let post: NewsPost

    var body: some View {
        CommunityCard {
            if let imageURL = post.imageURL {
                NewsRemoteImage(imageURL: imageURL, height: 180)
            }
            Text(post.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(post.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text(post.authorName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryBlue)
            }
        }
    }
}

private struct NewsRemoteImage: View {
    let imageURL: String
    let height: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: imageURL)) { phase in
            switch phase {
            case .empty:
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppTheme.groupedBackground)
                    ProgressView()
                }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppTheme.groupedBackground)
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            @unknown default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct NewsDetailView: View {
    @ObservedObject var viewModel: NewsViewModel
    let postID: String

    var body: some View {
        Group {
            if let post = viewModel.post(for: postID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GradientHeroCard(title: post.title, subtitle: post.subtitle) {
                            Text(post.authorName)
                                .font(.subheadline.weight(.semibold))
                        }

                        if let imageURL = post.imageURL {
                            NewsRemoteImage(imageURL: imageURL, height: 240)
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
                                    Text(comment.authorName)
                                        .font(.subheadline.weight(.semibold))
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
    }
}

#Preview("News List") {
    NavigationStack {
        NewsListView(viewModel: NewsViewModel(repository: MockNewsRepository()))
    }
}

#Preview("News Detail") {
    NavigationStack {
        NewsDetailView(viewModel: NewsViewModel(repository: MockNewsRepository()), postID: MockContentBuilder.newsPosts().first!.id)
    }
}
