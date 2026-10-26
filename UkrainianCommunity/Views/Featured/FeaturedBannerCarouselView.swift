import SwiftUI
import UIKit

enum FeaturedBannerCarouselSizing {
    case fixedHeight(CGFloat)
    case aspectRatio(CGFloat, maxHeight: CGFloat? = nil)

    static let compactHero = FeaturedBannerCarouselSizing.fixedHeight(AppTheme.heroBannerHeight)
    static let responsiveHero = FeaturedBannerCarouselSizing.aspectRatio(
        16.0 / 9.0,
        maxHeight: AppTheme.featuredBannerMaximumHeight
    )
}

struct FeaturedBannerAspectLayout: Layout {
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
    private static let autoAdvanceAnimation = Animation.easeInOut(duration: 0.42)

    let banners: [FeaturedBanner]
    let sizing: FeaturedBannerCarouselSizing
    let section: FeaturedBannerVisibleSection
    let isActive: Bool
    let selectedFederalState: AustrianFederalState?
    let viewportFrame: CGRect
    let onBannerTap: (FeaturedBanner) -> Void
    let onMeasurement: (FeaturedBannerMeasurement) -> Void
    private let actionResolver = FeaturedBannerActionResolver()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedBannerID: FeaturedBanner.ID?
    @State private var isUserInteracting = false
    @State private var cardHeights: [String: CGFloat] = [:]
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var settleTask: Task<Void, Never>?
    @State private var bannerFrame: CGRect = .zero
    @State private var readyArtworkIDs: Set<String> = []
    @State private var exposureTracker = FeaturedBannerExposureTracker()

    init(
        banners: [FeaturedBanner],
        sizing: FeaturedBannerCarouselSizing = .responsiveHero,
        section: FeaturedBannerVisibleSection,
        isActive: Bool,
        selectedFederalState: AustrianFederalState? = nil,
        viewportFrame: CGRect,
        onBannerTap: @escaping (FeaturedBanner) -> Void,
        onMeasurement: @escaping (FeaturedBannerMeasurement) -> Void = { _ in }
    ) {
        self.banners = banners
        self.sizing = sizing
        self.section = section
        self.isActive = isActive
        self.selectedFederalState = selectedFederalState
        self.viewportFrame = viewportFrame
        self.onBannerTap = onBannerTap
        self.onMeasurement = onMeasurement
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
            .overlay(alignment: .topLeading) {
#if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["UITestBanner14Artwork"] == "1" {
                    let frame = cardFrames[selectedBannerID ?? ""] ?? .zero
                    Text(" ").font(.system(size: 1)).foregroundStyle(.clear)
                        .frame(width: 1, height: 1).accessibilityElement()
                        .accessibilityLabel("Artwork geometry observation")
                        .accessibilityIdentifier("featuredBanner.artworkGeometry")
                        .accessibilityValue(Text(verbatim: "id=\(selectedBannerID ?? "");width=\(frame.width);artwork=\(artworkHeight(for: frame.width))"))
                        .allowsHitTesting(false)
                }
#endif
            }
            .onAppear(perform: normalizeSelection)
            .onChange(of: banners.map(\.id)) { _, _ in
                normalizeSelection()
            }
            .onChange(of: banners.map { "\($0.id):\($0.imageURL ?? "")" }) { _, _ in
                readyArtworkIDs.removeAll()
            }
            .task(id: rotationTaskID) {
                await runRotationLoop()
            }
            .onDisappear { exposureTracker.endExposure(); settleTask?.cancel() }
            .task(id: exposureTaskID) {
                // A new region/visibility context must satisfy its own continuous dwell.
                exposureTracker.endExposure()
                let bannerID = selectedBannerID
                _ = exposureTracker.observe(
                    bannerID: bannerID,
                    section: section,
                    visibleFraction: visibleFraction,
                    isEligible: canMeasureExposure
                )
                guard canMeasureExposure else { return }
                try? await Task.sleep(nanoseconds: UInt64(FeaturedBannerExposureTracker.minimumDuration * 1_000_000_000))
                guard !Task.isCancelled, bannerID == selectedBannerID, canMeasureExposure else { return }
                if let measurement = exposureTracker.observe(
                    bannerID: bannerID,
                    section: section,
                    visibleFraction: visibleFraction,
                    isEligible: true
                ) {
                    emit(measurement)
                }
            }
        }
    }

    private var carouselFrame: some View {
        Group {
            if usesStackedContent {
                carouselContent.frame(height: max(280, cardHeights.values.max() ?? 280))
            } else { switch sizing {
            case let .fixedHeight(height):
                carouselContent
                    .frame(height: resolvedMinimumHeight(for: height))
            case let .aspectRatio(aspectRatio, maxHeight):
                FeaturedBannerAspectLayout(
                    aspectRatio: aspectRatio,
                    minimumHeight: nil,
                    maximumHeight: resolvedMaximumHeight(maxHeight)
                ) {
                    carouselContent
                }
            } }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { bannerFrame = $0 }
    }

    private var usesStackedContent: Bool {
        FeaturedBannerLayoutPolicy.needsStackedContent(typeSize: dynamicTypeSize, width: bannerFrame.width)
            || verticalSizeClass == .compact
    }

    private func artworkHeight(for width: CGFloat) -> CGFloat {
        switch sizing {
        case let .fixedHeight(height): return height
        case let .aspectRatio(ratio, maximum):
            return min(width / max(ratio, 0.01), resolvedMaximumHeight(maximum) ?? .greatestFiniteMagnitude)
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
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(banners) { banner in
                        bannerSlide(for: banner, size: CGSize(width: max(1, proxy.size.width), height: artworkHeight(for: proxy.size.width)))
                            .id(banner.id)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                cardFrames[banner.id] = frame
                            }
                    }
                }.scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $selectedBannerID, anchor: .leading)
            .scrollClipDisabled(false)
            .bannerScrollActivity($isUserInteracting)
            .simultaneousGesture(interactionGesture)
            .accessibilityIdentifier("featuredBanner.carousel")
        }
    }

    @ViewBuilder
    private func bannerSlide(for banner: FeaturedBanner, size: CGSize) -> some View {
        if isActionable(banner) {
            Button {
                guard selectedBannerID == banner.id, !isUserInteracting else { return }
                if let measurement = exposureTracker.observe(
                    bannerID: banner.id,
                    section: section,
                    visibleFraction: visibleFraction,
                    isEligible: canMeasureExposure
                ) {
                    emit(measurement)
                }
                for measurement in exposureTracker.click(
                    bannerID: banner.id,
                    section: section,
                    visibleFraction: visibleFraction,
                    isEligible: canMeasureExposure
                ) {
                    emit(measurement)
                }
                onBannerTap(banner)
            } label: {
                bannerContent(for: banner, size: size)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("featuredBanner.card." + banner.id)
        } else {
            bannerContent(for: banner, size: size).accessibilityIdentifier("featuredBanner.card." + banner.id)
        }
    }

    private func bannerContent(for banner: FeaturedBanner, size: CGSize) -> some View {
        FeaturedBannerCardView(banner: banner, artworkHeight: size.height, forceStackedContent: usesStackedContent) { isReady in
            if isReady {
                readyArtworkIDs.insert(banner.id)
            } else {
                readyArtworkIDs.remove(banner.id)
            }
        }
            .frame(width: size.width)
            .fixedSize(horizontal: false, vertical: usesStackedContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if usesStackedContent, abs((cardHeights[banner.id] ?? 0) - height) > 0.5 { cardHeights[banner.id] = height }
            }
            .frame(width: size.width, alignment: .top)
    }

    private var visibleFraction: Double {
        guard let id = selectedBannerID, let frame = cardFrames[id] else { return 0 }
        return FeaturedBannerExposureTracker.visibleFraction(of: frame, within: viewportFrame.intersection(bannerFrame))
    }

    private var canMeasureExposure: Bool {
        isActive && scenePhase == .active && !isUserInteracting && !hasCoveringModal
            && selectedBannerID.map(readyArtworkIDs.contains) == true
            && visibleFraction >= FeaturedBannerExposureTracker.minimumVisibleFraction
    }

    private var hasCoveringModal: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .filter(\.isKeyWindow)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }

    private func emit(_ measurement: FeaturedBannerMeasurement) {
        var event = measurement
        event.displayRegion = selectedFederalState?.rawValue ?? "allAustria"
        onMeasurement(event)
    }

    private var exposureTaskID: String {
        "\(selectedBannerID ?? "none"):\(canMeasureExposure):\(selectedFederalState?.rawValue ?? "allAustria")"
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
        return "\(bannerConfiguration)-selected:\(selectedBannerID ?? "none")-interaction:\(isUserInteracting)-active:\(isActive)-scene:\(scenePhase)-ready:\(selectedBannerID.map(readyArtworkIDs.contains) ?? false)-reduceMotion:\(reduceMotion)-voiceOver:\(voiceOverEnabled)"
    }

    private var interactionGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { _ in
                if #unavailable(iOS 18.0) {
                    settleTask?.cancel()
                    isUserInteracting = true
                }
            }
            .onEnded { _ in
                if #unavailable(iOS 18.0) {
                    settleTask?.cancel()
                    settleTask = Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        isUserInteracting = false
                    }
                }
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
        guard !reduceMotion, !voiceOverEnabled, isActive, scenePhase == .active,
              !isUserInteracting, banners.count > 1, let initialBanner = selectedBanner,
              readyArtworkIDs.contains(initialBanner.id) else { return }
        let seconds = min(max(initialBanner.displayDurationSeconds, 3), 12)
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        guard !Task.isCancelled, isActive, scenePhase == .active, !isUserInteracting,
              selectedBannerID == initialBanner.id else { return }
        withAnimation(Self.autoAdvanceAnimation) { selectedBannerID = nextBannerID(after: initialBanner.id) }
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


}


private struct BannerScrollActivity: ViewModifier {
    @Binding var moving: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in moving = phase != .idle }
        } else { content }
    }
}
private extension View {
    func bannerScrollActivity(_ moving: Binding<Bool>) -> some View { modifier(BannerScrollActivity(moving: moving)) }
}
