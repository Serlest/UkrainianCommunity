import Foundation

enum AnalyticsParameterName: String, Sendable, CaseIterable {
    case contentID = "content_id"
    case contentTitle = "content_title"
    case contentType = "content_type"
    case category
    case federalState = "federal_state"
    case regionScope = "region_scope"
    case organizationID = "organization_id"
    case organizationName = "organization_name"
    case isGuest = "is_guest"
    case accountState = "account_state"
    case sourceScreen = "source_screen"
    case language
    case resultsCount = "results_count"
}
