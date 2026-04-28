import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel

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
            }
            .padding()
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.Tabs.home)
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
