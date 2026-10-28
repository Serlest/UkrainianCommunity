import Combine
import CoreMotion
import SwiftUI
import UIKit

@MainActor final class SeasonalMotion {
    private let manager = CMMotionManager()
    private var origin: CGPoint?
    private var filtered = CGPoint.zero

    func setEnabled(_ enabled: Bool) {
        if enabled && !manager.isDeviceMotionActive && manager.isDeviceMotionAvailable {
            origin = nil; filtered = .zero
            manager.deviceMotionUpdateInterval = 1.0 / 30
            if CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) {
                manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
            }
        } else if !enabled {
            manager.stopDeviceMotionUpdates(); origin = nil; filtered = .zero
        }
    }

    func offset() -> CGPoint {
        guard let gravity = manager.deviceMotion?.gravity else { return .zero }
        let current = CGPoint(x: gravity.x, y: gravity.y)
        if origin == nil { origin = current }
        let x = min(1, max(-1, (current.x - (origin?.x ?? 0)) * 2))
        let y = min(1, max(-1, (current.y - (origin?.y ?? 0)) * 2))
        filtered.x += (x - filtered.x) * 0.12
        filtered.y += (y - filtered.y) * 0.12
        return filtered
    }
    deinit { manager.stopDeviceMotionUpdates() }
}

/// Layout reserves a small strip; no artwork can obscure content or intercept a tap.
struct SeasonalDecorationStrip: View {
    let theme: SeasonalTheme
    var preview = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var motion = SeasonalMotion()
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var isVisible = false
    @State private var startedAt = Date()
    @State private var showsArrivalFlight = false
    private var hasAnimatedArtwork: Bool {
        theme.elements.contains { $0.sway > 0 || $0.glow || $0.pngFrames.count > 1 }
    }
    private var canAnimate: Bool {
        hasAnimatedArtwork && isVisible && scenePhase == .active && !reduceMotion && !lowPower && !typeSize.isAccessibilitySize
    }
    private var canTilt: Bool { canAnimate && theme.reactsToTilt && theme.elements.contains { $0.sway > 0 } && (preview || verticalSizeClass != .compact) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !canAnimate)) { context in
            GeometryReader { geometry in
                let scale = min(1, geometry.size.width / 320)
                let phase = canAnimate ? max(0, context.date.timeIntervalSince(startedAt)) : 0
                let tilt = canTilt ? motion.offset() : .zero
                ForEach(Array(theme.elements.enumerated()), id: \.element.id) { index, element in
                    let slot = Double(theme.elements.prefix(index).filter { $0.anchor == element.anchor }.count)
                    let x = element.anchor == .leading ? (26 + slot * 52) * scale : geometry.size.width - (26 + slot * 52) * scale
                    let sway = canAnimate ? sin(phase * 0.75 + Double(index)) * 2 * element.sway * theme.intensity : 0
                    let flying = element.artwork == .bat && element.sway > 0 && showsArrivalFlight && canAnimate && phase < 5
                    let flight = flying ? sin(phase * .pi / 5) * 10 * element.sway * theme.intensity : 0
                    let flap = flying ? sin(phase * .pi / 5) * 0.1 * theme.intensity * element.sway * (1 - cos(phase * 9)) : 0
                    SeasonalArtworkView(element: element, phase: phase, animated: canAnimate)
                        .scaleEffect(x: scale, y: scale * (1 - flap))
                        .rotationEffect(.degrees(Double(tilt.x) * 5 * element.sway * theme.intensity + sway))
                        .offset(x: tilt.x * 3 * element.sway * theme.intensity, y: tilt.y * 2 * element.sway * theme.intensity)
                        .offset(x: flight * (element.anchor == .leading ? 1 : -1))
                        .position(x: x, y: geometry.size.height / 2)
                        .opacity(element.artwork == .web ? 0.8 : 0.75 + theme.intensity * 0.25)
                }
            }
        }
        .frame(height: 52)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            isVisible = true; startedAt = Date(); motion.setEnabled(canTilt)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: theme.timeZoneID) ?? .gmt
            let day = calendar.startOfDay(for: startedAt).timeIntervalSince1970
            let key = "seasonalFlightDay." + theme.id
            showsArrivalFlight = preview || (canAnimate && UserDefaults.standard.double(forKey: key) != day)
            if !preview && showsArrivalFlight { UserDefaults.standard.set(day, forKey: key) }
        }
        .onDisappear { isVisible = false; motion.setEnabled(false) }
        .onChange(of: canTilt) { _, enabled in motion.setEnabled(enabled) }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

struct SeasonalPresentationBar: View {
    @ObservedObject var store: SeasonalStore
    let section: SeasonalSection
    let isEligible: Bool
    @AppStorage("seasonalEffectsEnabled") private var enabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        if enabled && isEligible && verticalSizeClass != .compact && !store.library.themes.isEmpty {
            TimelineView(.animation(minimumInterval: 1, paused: scenePhase != .active)) { context in
                if let theme = store.library.active(at: context.date, section: section) {
                    SeasonalDecorationStrip(theme: theme).id(theme.id)
                }
            }
        }
    }
}

struct SeasonalPreview: View {
    let theme: SeasonalTheme
    var body: some View {
        VStack(spacing: 0) {
            SeasonalDecorationStrip(theme: theme, preview: true)
            HStack {
                AdaptiveBrandLockupView(layout: .horizontal)
                Spacer(minLength: 0)
                Image(systemName: "bell").foregroundStyle(AppTheme.accentPrimaryForeground)
            }.padding(.horizontal, 12).padding(.bottom, 12).dynamicTypeSize(.large)
        }
        .background { AppBackgroundView() }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SeasonalText.value("preview", "Vorschau") + ": " + theme.name)
        .accessibilityIdentifier("seasonal.preview")
    }
}

/// Install inside NavigationStack on the root screen. UIKit TabView does not
/// reliably forward an external inset to the scroll views of its child stacks.
struct SeasonalRootDecoration: ViewModifier {
    @ObservedObject var store: SeasonalStore
    let section: SeasonalSection
    let isEligible: Bool
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            SeasonalPresentationBar(store: store, section: section, isEligible: isEligible)
        }
    }
}
