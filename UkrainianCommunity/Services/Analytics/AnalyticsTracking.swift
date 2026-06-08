import Foundation

protocol AnalyticsTracking {
    func track(_ event: AppAnalyticsEvent)
    func setCollectionEnabled(_ isEnabled: Bool)
}
