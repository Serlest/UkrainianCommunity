import Foundation
import SwiftUI

enum FeaturedBannerMeasurementKind: String, Equatable {
    case impression
    case click
}

private struct FeaturedBannerViewportPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct FeaturedBannerViewportModifier: ViewModifier {
    @Binding var frame: CGRect

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: FeaturedBannerViewportPreferenceKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            }
            .onPreferenceChange(FeaturedBannerViewportPreferenceKey.self) { frame = $0 }
    }
}

extension View {
    func featuredBannerViewport(_ frame: Binding<CGRect>) -> some View {
        modifier(FeaturedBannerViewportModifier(frame: frame))
    }
}

struct FeaturedBannerMeasurement: Equatable {
    let id: UUID
    let bannerID: String
    let section: FeaturedBannerVisibleSection
    let kind: FeaturedBannerMeasurementKind
    let occurredAt: Date
}

/// Defines a local exposure. Delivery is deliberately separate: banner metrics
/// require their own disclosed purpose and must never use content-analytics consent.
struct FeaturedBannerExposureTracker {
    static let minimumVisibleFraction = 0.5
    static let minimumDuration: TimeInterval = 1
    static let repeatImpressionInterval: TimeInterval = 30
    static let repeatClickInterval: TimeInterval = 0.8

    private var currentBannerID: String?
    private var visibleSince: Date?
    private var impressionRecordedForExposure = false
    private var lastImpressionAt: [String: Date] = [:]
    private var lastClickAt: [String: Date] = [:]

    static func visibleFraction(of frame: CGRect, within viewport: CGRect) -> Double {
        guard frame.width > 0, frame.height > 0,
              viewport.width > 0, viewport.height > 0 else { return 0 }
        let intersection = frame.intersection(viewport)
        guard !intersection.isNull else { return 0 }
        return Double(intersection.width * intersection.height / (frame.width * frame.height))
    }

    mutating func observe(
        bannerID: String?,
        section: FeaturedBannerVisibleSection,
        visibleFraction: Double,
        isEligible: Bool,
        at now: Date = Date()
    ) -> FeaturedBannerMeasurement? {
        pruneOldTimestamps(at: now)
        guard isEligible, visibleFraction >= Self.minimumVisibleFraction,
              let bannerID, !bannerID.isEmpty else {
            endExposure()
            return nil
        }

        if currentBannerID != bannerID {
            currentBannerID = bannerID
            visibleSince = now
            impressionRecordedForExposure = false
            return nil
        }

        guard !impressionRecordedForExposure,
              let visibleSince,
              now.timeIntervalSince(visibleSince) >= Self.minimumDuration else { return nil }

        impressionRecordedForExposure = true
        guard lastImpressionAt[bannerID].map({ now.timeIntervalSince($0) >= Self.repeatImpressionInterval }) ?? true else {
            return nil
        }
        lastImpressionAt[bannerID] = now
        return FeaturedBannerMeasurement(
            id: UUID(), bannerID: bannerID, section: section, kind: .impression, occurredAt: now
        )
    }

    mutating func click(
        bannerID: String,
        section: FeaturedBannerVisibleSection,
        visibleFraction: Double,
        isEligible: Bool,
        at now: Date = Date()
    ) -> [FeaturedBannerMeasurement] {
        pruneOldTimestamps(at: now)
        guard isEligible, visibleFraction >= Self.minimumVisibleFraction,
              currentBannerID == bannerID,
              lastClickAt[bannerID].map({ now.timeIntervalSince($0) >= Self.repeatClickInterval }) ?? true else {
            return []
        }

        lastClickAt[bannerID] = now
        var measurements: [FeaturedBannerMeasurement] = []
        // A deliberate tap before the one-second timer proves exposure. Count
        // it once so the click cannot be reported without a corresponding view.
        if !impressionRecordedForExposure {
            impressionRecordedForExposure = true
            if lastImpressionAt[bannerID].map({ now.timeIntervalSince($0) >= Self.repeatImpressionInterval }) ?? true {
                lastImpressionAt[bannerID] = now
                measurements.append(FeaturedBannerMeasurement(
                    id: UUID(), bannerID: bannerID, section: section, kind: .impression, occurredAt: now
                ))
            }
        }
        measurements.append(FeaturedBannerMeasurement(
            id: UUID(), bannerID: bannerID, section: section, kind: .click, occurredAt: now
        ))
        return measurements
    }

    private mutating func endExposure() {
        currentBannerID = nil
        visibleSince = nil
        impressionRecordedForExposure = false
    }

    private mutating func pruneOldTimestamps(at now: Date) {
        lastImpressionAt = lastImpressionAt.filter {
            now.timeIntervalSince($0.value) < Self.repeatImpressionInterval
        }
        lastClickAt = lastClickAt.filter {
            now.timeIntervalSince($0.value) < Self.repeatClickInterval
        }
    }
}
