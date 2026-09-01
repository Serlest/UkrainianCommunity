import SwiftUI

enum FeaturedBannerCarouselSizing {
    case fixedHeight(CGFloat)
    case aspectRatio(CGFloat, maxHeight: CGFloat? = nil)

    static let compactHero = FeaturedBannerCarouselSizing.fixedHeight(AppTheme.heroBannerHeight)
    static let responsiveHero = FeaturedBannerCarouselSizing.aspectRatio(
        16.0 / 9.0,
        maxHeight: AppTheme.featuredBannerMaximumHeight
    )
}

private struct FeaturedBannerAspectLayout: Layout {
    let aspectRatio: CGFloat
    let minimumHeight: CGFloat?
    let maximumHeight: CGFloat?

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }

        let fallbackSize = subview.sizeThatFits(proposal)
        let width = proposal.width ?? fallbackSize.width
        var height = width / max(aspectRatio, 0.01)

        if let minimumHeight {
            height = max(height, minimumHeight)
        }
        if let maximumHeight {
            height = min(height, maximumHeight)
        }

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

struct FeaturedBannerCarouselView: View {
    private static let autoAdvanceAnimation = Animation.easeInOut(duration: 0.88)
    private static let restartFadeAnimation = Animation.easeInOut(duration: 0.22)
    private static let restartFadeNanoseconds: UInt64 = 220_000_000
    private static let restartSettleNanoseconds: UInt64 = 120_000_000
    private static let interactionRetryNanoseconds: UInt64 = 250_000_000

    let banners: [FeaturedBanner]
    let sizing: FeaturedBannerCarouselSizing
    let onBannerTap: (FeaturedBanner) -> Void
    private let actionResolver = FeaturedBannerActionResolver()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selectedBannerID: FeaturedBanner.ID?
    @State private var isUserInteracting = false
    @State private var isRestartingCarousel = false

    init(
        banners: [FeaturedBanner],
        sizing: FeaturedBannerCarouselSizing = .responsiveHero,
        onBannerTap: @escaping (FeaturedBanner) -> Void
    ) {
        self.banners = banners
        self.sizing = sizing
        self.onBannerTap = onBannerTap
        _selectedBannerID = State(initialValue: banners.first?.id)
    }

    var body: some View {
        if banners.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                carouselFrame

                FeaturedBannerPageIndicator(
                    count: banners.count,
                    selectedIndex: selectedIndex,
                    onIncrement: { moveSelection(by: 1) },
                    onDecrement: { moveSelection(by: -1) }
                )
            }
            .opacity(isRestartingCarousel ? 0 : 1)
            .onAppear(perform: normalizeSelection)
            .onChange(of: banners.map(\.id)) { _, _ in
                normalizeSelection()
            }
            .task(id: rotationTaskID) {
                await runRotationLoop()
            }
        }
    }

    @ViewBuilder
    private var carouselFrame: some View {
        switch sizing {
        case let .fixedHeight(height):
            carouselContent
                .frame(height: resolvedMinimumHeight(for: height))
        case let .aspectRatio(aspectRatio, maxHeight):
            FeaturedBannerAspectLayout(
                aspectRatio: aspectRatio,
                minimumHeight: dynamicTypeSize.isAccessibilitySize ? AppTheme.accessibilityHeroMinHeight : nil,
                maximumHeight: resolvedMaximumHeight(maxHeight)
            ) {
                carouselContent
            }
        }
    }

    private func resolvedMaximumHeight(_ configuredMaximum: CGFloat?) -> CGFloat? {
        guard !dynamicTypeSize.isAccessibilitySize else { return nil }
        guard verticalSizeClass == .compact else { return configuredMaximum }
        return min(configuredMaximum ?? .greatestFiniteMagnitude, AppTheme.featuredBannerLandscapeHeight)
    }

    private func resolvedMinimumHeight(for height: CGFloat) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? max(height, AppTheme.accessibilityHeroMinHeight) : height
    }

    private var carouselContent: some View {
        GeometryReader { proxy in
            TabView(selection: $selectedBannerID) {
                ForEach(banners) { banner in
                    bannerSlide(for: banner, size: proxy.size)
                    .tag(Optional(banner.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .simultaneousGesture(interactionGesture)
        }
    }

    @ViewBuilder
    private func bannerSlide(for banner: FeaturedBanner, size: CGSize) -> some View {
        if isActionable(banner) {
            Button {
                onBannerTap(banner)
            } label: {
                bannerContent(for: banner, size: size)
            }
            .buttonStyle(.plain)
        } else {
            bannerContent(for: banner, size: size)
        }
    }

    private func bannerContent(for banner: FeaturedBanner, size: CGSize) -> some View {
        FeaturedBannerCardView(banner: banner)
            .frame(width: size.width, height: size.height)
    }

    private func isActionable(_ banner: FeaturedBanner) -> Bool {
        actionResolver.resolve(banner) != .noAction
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
        let bannerConfiguration = banners
            .map { "\($0.id)-\($0.displayDurationSeconds)" }
            .joined(separator: "|")
        return "\(bannerConfiguration)-reduceMotion:\(reduceMotion)-voiceOver:\(voiceOverEnabled)"
    }

    private var interactionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isUserInteracting {
                    isUserInteracting = true
                }
            }
            .onEnded { _ in
                isUserInteracting = false
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

    private func runRotationLoop() async {
        guard !reduceMotion, !voiceOverEnabled else { return }

        while !Task.isCancelled {
            guard banners.count > 1 else { return }

            guard !isUserInteracting, !isRestartingCarousel, let initialBanner = selectedBanner else {
                try? await Task.sleep(nanoseconds: Self.interactionRetryNanoseconds)
                continue
            }

            let seconds = min(max(initialBanner.displayDurationSeconds, 3), 12)
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard !isUserInteracting, !isRestartingCarousel, let currentBanner = selectedBanner else { continue }

            if isLastBanner(currentBanner.id) {
                await restartAtFirstBanner()
            } else {
                withAnimation(Self.autoAdvanceAnimation) {
                    selectedBannerID = nextBannerID(after: currentBanner.id)
                }
            }
        }
    }

    private func restartAtFirstBanner() async {
        await MainActor.run {
            guard !isUserInteracting, !isRestartingCarousel else { return }
            withAnimation(Self.restartFadeAnimation) {
                isRestartingCarousel = true
            }
        }
        try? await Task.sleep(nanoseconds: Self.restartFadeNanoseconds)
        guard !Task.isCancelled else {
            await clearRestartState()
            return
        }

        await MainActor.run {
            guard !isUserInteracting else {
                isRestartingCarousel = false
                return
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedBannerID = banners.first?.id
            }
        }
        try? await Task.sleep(nanoseconds: Self.restartSettleNanoseconds)
        guard !Task.isCancelled else {
            await clearRestartState()
            return
        }

        await MainActor.run {
            withAnimation(Self.restartFadeAnimation) {
                isRestartingCarousel = false
            }
        }
    }

    private func clearRestartState() async {
        await MainActor.run {
            isRestartingCarousel = false
        }
    }

    private func nextBannerID(after bannerID: FeaturedBanner.ID) -> FeaturedBanner.ID? {
        guard let currentIndex = banners.firstIndex(where: { $0.id == bannerID }) else {
            return banners.first?.id
        }

        let nextIndex = banners.index(after: currentIndex)
        return nextIndex < banners.endIndex ? banners[nextIndex].id : banners.first?.id
    }

    private func moveSelection(by offset: Int) {
        guard banners.count > 1 else { return }
        let nextIndex = min(max(selectedIndex + offset, 0), banners.count - 1)
        guard nextIndex != selectedIndex else { return }
        withAnimation(reduceMotion ? nil : Self.autoAdvanceAnimation) {
            selectedBannerID = banners[nextIndex].id
        }
    }

    private func isLastBanner(_ bannerID: FeaturedBanner.ID) -> Bool {
        banners.last?.id == bannerID
    }
}
