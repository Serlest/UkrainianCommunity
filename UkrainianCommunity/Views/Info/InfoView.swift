import SwiftUI

struct InfoView: View {
    @ObservedObject var viewModel: InfoViewModel
    let bannerService: HomeBannerServiceProtocol

    init(
        viewModel: InfoViewModel,
        bannerService: HomeBannerServiceProtocol = FirestoreHomeBannerService()
    ) {
        self.viewModel = viewModel
        self.bannerService = bannerService
    }

    var body: some View {
        GuideHomeView(
            viewModel: viewModel,
            bannerService: bannerService
        )
    }
}

#Preview {
    NavigationStack {
        InfoView(viewModel: InfoViewModel(repository: MockInfoRepository()))
    }
}
