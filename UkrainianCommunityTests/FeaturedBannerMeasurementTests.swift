import CoreGraphics
import Foundation
import Testing
@testable import UkrainianCommunity

struct FeaturedBannerMeasurementTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test @MainActor func queuedEventsSurviveRestartButNeverCrossAccounts() {
        let suite = "banner-measurement-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let measurement = FeaturedBannerMeasurement(
            id: UUID(), bannerID: "banner", section: .home,
            kind: .impression, occurredAt: Date()
        )
        let eventID = measurement.id.uuidString.lowercased()
        let first = BannerMeasurementQueueStore(defaults: defaults, principalID: "account-a")
        first.append(BannerMeasurementQueuedEvent(measurement, consentID: "consent-a"))
        #expect(BannerMeasurementQueueStore(defaults: defaults, principalID: "account-a").first?.id == eventID)
        first.switchPrincipal(to: "account-b")
        #expect(first.first == nil)
        #expect(BannerMeasurementQueueStore(defaults: defaults, principalID: "account-a").first == nil)
    }

    @Test func visibleFractionUsesActualScrollViewport() {
        let banner = CGRect(x: 20, y: 100, width: 300, height: 200)
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 200)
        #expect(FeaturedBannerExposureTracker.visibleFraction(of: banner, within: viewport) == 0.5)
        #expect(FeaturedBannerExposureTracker.visibleFraction(
            of: CGRect(x: 20, y: 300, width: 300, height: 200), within: viewport
        ) == 0)
        #expect(FeaturedBannerExposureTracker.visibleFraction(of: .zero, within: viewport) == 0)
    }

    @Test func impressionNeedsContinuousViewability() {
        var tracker = FeaturedBannerExposureTracker()
        #expect(tracker.observe(bannerID: "banner", section: .home, visibleFraction: 0.49,
                                isEligible: true, at: start) == nil)
        #expect(tracker.observe(bannerID: "banner", section: .home, visibleFraction: 0.50,
                                isEligible: true, at: start) == nil)
        #expect(tracker.observe(bannerID: "banner", section: .home, visibleFraction: 0.50,
                                isEligible: true, at: start.addingTimeInterval(0.99)) == nil)
        let impression = tracker.observe(bannerID: "banner", section: .home, visibleFraction: 0.50,
                                         isEligible: true, at: start.addingTimeInterval(1))
        #expect(impression?.kind == .impression)
        #expect(impression?.section == .home)
        #expect(tracker.observe(bannerID: "banner", section: .home, visibleFraction: 1,
                                isEligible: true, at: start.addingTimeInterval(2)) == nil)
    }

    @Test func tabChangeAndScrollResetExposure() {
        var tracker = FeaturedBannerExposureTracker()
        #expect(tracker.observe(bannerID: "banner", section: .events, visibleFraction: 1,
                                isEligible: true, at: start) == nil)
        #expect(tracker.observe(bannerID: "banner", section: .events, visibleFraction: 1,
                                isEligible: false, at: start.addingTimeInterval(0.8)) == nil)
        #expect(tracker.observe(bannerID: "banner", section: .events, visibleFraction: 1,
                                isEligible: true, at: start.addingTimeInterval(1.2)) == nil)
        #expect(tracker.observe(bannerID: "banner", section: .events, visibleFraction: 0.2,
                                isEligible: true, at: start.addingTimeInterval(1.6)) == nil)
        #expect(tracker.observe(bannerID: "banner", section: .events, visibleFraction: 1,
                                isEligible: true, at: start.addingTimeInterval(2)) == nil)
        #expect(tracker.observe(bannerID: "banner", section: .events, visibleFraction: 1,
                                isEligible: true, at: start.addingTimeInterval(3))?.kind == .impression)
    }

    @Test func rotationAndRepeatIntervalDoNotInflateImpressions() {
        var tracker = FeaturedBannerExposureTracker()
        _ = tracker.observe(bannerID: "a", section: .organizations, visibleFraction: 1,
                            isEligible: true, at: start)
        #expect(tracker.observe(bannerID: "a", section: .organizations, visibleFraction: 1,
                                isEligible: true, at: start.addingTimeInterval(1)) != nil)
        _ = tracker.observe(bannerID: "b", section: .organizations, visibleFraction: 1,
                            isEligible: true, at: start.addingTimeInterval(2))
        #expect(tracker.observe(bannerID: "b", section: .organizations, visibleFraction: 1,
                                isEligible: true, at: start.addingTimeInterval(3)) != nil)
        _ = tracker.observe(bannerID: "a", section: .organizations, visibleFraction: 1,
                            isEligible: true, at: start.addingTimeInterval(4))
        #expect(tracker.observe(bannerID: "a", section: .organizations, visibleFraction: 1,
                                isEligible: true, at: start.addingTimeInterval(5)) == nil)
        _ = tracker.observe(bannerID: "b", section: .organizations, visibleFraction: 1,
                            isEligible: true, at: start.addingTimeInterval(31))
        _ = tracker.observe(bannerID: "a", section: .organizations, visibleFraction: 1,
                            isEligible: true, at: start.addingTimeInterval(32))
        #expect(tracker.observe(bannerID: "a", section: .organizations, visibleFraction: 1,
                                isEligible: true, at: start.addingTimeInterval(33))?.kind == .impression)
    }

    @Test func tapCountsExposureOnceAndRejectsImmediateDoubleTap() {
        var tracker = FeaturedBannerExposureTracker()
        _ = tracker.observe(bannerID: "banner", section: .directory, visibleFraction: 1,
                            isEligible: true, at: start)
        let firstTap = tracker.click(bannerID: "banner", section: .directory, visibleFraction: 1,
                                     isEligible: true, at: start.addingTimeInterval(0.2))
        #expect(firstTap.map(\.kind) == [.impression, .click])
        #expect(Set(firstTap.map(\.id)).count == 2)
        #expect(tracker.click(bannerID: "banner", section: .directory, visibleFraction: 1,
                              isEligible: true, at: start.addingTimeInterval(0.5)).isEmpty)
        #expect(tracker.observe(bannerID: "banner", section: .directory, visibleFraction: 1,
                                isEligible: true, at: start.addingTimeInterval(2)) == nil)
    }

    @Test func tapAtDwellBoundaryRetainsItsImpression() {
        var tracker = FeaturedBannerExposureTracker()
        _ = tracker.observe(bannerID: "banner", section: .home, visibleFraction: 1,
                            isEligible: true, at: start)
        let impression = tracker.observe(bannerID: "banner", section: .home, visibleFraction: 1,
                                         isEligible: true, at: start.addingTimeInterval(1.1))
        let tap = tracker.click(bannerID: "banner", section: .home, visibleFraction: 1,
                                isEligible: true, at: start.addingTimeInterval(1.1))
        #expect(impression?.kind == .impression)
        #expect(tap.map(\.kind) == [.click])
    }
}
