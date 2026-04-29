import SwiftUI

private func sanitizedHomeAuthorName(_ rawValue: String) -> String {
    let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
        return AppStrings.NewsEditor.authorFallback
    }

    guard trimmedValue.count >= 20 else {
        return trimmedValue
    }

    guard trimmedValue.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
        return trimmedValue
    }

    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    if trimmedValue.rangeOfCharacter(from: allowedCharacters.inverted) == nil {
        return AppStrings.NewsEditor.authorFallback
    }

    return trimmedValue
}

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel

    private var newsErrorText: String {
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GradientHeroCard(title: AppStrings.Home.title, subtitle: AppStrings.Home.subtitle) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.user.fullName)
                                .font(.headline)
                            Text(viewModel.user.city)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Text(viewModel.user.role.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(AppStrings.Home.highlights)
                        .font(.title3.weight(.semibold))
                    AdaptiveCardGrid(items: viewModel.highlights) { item in
                        CommunityCard {
                            Label(item.title, systemImage: item.systemImage)
                                .font(.headline)
                                .foregroundStyle(AppTheme.primaryBlue)
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(AppStrings.Home.latestNews)
                        .font(.title3.weight(.semibold))

                    if viewModel.isLoading && viewModel.latestNews.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else if viewModel.error != nil && viewModel.latestNews.isEmpty {
                        CommunityCard {
                            Text(newsErrorText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.latestNews.isEmpty {
                        CommunityCard {
                            Text(AppStrings.News.empty)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if viewModel.error != nil {
                            CommunityCard {
                                Text(newsErrorText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(viewModel.latestNews) { post in
                            CommunityCard {
                                Text(post.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(post.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(sanitizedHomeAuthorName(post.authorName))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.Tabs.home)
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(
                userRepository: MockUserRepository(),
                newsRepository: MockNewsRepository(),
                eventRepository: MockEventRepository(),
                organizationRepository: MockOrganizationRepository(),
                marketplaceRepository: MockMarketplaceRepository()
            )
        )
    }
}
