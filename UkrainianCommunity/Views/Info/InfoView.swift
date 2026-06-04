import SwiftUI

struct InfoView: View {
    @ObservedObject var viewModel: InfoViewModel
    let featuredBannerRepository: FeaturedBannerRepository
    let feedbackRepository: FeedbackRepository
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    @Binding var guideBannerCategoryTarget: GuideCategory?
    let scrollResetToken: Int

    init(
        viewModel: InfoViewModel,
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        feedbackRepository: FeedbackRepository = FirestoreFeedbackRepository(),
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        guideBannerCategoryTarget: Binding<GuideCategory?> = .constant(nil),
        scrollResetToken: Int = 0
    ) {
        self.viewModel = viewModel
        self.featuredBannerRepository = featuredBannerRepository
        self.feedbackRepository = feedbackRepository
        self.onFeaturedBannerTap = onFeaturedBannerTap
        _guideBannerCategoryTarget = guideBannerCategoryTarget
        self.scrollResetToken = scrollResetToken
    }

    var body: some View {
        GuideReaderView(
            viewModel: GuideReaderViewModel(repository: FirestoreGuideRepository()),
            featuredBannerRepository: featuredBannerRepository,
            feedbackRepository: feedbackRepository,
            onFeaturedBannerTap: onFeaturedBannerTap,
            guideBannerCategoryTarget: $guideBannerCategoryTarget,
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
