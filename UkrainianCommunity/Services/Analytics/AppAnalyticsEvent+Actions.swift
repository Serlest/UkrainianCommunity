import Foundation

extension AppAnalyticsEvent {
    static func newsLike(post: NewsPost, sourceScreen: String = "news_detail") -> AppAnalyticsEvent {
        newsAction(.newsLike, post: post, sourceScreen: sourceScreen)
    }

    static func newsBookmark(post: NewsPost, sourceScreen: String = "news_detail") -> AppAnalyticsEvent {
        newsAction(.newsBookmark, post: post, sourceScreen: sourceScreen)
    }

    static func eventRegister(event: Event, sourceScreen: String = "event_detail") -> AppAnalyticsEvent {
        eventAction(.eventRegister, event: event, sourceScreen: sourceScreen)
    }

    static func eventCancelRegistration(event: Event, sourceScreen: String = "event_detail") -> AppAnalyticsEvent {
        eventAction(.eventCancelRegistration, event: event, sourceScreen: sourceScreen)
    }

    static func eventBookmark(event: Event, sourceScreen: String = "event_detail") -> AppAnalyticsEvent {
        eventAction(.eventBookmark, event: event, sourceScreen: sourceScreen)
    }

    static func organizationFollow(organization: Organization, sourceScreen: String = "organization_detail") -> AppAnalyticsEvent {
        organizationAction(.organizationFollow, organization: organization, sourceScreen: sourceScreen)
    }

    static func organizationUnfollow(organization: Organization, sourceScreen: String = "organization_detail") -> AppAnalyticsEvent {
        organizationAction(.organizationUnfollow, organization: organization, sourceScreen: sourceScreen)
    }

    static func organizationBookmark(organization: Organization, sourceScreen: String = "organization_detail") -> AppAnalyticsEvent {
        organizationAction(.organizationBookmark, organization: organization, sourceScreen: sourceScreen)
    }

    private static func newsAction(_ name: AnalyticsEventName, post: NewsPost, sourceScreen: String) -> AppAnalyticsEvent {
        var parameters = baseContentParameters(
            contentID: post.id,
            contentTitle: post.title,
            contentType: "news",
            category: post.category.rawValue,
            federalState: post.federalState,
            regionScope: post.regionScope,
            sourceScreen: sourceScreen,
            language: .stored
        )
        addString(post.source.displayOrganizationId, for: .organizationID, to: &parameters)
        addString(post.source.displayOrganizationName, for: .organizationName, to: &parameters)
        return AppAnalyticsEvent(name: name, parameters: parameters)
    }

    private static func eventAction(_ name: AnalyticsEventName, event: Event, sourceScreen: String) -> AppAnalyticsEvent {
        var parameters = baseContentParameters(
            contentID: event.id,
            contentTitle: event.title,
            contentType: "event",
            category: event.category.rawValue,
            federalState: event.federalState,
            regionScope: event.regionScope,
            sourceScreen: sourceScreen,
            language: .stored
        )
        addString(event.source.displayOrganizationId, for: .organizationID, to: &parameters)
        addString(event.source.displayOrganizationName, for: .organizationName, to: &parameters)
        return AppAnalyticsEvent(name: name, parameters: parameters)
    }

    private static func organizationAction(_ name: AnalyticsEventName, organization: Organization, sourceScreen: String) -> AppAnalyticsEvent {
        var parameters = baseContentParameters(
            contentID: organization.id,
            contentTitle: organization.name,
            contentType: "organization",
            category: nil,
            federalState: organization.federalState,
            regionScope: organization.regionScope,
            sourceScreen: sourceScreen,
            language: .stored
        )
        parameters[.organizationID] = .string(organization.id)
        addString(organization.name, for: .organizationName, to: &parameters)
        return AppAnalyticsEvent(name: name, parameters: parameters)
    }
}
