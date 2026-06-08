import Foundation

enum AnalyticsEventName: String, Sendable, CaseIterable {
    case newsView = "news_view"
    case newsLike = "news_like"
    case newsBookmark = "news_bookmark"
    case eventView = "event_view"
    case eventRegister = "event_register"
    case eventCancelRegistration = "event_cancel_registration"
    case eventBookmark = "event_bookmark"
    case organizationView = "organization_view"
    case organizationFollow = "organization_follow"
    case organizationUnfollow = "organization_unfollow"
    case organizationBookmark = "organization_bookmark"
    case guideArticleView = "guide_article_view"
    case searchUsed = "search_used"
    case filterUsed = "filter_used"
    case languageChanged = "language_changed"
    case themeChanged = "theme_changed"
    case analyticsConsentChanged = "analytics_consent_changed"
}
