import SwiftUI

struct InfoView: View {
    @ObservedObject var viewModel: InfoViewModel
    let featuredBannerRepository: FeaturedBannerRepository
    @Binding var navigationPath: [GuideNavigationRoute]
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    let scrollResetToken: Int

    init(
        viewModel: InfoViewModel,
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        navigationPath: Binding<[GuideNavigationRoute]> = .constant([]),
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        scrollResetToken: Int = 0
    ) {
        self.viewModel = viewModel
        self.featuredBannerRepository = featuredBannerRepository
        self.onFeaturedBannerTap = onFeaturedBannerTap
        self.scrollResetToken = scrollResetToken
        _navigationPath = navigationPath
    }

    var body: some View {
        GuideHomeView(
            viewModel: viewModel,
            featuredBannerRepository: featuredBannerRepository,
            navigationPath: $navigationPath,
            onFeaturedBannerTap: onFeaturedBannerTap,
            scrollResetToken: scrollResetToken
        )
    }
}

#Preview {
    NavigationStack {
        InfoView(
            viewModel: InfoViewModel(repository: MockInfoRepository()),
            featuredBannerRepository: MockFeaturedBannerRepository()
        )
    }
}
