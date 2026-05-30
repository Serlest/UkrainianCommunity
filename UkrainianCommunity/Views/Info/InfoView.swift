import SwiftUI

struct InfoView: View {
    @ObservedObject var viewModel: InfoViewModel
    let featuredBannerRepository: FeaturedBannerRepository

    init(
        viewModel: InfoViewModel,
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository()
    ) {
        self.viewModel = viewModel
        self.featuredBannerRepository = featuredBannerRepository
    }

    var body: some View {
        GuideHomeView(
            viewModel: viewModel,
            featuredBannerRepository: featuredBannerRepository
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
