import Foundation

struct AppAnalyticsEvent: Sendable, Equatable {
    let name: AnalyticsEventName
    let parameters: [AnalyticsParameterName: AnalyticsParameterValue]

    init(
        name: AnalyticsEventName,
        parameters: [AnalyticsParameterName: AnalyticsParameterValue] = [:]
    ) {
        self.name = name
        self.parameters = parameters
    }
}
