import Foundation

extension AppAnalyticsEvent {
    static func newsView(
        contentID: String,
        contentTitle: String,
        category: NewsCategory,
        federalState: AustrianFederalState?,
        regionScope: RegionScope?,
        organizationID: String?,
        sourceScreen: String,
        language: AppLanguage = .stored
    ) -> AppAnalyticsEvent {
        var parameters = baseContentParameters(
            contentID: contentID,
            contentTitle: contentTitle,
            contentType: "news",
            category: category.rawValue,
            federalState: federalState,
            regionScope: regionScope,
            sourceScreen: sourceScreen,
            language: language
        )

        addString(organizationID, for: .organizationID, to: &parameters)
        return AppAnalyticsEvent(name: .newsView, parameters: parameters)
    }

    static func eventView(
        contentID: String,
        contentTitle: String,
        category: EventCategory,
        federalState: AustrianFederalState?,
        regionScope: RegionScope?,
        organizationID: String?,
        sourceScreen: String,
        language: AppLanguage = .stored
    ) -> AppAnalyticsEvent {
        var parameters = baseContentParameters(
            contentID: contentID,
            contentTitle: contentTitle,
            contentType: "event",
            category: category.rawValue,
            federalState: federalState,
            regionScope: regionScope,
            sourceScreen: sourceScreen,
            language: language
        )

        addString(organizationID, for: .organizationID, to: &parameters)
        return AppAnalyticsEvent(name: .eventView, parameters: parameters)
    }

    static func organizationView(
        organizationID: String,
        organizationName: String,
        federalState: AustrianFederalState?,
        regionScope: RegionScope?,
        sourceScreen: String,
        language: AppLanguage = .stored
    ) -> AppAnalyticsEvent {
        var parameters = baseContentParameters(
            contentID: organizationID,
            contentTitle: organizationName,
            contentType: "organization",
            category: nil,
            federalState: federalState,
            regionScope: regionScope,
            sourceScreen: sourceScreen,
            language: language
        )

        parameters[.organizationID] = .string(organizationID)
        addString(organizationName, for: .organizationName, to: &parameters)
        return AppAnalyticsEvent(name: .organizationView, parameters: parameters)
    }

    static func guideArticleView(
        contentID: String,
        contentTitle: String,
        category: GuideCategory,
        federalState: AustrianFederalState?,
        regionScope: RegionScope?,
        sourceScreen: String,
        language: AppLanguage = .stored
    ) -> AppAnalyticsEvent {
        let parameters = baseContentParameters(
            contentID: contentID,
            contentTitle: contentTitle,
            contentType: "guide_article",
            category: category.rawValue,
            federalState: federalState,
            regionScope: regionScope,
            sourceScreen: sourceScreen,
            language: language
        )

        return AppAnalyticsEvent(name: .guideArticleView, parameters: parameters)
    }

    static func baseContentParameters(
        contentID: String,
        contentTitle: String,
        contentType: String,
        category: String?,
        federalState: AustrianFederalState?,
        regionScope: RegionScope?,
        sourceScreen: String,
        language: AppLanguage
    ) -> [AnalyticsParameterName: AnalyticsParameterValue] {
        var parameters: [AnalyticsParameterName: AnalyticsParameterValue] = [
            .contentID: .string(contentID),
            .contentType: .string(contentType),
            .sourceScreen: .string(sourceScreen),
            .language: .string(language.rawValue)
        ]
        let resolvedRegionScope = regionScope ?? (federalState == nil ? nil : .federalState)

        addString(contentTitle, for: .contentTitle, to: &parameters)
        addString(category, for: .category, to: &parameters)
        addString(federalState?.rawValue, for: .federalState, to: &parameters)
        addString(resolvedRegionScope?.rawValue, for: .regionScope, to: &parameters)
        return parameters
    }

    static func addString(
        _ value: String?,
        for name: AnalyticsParameterName,
        to parameters: inout [AnalyticsParameterName: AnalyticsParameterValue]
    ) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        parameters[name] = .string(value)
    }
}
