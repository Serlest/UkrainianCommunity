import Foundation

final class NoopAnalyticsService: AnalyticsTracking {
    nonisolated init() {}

    nonisolated var isCollectionAvailable: Bool { false }
    nonisolated var isCollectionEnabled: Bool { false }
    nonisolated var collectionScopeID: String? { nil }

    nonisolated func actionCapture(for event: AppAnalyticsEvent) -> AnalyticsActionCapture? { nil }

    nonisolated func track(_ event: AppAnalyticsEvent, actionCapture: AnalyticsActionCapture?) {}

    nonisolated func setCollectionEnabled(_ isEnabled: Bool) {}
}
