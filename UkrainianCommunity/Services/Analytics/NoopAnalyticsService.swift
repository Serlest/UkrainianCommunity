import Foundation

final class NoopAnalyticsService: AnalyticsTracking {
    nonisolated init() {}

    nonisolated func track(_ event: AppAnalyticsEvent) {}

    nonisolated func setCollectionEnabled(_ isEnabled: Bool) {}
}
