import SwiftUI

struct InfoView: View {
    @ObservedObject var viewModel: InfoViewModel
    @ObservedObject private var guideReaderViewModel: GuideReaderViewModel
    let featuredBannerRepository: FeaturedBannerRepository
    let feedbackRepository: FeedbackRepository
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    @Binding var guideBannerCategoryTarget: GuideCategory?
    let scrollResetToken: Int

    init(
        viewModel: InfoViewModel,
        guideReaderViewModel: GuideReaderViewModel? = nil,
        guideReaderRepository: GuideRepositoryProtocol = FirestoreGuideRepository(),
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        feedbackRepository: FeedbackRepository = FirestoreFeedbackRepository(),
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        guideBannerCategoryTarget: Binding<GuideCategory?> = .constant(nil),
        scrollResetToken: Int = 0
    ) {
        self.viewModel = viewModel
        _guideReaderViewModel = ObservedObject(
            wrappedValue: guideReaderViewModel ?? GuideReaderViewModel(repository: guideReaderRepository)
        )
        self.featuredBannerRepository = featuredBannerRepository
        self.feedbackRepository = feedbackRepository
        self.onFeaturedBannerTap = onFeaturedBannerTap
        _guideBannerCategoryTarget = guideBannerCategoryTarget
        self.scrollResetToken = scrollResetToken
    }

    var body: some View {
        GuideReaderView(
            viewModel: guideReaderViewModel,
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
            guideReaderRepository: MockGuideRepository(),
            featuredBannerRepository: MockFeaturedBannerRepository()
        )
    }
}
