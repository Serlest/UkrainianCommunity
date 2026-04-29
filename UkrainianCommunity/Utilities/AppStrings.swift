import Foundation

enum AppStrings {
    enum Tabs {
        static var home: String { text("tab.home", "Home") }
        static var news: String { text("tab.news", "News") }
        static var events: String { text("tab.events", "Events") }
        static var community: String { text("tab.community", "Community") }
        static var organizations: String { text("tab.organizations", "Organizations") }
        static var marketplace: String { text("tab.marketplace", "Marketplace") }
        static var info: String { text("tab.info", "Info") }
        static var profile: String { text("tab.profile", "Profile") }
    }

    enum Home {
        static var title: String { text("home.title", "Ukrainian Community Tirol") }
        static var subtitle: String { text("home.subtitle", "A calm, trusted place for updates, events, organizations, and neighbor-to-neighbor support.") }
        static var highlights: String { text("home.highlights", "Community Highlights") }
        static var latestNews: String { text("home.latest_news", "Latest News") }
    }

    enum News {
        static var title: String { text("news.title", "News") }
        static var detailTitle: String { text("news.detail.title", "News Details") }
        static var empty: String { text("news.empty", "No news available yet.") }
        static var retry: String { text("news.retry", "Retry") }
        static var loadNetworkError: String { text("news.error.load.network", "Unable to load news. Check your connection and try again.") }
        static var loadPermissionError: String { text("news.error.load.permission", "You do not have permission to view this news.") }
        static var loadValidationError: String { text("news.error.load.validation", "The news data could not be loaded.") }
        static var loadUnknownError: String { text("news.error.load.unknown", "Something went wrong while loading news.") }
        static var actionPermissionError: String { text("news.error.action.permission", "You do not have permission to perform this action.") }
        static var actionValidationError: String { text("news.error.action.validation", "The news data could not be processed.") }
        static var actionNotFoundError: String { text("news.error.action.not_found", "The selected news item could not be found.") }
        static var actionUnknownError: String { text("news.error.action.unknown", "Something went wrong while processing the news.") }
        static var deleteConfirmation: String { text("news.delete.confirmation", "Delete this news post?") }
        static var delete: String { text("news.delete", "Delete") }
        static var cancel: String { text("news.cancel", "Cancel") }
        static var deleteFailed: String { text("news.delete_failed", "Delete Failed") }
        static var dismissError: String { text("news.dismiss_error", "OK") }
    }

    enum NewsEditor {
        static var title: String { text("news.editor.title", "Create News") }
        static var fieldTitle: String { text("news.editor.field.title", "Title") }
        static var fieldSummary: String { text("news.editor.field.summary", "Summary") }
        static var fieldBody: String { text("news.editor.field.body", "Body") }
        static var selectPhoto: String { text("news.editor.select_photo", "Select Photo") }
        static var publish: String { text("news.editor.publish", "Publish") }
        static var publishing: String { text("news.editor.publishing", "Publishing...") }
        static var uploadingImage: String { text("news.editor.uploading_image", "Uploading image...") }
        static var publishedSuccessfully: String { text("news.editor.success", "News published successfully.") }
        static var titleRequired: String { text("news.editor.validation.title_required", "Title is required.") }
        static var bodyRequired: String { text("news.editor.validation.body_required", "Body is required.") }
        static var imageLoadFailed: String { text("news.editor.image_load_failed", "Failed to load the selected image.") }
        static var imageProcessingFailed: String { text("news.editor.image_processing_failed", "Failed to process the selected image.") }
        static var imageTooLarge: String { text("news.editor.image_too_large", "Image is too large. Please choose a smaller photo.") }
        static var authorFallback: String { text("news.editor.author_fallback", "Unknown author") }
    }

    enum Events {
        static var title: String { text("events.title", "Events") }
        static var register: String { text("events.register", "Register") }
        static var registered: String { text("events.registered", "Registered") }
        static var waitlisted: String { text("events.waitlisted", "Waitlisted") }
    }

    enum Organizations {
        static var title: String { text("organizations.title", "Organizations") }
    }

    enum Marketplace {
        static var title: String { text("marketplace.title", "Marketplace") }
        static var freeGift: String { text("marketplace.free_gift", "Free / Gift") }
        static var phone: String { text("marketplace.contact.phone", "Phone") }
        static var email: String { text("marketplace.contact.email", "Email") }
        static var telegram: String { text("marketplace.contact.telegram", "Telegram") }
    }

    enum Info {
        static var title: String { text("info.title", "Info") }
        static var placeholderTitle: String { text("info.placeholder.title", "Information hub foundation") }
        static var placeholderBody: String { text("info.placeholder.body", "This section is ready for official guidance, practical resources, and trusted local references in a later phase.") }
    }

    enum Community {
        static var title: String { text("community.title", "Community") }
        static var subtitle: String { text("community.subtitle", "Find trusted organizations, local offers, and practical information in one place.") }
    }

    enum Profile {
        static var title: String { text("profile.title", "Profile") }
        static var memberSince: String { text("profile.member_since", "Member since") }
        static var role: String { text("profile.role", "Role") }
        static var accountStatus: String { text("profile.account_status", "Account status") }
        static var capabilities: String { text("profile.capabilities", "Capabilities") }
        static var loadingUserProfile: String { text("profile.loading_user_profile", "Loading user profile...") }
        static var adminTools: String { text("profile.admin_tools", "Admin tools") }
        static var moderationTools: String { text("profile.moderation_tools", "Moderation tools") }
        static var userManagement: String { text("profile.user_management", "User management") }
        static var reviewPendingContent: String { text("profile.review_pending_content", "Review pending content") }
        static var manageNews: String { text("profile.manage_news", "Manage news") }
        static var manageEvents: String { text("profile.manage_events", "Manage events") }
        static var manageOrganizations: String { text("profile.manage_organizations", "Manage organizations") }
        static var manageMarketplace: String { text("profile.manage_marketplace", "Manage marketplace") }
    }

    enum Moderation {
        static var title: String { text("moderation.title", "Moderation Tools") }
        static var subtitle: String { text("moderation.subtitle", "Moderation tools will be available here.") }
    }

    enum UserManagement {
        static var title: String { text("user_management.title", "User Management") }
        static var subtitle: String { text("user_management.subtitle", "User management tools will be available here.") }
        static var viewUsers: String { text("user_management.view_users", "View users") }
        static var blockUser: String { text("user_management.block_user", "Block user") }
        static var assignModerator: String { text("user_management.assign_moderator", "Assign moderator") }
        static var assignAdmin: String { text("user_management.assign_admin", "Assign admin") }
    }

    enum Settings {
        static var title: String { text("settings.title", "Settings") }
        static var language: String { text("settings.language", "Language") }
        static var appearance: String { text("settings.appearance", "Appearance") }
        static var privacyPolicy: String { text("settings.privacy_policy", "Privacy Policy") }
        static var terms: String { text("settings.terms", "Terms") }
        static var placeholder: String { text("settings.placeholder", "Placeholder") }
        static var german: String { text("settings.language.german", "German") }
        static var ukrainian: String { text("settings.language.ukrainian", "Ukrainian") }
        static var system: String { text("settings.appearance.system", "System") }
        static var light: String { text("settings.appearance.light", "Light") }
        static var dark: String { text("settings.appearance.dark", "Dark") }
    }

    enum Roles {
        static var user: String { text("role.user", "User") }
        static var moderator: String { text("role.moderator", "Moderator") }
        static var admin: String { text("role.admin", "Admin") }
        static var owner: String { text("role.owner", "Owner") }
    }

    enum Common {
        static var likes: String { text("common.likes", "Likes") }
        static var comments: String { text("common.comments", "Comments") }
        static var city: String { text("common.city", "City") }
        static var venue: String { text("common.venue", "Venue") }
        static var website: String { text("common.website", "Website") }
        static var contact: String { text("common.contact", "Contact") }
        static var price: String { text("common.price", "Price") }
        static var expires: String { text("common.expires", "Expires") }
        static var status: String { text("common.status", "Status") }
        static var active: String { text("common.active", "Active") }
        static var blocked: String { text("common.blocked", "Blocked") }
        static var draft: String { text("common.draft", "Draft") }
        static var pendingReview: String { text("common.pending_review", "Pending review") }
        static var approved: String { text("common.approved", "Approved") }
        static var rejected: String { text("common.rejected", "Rejected") }
        static var archived: String { text("common.archived", "Archived") }
        static var noItems: String { text("common.no_items", "No items available.") }
        static var notAvailable: String { text("common.not_available", "Not available") }
        static var commentsPlaceholder: String { text("common.comments_placeholder", "Comments UI will be expanded in a later phase.") }
        static var legalPlaceholder: String { text("common.placeholder.legal", "Placeholder") }
    }

    enum Validation {
        static var newsTitleRequired: String { text("validation.news.title_required", "News title is required.") }
        static var newsSubtitleRequired: String { text("validation.news.subtitle_required", "News subtitle is required.") }
        static var newsBodyTooShort: String { text("validation.news.body_too_short", "News body is too short.") }
        static var eventTitleRequired: String { text("validation.event.title_required", "Event title is required.") }
        static var eventDetailsTooShort: String { text("validation.event.details_too_short", "Event details are too short.") }
        static var eventCityRequired: String { text("validation.event.city_required", "Event city is required.") }
        static var eventVenueRequired: String { text("validation.event.venue_required", "Event venue is required.") }
        static var eventDateOrderInvalid: String { text("validation.event.date_order_invalid", "Event end date must be after the start date.") }
        static var marketplaceTitleRequired: String { text("validation.marketplace.title_required", "Marketplace title is required.") }
        static var marketplaceDescriptionTooShort: String { text("validation.marketplace.description_too_short", "Marketplace description is too short.") }
        static var marketplaceCityRequired: String { text("validation.marketplace.city_required", "Marketplace city is required.") }
        static var marketplaceContactRequired: String { text("validation.marketplace.contact_required", "Marketplace contact is required.") }
        static var marketplacePriceInvalid: String { text("validation.marketplace.price_invalid", "Marketplace price must be zero or greater.") }
        static var marketplaceExpirationInvalid: String { text("validation.marketplace.expiration_invalid", "Marketplace expiration date must be in the future.") }
    }

    static func homeHighlightNews(_ count: Int) -> String {
        LocalizationStore.localizedFormat("home.highlight.news", defaultValue: "%lld current community updates", arguments: [count])
    }

    static func homeHighlightEvents(_ count: Int) -> String {
        LocalizationStore.localizedFormat("home.highlight.events", defaultValue: "%lld upcoming gatherings and workshops", arguments: [count])
    }

    static func homeHighlightOrganizations(_ count: Int) -> String {
        LocalizationStore.localizedFormat("home.highlight.organizations", defaultValue: "%lld trusted support groups", arguments: [count])
    }

    static func homeHighlightMarketplace(_ count: Int) -> String {
        LocalizationStore.localizedFormat("home.highlight.marketplace", defaultValue: "%lld neighborhood exchange offers", arguments: [count])
    }

    static func commentLine(author: String, body: String) -> String {
        LocalizationStore.localizedFormat("common.comment_line", defaultValue: "%1$@: %2$@", arguments: [author, body])
    }

    static func contactLine(method: String, value: String) -> String {
        LocalizationStore.localizedFormat("common.contact_line", defaultValue: "%1$@: %2$@", arguments: [method, value])
    }

    private static func text(_ key: String, _ defaultValue: String) -> String {
        LocalizationStore.localizedString(key, defaultValue: defaultValue)
    }
}
