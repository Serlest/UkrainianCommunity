import SwiftUI

enum FeaturedBannerCarouselSizing {
    case fixedHeight(CGFloat)
    case aspectRatio(CGFloat, maxHeight: CGFloat)

    static let compactHero = FeaturedBannerCarouselSizing.fixedHeight(AppTheme.heroBannerHeight)
    static let responsiveHero = FeaturedBannerCarouselSizing.aspectRatio(16.0 / 9.0, maxHeight: AppTheme.heroBannerHeight)
}

struct FeaturedBannerCarouselView: View {
    let banners: [FeaturedBanner]
    let sizing: FeaturedBannerCarouselSizing
    let onBannerTap: (FeaturedBanner) -> Void
    @State private var selectedBannerID: FeaturedBanner.ID?

    init(
        banners: [FeaturedBanner],
        sizing: FeaturedBannerCarouselSizing = .responsiveHero,
        onBannerTap: @escaping (FeaturedBanner) -> Void
    ) {
        self.banners = banners
        self.sizing = sizing
        self.onBannerTap = onBannerTap
    }

    var body: some View {
        if banners.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                GeometryReader { proxy in
                    TabView(selection: $selectedBannerID) {
                        ForEach(banners) { banner in
                            Button {
                                onBannerTap(banner)
                            } label: {
                                FeaturedBannerCardView(banner: banner)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                            }
                            .buttonStyle(.plain)
                            .tag(Optional(banner.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .frame(height: resolvedHeight)

                FeaturedBannerPageIndicator(
                    count: banners.count,
                    selectedIndex: selectedIndex
                )
            }
            .onAppear(perform: normalizeSelection)
            .onChange(of: banners.map(\.id)) { _, _ in
                normalizeSelection()
            }
            .task(id: rotationTaskID) {
                await scheduleNextRotation()
            }
        }
    }

    private var selectedIndex: Int {
        guard let selectedBannerID,
              let index = banners.firstIndex(where: { $0.id == selectedBannerID }) else {
            return 0
        }
        return index
    }

    private var selectedBanner: FeaturedBanner? {
        guard banners.indices.contains(selectedIndex) else { return nil }
        return banners[selectedIndex]
    }

    private var rotationTaskID: String {
        let slideKeys = banners
            .map { "\($0.id)-\($0.displayDurationSeconds)" }
            .joined(separator: "|")
        return "\(selectedBannerID ?? "none"):\(slideKeys)"
    }

    private var resolvedHeight: CGFloat? {
        switch sizing {
        case let .fixedHeight(height):
            return height
        case let .aspectRatio(aspectRatio, maxHeight):
            guard aspectRatio > 0 else { return maxHeight }
            return min(UIScreen.main.bounds.width / aspectRatio, maxHeight)
        }
    }

    private func normalizeSelection() {
        guard let firstBanner = banners.first else {
            selectedBannerID = nil
            return
        }

        if selectedBannerID == nil || !banners.contains(where: { $0.id == selectedBannerID }) {
            selectedBannerID = firstBanner.id
        }
    }

    private func scheduleNextRotation() async {
        guard banners.count > 1, let selectedBanner else { return }

        let seconds = min(max(selectedBanner.displayDurationSeconds, 3), 12)
        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        guard !Task.isCancelled else { return }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.35)) {
                selectedBannerID = nextBannerID(after: selectedBanner.id)
            }
        }
    }

    private func nextBannerID(after bannerID: FeaturedBanner.ID) -> FeaturedBanner.ID? {
        guard let currentIndex = banners.firstIndex(where: { $0.id == bannerID }) else {
            return banners.first?.id
        }

        let nextIndex = banners.index(after: currentIndex)
        return nextIndex < banners.endIndex ? banners[nextIndex].id : banners.first?.id
    }
}
