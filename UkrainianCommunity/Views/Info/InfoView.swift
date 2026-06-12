import SwiftUI

struct InfoView: View {
    @ObservedObject private var guideReaderViewModel: GuideReaderViewModel
    let featuredBannerRepository: FeaturedBannerRepository
    let featuredBannerCache: FeaturedBannerCache
    let feedbackRepository: FeedbackRepository
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    @Binding var guideBannerCategoryTarget: GuideCategory?
    @Binding var guideMaterialTargetID: String?
    let navigationResetToken: Int
    let scrollResetToken: Int

    init(
        guideReaderViewModel: GuideReaderViewModel? = nil,
        guideReaderRepository: GuideRepositoryProtocol = FirestoreGuideRepository(),
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        featuredBannerCache: FeaturedBannerCache = FeaturedBannerCache(),
        feedbackRepository: FeedbackRepository = FirestoreFeedbackRepository(),
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        guideBannerCategoryTarget: Binding<GuideCategory?> = .constant(nil),
        guideMaterialTargetID: Binding<String?> = .constant(nil),
        navigationResetToken: Int = 0,
        scrollResetToken: Int = 0
    ) {
        _guideReaderViewModel = ObservedObject(
            wrappedValue: guideReaderViewModel ?? GuideReaderViewModel(repository: guideReaderRepository)
        )
        self.featuredBannerRepository = featuredBannerRepository
        self.featuredBannerCache = featuredBannerCache
        self.feedbackRepository = feedbackRepository
        self.onFeaturedBannerTap = onFeaturedBannerTap
        _guideBannerCategoryTarget = guideBannerCategoryTarget
        _guideMaterialTargetID = guideMaterialTargetID
        self.navigationResetToken = navigationResetToken
        self.scrollResetToken = scrollResetToken
    }

    var body: some View {
        GuideReaderView(
            viewModel: guideReaderViewModel,
            featuredBannerRepository: featuredBannerRepository,
            featuredBannerCache: featuredBannerCache,
            feedbackRepository: feedbackRepository,
            onFeaturedBannerTap: onFeaturedBannerTap,
            guideBannerCategoryTarget: $guideBannerCategoryTarget,
            guideMaterialTargetID: $guideMaterialTargetID,
            navigationResetToken: navigationResetToken,
            scrollResetToken: scrollResetToken
        )
    }
}

#Preview {
    NavigationStack {
        InfoView(
            guideReaderRepository: MockGuideRepository(),
            featuredBannerRepository: MockFeaturedBannerRepository()
        )
    }
}
