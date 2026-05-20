import Foundation

enum AppStrings {
    enum Tabs {
        static var home: String { text("tab.home", "Home") }
        static var events: String { text("tab.events", "Events") }
        static var organizations: String { text("tab.organizations", "Organizations") }
        static var info: String { text("tab.info", "Guide") }
        static var profile: String { text("tab.profile", "Profile") }
    }

    enum Home {
        static var brandTitle: String { text("home.brand_title", "Ukrainian Community") }
        static var brandSubtitle: String { text("home.brand_subtitle", "Austria") }
        static var title: String { text("home.title", "Ukrainian Community Tirol") }
        static var subtitle: String { text("home.subtitle", "A calm, trusted place for updates, events, organizations, and neighbor-to-neighbor support.") }
        static var bannerTitle: String { text("home.banner.title", "Together, stronger") }
        static var bannerSubtitle: String { text("home.banner.subtitle", "Support, information, and opportunities for Ukrainians in Austria.") }
        static var regionAllAustria: String { text("home.region.all_austria", "All Austria") }
        static var highlights: String { text("home.highlights", "Community Highlights") }
        static var feedTitle: String { text("home.feed_title", "Community Feed") }
        static var latestNews: String { text("home.latest_news", "Latest updates") }
        static var filterAll: String { text("home.filter.all", "All") }
        static var filterSubscriptions: String { text("home.filter.subscriptions", "Subscriptions") }
        static var filterFavorites: String { text("home.filter.favorites", "Favorites") }
        static var filterButton: String { text("home.filter.button", "Filter") }
        static var notifications: String { text("home.notifications", "Notifications") }
        static var changeBanner: String { text("home.banner.change", "Change banner image") }
        static var bannerUploadFailed: String { text("home.banner.upload_failed", "Unable to update the banner image.") }
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
        static var editTitle: String { text("news.editor.edit_title", "Edit News") }
        static var fieldTitle: String { text("news.editor.field.title", "Title") }
        static var fieldSummary: String { text("news.editor.field.summary", "Summary") }
        static var fieldBody: String { text("news.editor.field.body", "Body") }
        static var selectPhoto: String { text("news.editor.select_photo", "Select Photo") }
        static var publish: String { text("news.editor.publish", "Publish") }
        static var saveChanges: String { text("news.editor.save_changes", "Save Changes") }
        static var publishing: String { text("news.editor.publishing", "Publishing...") }
        static var uploadingImage: String { text("news.editor.uploading_image", "Uploading image...") }
        static var publishedSuccessfully: String { text("news.editor.success", "News published successfully.") }
        static var updatedSuccessfully: String { text("news.editor.updated_success", "News updated successfully.") }
        static var titleRequired: String { text("news.editor.validation.title_required", "Title is required.") }
        static var bodyRequired: String { text("news.editor.validation.body_required", "Body is required.") }
        static var imageLoadFailed: String { text("news.editor.image_load_failed", "Failed to load the selected image.") }
        static var imageProcessingFailed: String { text("news.editor.image_processing_failed", "Failed to process the selected image.") }
        static var imageTooLarge: String { text("news.editor.image_too_large", "Image is too large. Please choose a smaller photo.") }
        static var authorFallback: String { text("news.editor.author_fallback", "Anonymous") }
    }

    enum Events {
        static var title: String { text("events.title", "Events") }
        static var upcomingTitle: String { text("events.section.upcoming", "Upcoming") }
        static var pastTitle: String { text("events.section.past", "Past") }
        static var filterAll: String { text("events.filter.all", "All") }
        static var filterToday: String { text("events.filter.today", "Today") }
        static var filterThisWeek: String { text("events.filter.this_week", "This week") }
        static var filteredUpcomingEmpty: String { text("events.empty.filtered_upcoming", "No upcoming events match this time range right now.") }
        static var register: String { text("events.register", "Register") }
        static var registered: String { text("events.registered", "Registered") }
        static var waitlisted: String { text("events.waitlisted", "Waitlisted") }
        static var allDay: String { text("events.all_day", "All day") }
        static var empty: String { text("events.empty", "No events available yet.") }
        static var retry: String { text("events.retry", "Retry") }
        static var loadNetworkError: String { text("events.error.load.network", "Unable to load events. Check your connection and try again.") }
        static var loadPermissionError: String { text("events.error.load.permission", "You do not have permission to view these events.") }
        static var loadValidationError: String { text("events.error.load.validation", "The event data could not be loaded.") }
        static var loadUnknownError: String { text("events.error.load.unknown", "Something went wrong while loading events.") }
        static var actionPermissionError: String { text("events.error.action.permission", "You do not have permission to perform this action.") }
        static var actionValidationError: String { text("events.error.action.validation", "The event data could not be processed.") }
        static var actionNotFoundError: String { text("events.error.action.not_found", "The selected event could not be found.") }
        static var actionUnknownError: String { text("events.error.action.unknown", "Something went wrong while processing the event.") }
        static var editorTitle: String { text("events.editor.title", "Create Event") }
        static var editTitle: String { text("events.editor.edit_title", "Edit Event") }
        static var fieldTitle: String { text("events.editor.field.title", "Title") }
        static var fieldSummary: String { text("events.editor.field.summary", "Summary") }
        static var fieldDetails: String { text("events.editor.field.details", "Details") }
        static var fieldDescription: String { text("events.editor.field.description", "Description") }
        static var fieldLocation: String { text("events.editor.field.location", "Location") }
        static var fieldStartDate: String { text("events.editor.field.start_date", "Start Date") }
        static var fieldEndDate: String { text("events.editor.field.end_date", "End Date") }
        static var publish: String { text("events.editor.publish", "Publish") }
        static var saveChanges: String { text("events.editor.save_changes", "Save Changes") }
        static var publishing: String { text("events.editor.publishing", "Publishing...") }
        static var publishedSuccessfully: String { text("events.editor.success", "Event published successfully.") }
        static var updatedSuccessfully: String { text("events.editor.updated_success", "Event updated successfully.") }
        static var summaryRequired: String { text("events.editor.validation.summary_required", "Summary is required.") }
        static var detailsRequired: String { text("events.editor.validation.details_required", "Details are required.") }
        static var descriptionRequired: String { text("events.editor.validation.description_required", "Description is required.") }
        static var invalidDateOrder: String { text("events.editor.validation.invalid_date_order", "End date must be after the start date.") }
        static var deleteConfirmation: String { text("events.delete.confirmation", "Delete this event?") }
        static var delete: String { text("events.delete", "Delete") }
        static var cancel: String { text("events.cancel", "Cancel") }
        static var deleteFailed: String { text("events.delete_failed", "Delete Failed") }
        static var dismissError: String { text("events.dismiss_error", "OK") }
    }

    enum Organizations {
        static var title: String { text("organizations.title", "Organizations") }
        static var detailTitle: String { text("organizations.detail.title", "Organization Details") }
        static var activityTitle: String { text("organizations.activity.title", "Community Activity") }
        static var empty: String { text("organizations.empty", "No organizations available yet.") }
        static var retry: String { text("organizations.retry", "Retry") }
        static var loadNetworkError: String { text("organizations.error.load.network", "Unable to load organizations. Check your connection and try again.") }
        static var loadPermissionError: String { text("organizations.error.load.permission", "You do not have permission to view these organizations.") }
        static var loadValidationError: String { text("organizations.error.load.validation", "The organization data could not be loaded.") }
        static var loadUnknownError: String { text("organizations.error.load.unknown", "Something went wrong while loading organizations.") }
        static var actionPermissionError: String { text("organizations.error.action.permission", "You do not have permission to perform this action.") }
        static var actionValidationError: String { text("organizations.error.action.validation", "The organization data could not be processed.") }
        static var actionNotFoundError: String { text("organizations.error.action.not_found", "The selected organization could not be found.") }
        static var actionUnknownError: String { text("organizations.error.action.unknown", "Something went wrong while processing the organization.") }
        static var editorTitle: String { text("organizations.editor.title", "Create Organization") }
        static var editTitle: String { text("organizations.editor.edit_title", "Edit Organization") }
        static var fieldName: String { text("organizations.editor.field.name", "Name") }
        static var fieldDescription: String { text("organizations.editor.field.description", "Description") }
        static var fieldContactEmail: String { text("organizations.editor.field.contact_email", "Contact Email") }
        static var fieldWebsite: String { text("organizations.editor.field.website", "Website") }
        static var publish: String { text("organizations.editor.publish", "Publish") }
        static var saveChanges: String { text("organizations.editor.save_changes", "Save Changes") }
        static var publishing: String { text("organizations.editor.publishing", "Saving...") }
        static var publishedSuccessfully: String { text("organizations.editor.success", "Organization published successfully.") }
        static var updatedSuccessfully: String { text("organizations.editor.updated_success", "Organization updated successfully.") }
        static var imageSectionTitle: String { text("organizations.editor.image_section", "Image") }
        static var detailsSectionTitle: String { text("organizations.editor.details_section", "Details") }
        static var deleteConfirmation: String { text("organizations.delete.confirmation", "Delete this organization?") }
        static var delete: String { text("organizations.delete", "Delete") }
        static var cancel: String { text("organizations.cancel", "Cancel") }
        static var deleteFailed: String { text("organizations.delete_failed", "Delete Failed") }
        static var dismissError: String { text("organizations.dismiss_error", "OK") }
    }

    enum Info {
        static var title: String { text("info.title", "Guide") }
        static var subtitle: String { text("guide.subtitle", "Curated practical guidance, official references, and everyday orientation for families in Austria.") }
        static var pinnedTitle: String { text("guide.pinned", "Important Now") }
        static var categoriesTitle: String { text("guide.categories", "Categories") }
        static var allCategories: String { text("guide.categories.all", "All") }
        static var allArticlesTitle: String { text("guide.articles", "Articles") }
        static var officialSource: String { text("guide.official_source", "Official source") }
        static var searchPlaceholder: String { text("guide.search", "Search the guide") }
        static var noResults: String { text("guide.no_results", "No guide articles match this search right now.") }
        static var articleDetailTitle: String { text("guide.detail.title", "Guide Article") }
        static var categoryDocuments: String { text("guide.category.documents", "Documents") }
        static var categoryAnmeldung: String { text("guide.category.anmeldung", "Anmeldung") }
        static var categoryWork: String { text("guide.category.work", "Work") }
        static var categoryAMS: String { text("guide.category.ams", "AMS") }
        static var categoryHousing: String { text("guide.category.housing", "Housing") }
        static var categoryMedicine: String { text("guide.category.medicine", "Medicine") }
        static var categoryChildren: String { text("guide.category.children", "Children") }
        static var categoryEducation: String { text("guide.category.education", "Education") }
        static var categoryBusiness: String { text("guide.category.business", "Business") }
        static var categoryContacts: String { text("guide.category.contacts", "Contacts") }
        static var categoryEmergency: String { text("guide.category.emergency", "Emergency") }
    }

    enum Profile {
        static var title: String { text("profile.title", "Profile") }
        static var guestOverline: String { text("profile.guest.overline", "Guest Access") }
        static var guestTitle: String { text("profile.guest.title", "Use more with an account") }
        static var guestMessage: String { text("profile.guest.message", "Sign in to save likes and register for events.") }
        static var accountSection: String { text("profile.account_section", "Account") }
        static var accountSummary: String { text("profile.account_summary", "Personal account") }
        static var appManagement: String { text("profile.app_management", "App Management") }
        static var appManagementSubtitle: String { text("profile.app_management.subtitle", "Moderation, publishing, and administration tools are grouped here according to your role.") }
        static var myProfile: String { text("profile.my_profile", "My Profile") }
        static var myActivity: String { text("profile.my_activity", "My Activity") }
        static var activitySubtitle: String { text("profile.activity.subtitle", "Event registrations and saved activity appear here.") }
        static var activitySectionSummary: String { text("profile.activity.section_summary", "Your account activity in one place.") }
        static var myRegistrations: String { text("profile.my_registrations", "My Registrations") }
        static var registrationsLoading: String { text("profile.registrations.loading", "Loading your registrations…") }
        static var registrationsEmptySummary: String { text("profile.registrations.empty_summary", "You are not registered for any events yet.") }
        static var registrationsEmptyMessage: String { text("profile.registrations.empty_message", "When you register for an event, it will appear here so you can revisit details or cancel later.") }
        static var myOrganizations: String { text("profile.my_organizations", "My Organizations") }
        static var organizationsSectionSubtitle: String { text("profile.organizations.subtitle", "Organization roles will appear here when they are assigned.") }
        static var organizationsSectionSummary: String { text("profile.organizations.section_summary", "Organization access linked to your account.") }
        static var organizationManagement: String { text("profile.organization_management", "Organization Management") }
        static var organizationManagementSubtitle: String { text("profile.organization_management.subtitle", "Manage the organizations you help lead and publish organization-owned updates.") }
        static var contentManagement: String { text("profile.content_management", "Content Management") }
        static var contentManagementSubtitle: String { text("profile.content_management.subtitle", "Manage app-owned community news and events.") }
        static var appAdministration: String { text("profile.app_administration", "App Administration") }
        static var feedbackSupport: String { text("profile.feedback_support", "Feedback & Support") }
        static var manageAppNews: String { text("profile.manage_app_news", "Manage app News") }
        static var manageAppEvents: String { text("profile.manage_app_events", "Manage app Events") }
        static var createOrganizationNews: String { text("profile.create_organization_news", "Create organization News") }
        static var createOrganizationEvent: String { text("profile.create_organization_event", "Create organization Event") }
        static var editOrganizationDetails: String { text("profile.edit_organization_details", "Edit organization details") }
        static var noManagedOrganizations: String { text("profile.no_managed_organizations", "No organizations are assigned to you yet.") }
        static var editProfile: String { text("profile.edit", "Edit Profile") }
        static var editProfileSubtitle: String { text("profile.edit.subtitle", "Keep your personal details up to date so your account card stays clear and trustworthy.") }
        static var fullName: String { text("profile.full_name", "Full name") }
        static var displayName: String { text("profile.display_name", "Display name") }
        static var bio: String { text("profile.bio", "Bio") }
        static var changeAvatar: String { text("profile.change_avatar", "Change photo") }
        static var avatarSubtitle: String { text("profile.avatar_subtitle", "Choose a square-friendly photo for your account card. You can always change it later.") }
        static var avatarSelectionFailed: String { text("profile.avatar_selection_failed", "The selected photo could not be loaded.") }
        static var avatarLoading: String { text("profile.avatar_loading", "Preparing the selected photo…") }
        static var avatarUploading: String { text("profile.avatar_uploading", "Uploading your profile photo…") }
        static var avatarReadyToSave: String { text("profile.avatar_ready_to_save", "Your new photo is ready. Save the profile to apply it everywhere in the app.") }
        static var avatarUploadFailed: String { text("profile.avatar_upload_failed", "The profile photo could not be uploaded right now. Check your connection and try again.") }
        static var emailReadOnlyHint: String { text("profile.email_read_only_hint", "Your email address is managed through account sign-in and cannot be changed here yet.") }
        static var telegramUsername: String { text("profile.telegram", "Telegram username") }
        static var region: String { text("profile.region", "Region") }
        static var saveProfile: String { text("profile.save", "Save") }
        static var savingProfile: String { text("profile.saving", "Saving…") }
        static var savingProfileMessage: String { text("profile.saving_message", "Saving your profile and applying updates…") }
        static var noProfileChanges: String { text("profile.no_changes", "Make a change before saving.") }
        static var profileSaved: String { text("profile.saved", "Profile updated.") }
        static var profileSaveFailed: String { text("profile.save_failed", "Unable to save profile right now.") }
        static var displayNameRequired: String { text("profile.validation.display_name_required", "Display name is required.") }
        static var memberSince: String { text("profile.member_since", "Member since") }
        static var role: String { text("profile.role", "Role") }
        static var accountStatus: String { text("profile.account_status", "Account status") }
        static var capabilities: String { text("profile.capabilities", "Capabilities") }
        static var eventRegistration: String { text("profile.capability.event_registration", "Event registration") }
        static var loadingUserProfile: String { text("profile.loading_user_profile", "Loading user profile...") }
        static var adminTools: String { text("profile.admin_tools", "Admin tools") }
        static var moderationTools: String { text("profile.moderation_tools", "Moderation tools") }
        static var userManagement: String { text("profile.user_management", "User management") }
        static var reviewPendingContent: String { text("profile.review_pending_content", "Review pending content") }
        static var manageNews: String { text("profile.manage_news", "Manage news") }
        static var manageEvents: String { text("profile.manage_events", "Manage events") }
        static var manageOrganizations: String { text("profile.manage_organizations", "Manage organizations") }
        static var signOut: String { text("profile.sign_out", "Sign Out") }
        static var signOutConfirmTitle: String { text("profile.sign_out.confirm_title", "Sign out?") }
        static var signOutConfirmMessage: String { text("profile.sign_out.confirm_message", "You will return to guest browsing and protected actions will require sign-in again.") }
        static var signOutFailed: String { text("profile.sign_out.failed", "We couldn’t sign you out right now.") }
        static var accountSectionSummary: String { text("profile.account.section_summary", "Your personal details, account state, and photo live here.") }
        static var guestSectionSummary: String { text("profile.guest.section_summary", "Browse publicly now, then sign in only when you need an account feature.") }
    }

    enum Feedback {
        static var title: String { text("feedback.title", "Feedback") }
        static var subtitle: String { text("feedback.subtitle", "Send a short note to the team.") }
        static var fieldType: String { text("feedback.field.type", "Type") }
        static var fieldMessage: String { text("feedback.field.message", "Message") }
        static var submit: String { text("feedback.submit", "Send Feedback") }
        static var submitted: String { text("feedback.submitted", "Feedback sent. Thank you.") }
        static var submitFailed: String { text("feedback.submit_failed", "Unable to send feedback right now.") }
        static var messageRequired: String { text("feedback.validation.message_required", "Please enter a message.") }
        static var typeQuestion: String { text("feedback.type.question", "Question") }
        static var typeSuggestion: String { text("feedback.type.suggestion", "Suggestion") }
        static var typeBug: String { text("feedback.type.bug", "Bug") }
        static var typeReport: String { text("feedback.type.report", "Report") }
    }

    enum Moderation {
        static var title: String { text("moderation.title", "Moderation Tools") }
        static var subtitle: String { text("moderation.subtitle", "Review pending community content before it becomes visible to everyone.") }
        static var empty: String { text("moderation.empty", "No pending items right now.") }
        static var retry: String { text("moderation.retry", "Retry") }
        static var approve: String { text("moderation.approve", "Approve") }
        static var reject: String { text("moderation.reject", "Reject") }
        static var typeNews: String { text("moderation.type.news", "News") }
        static var typeEvent: String { text("moderation.type.event", "Event") }
        static var typeOrganization: String { text("moderation.type.organization", "Organization") }
        static var loadNetworkError: String { text("moderation.error.load.network", "Unable to load pending content. Check your connection and try again.") }
        static var loadPermissionError: String { text("moderation.error.load.permission", "You do not have permission to access moderation tools.") }
        static var loadValidationError: String { text("moderation.error.load.validation", "The pending content could not be loaded.") }
        static var loadUnknownError: String { text("moderation.error.load.unknown", "Something went wrong while loading moderation items.") }
        static var actionNetworkError: String { text("moderation.error.action.network", "Unable to update moderation status. Check your connection and try again.") }
        static var actionPermissionError: String { text("moderation.error.action.permission", "You do not have permission to update moderation status.") }
        static var actionValidationError: String { text("moderation.error.action.validation", "The moderation update could not be processed.") }
        static var actionUnknownError: String { text("moderation.error.action.unknown", "Something went wrong while updating moderation status.") }
    }

    enum UserManagement {
        static var title: String { text("user_management.title", "User Management") }
        static var subtitle: String { text("user_management.subtitle", "Review user role records that still need roles migration backfill.") }
        static var viewUsers: String { text("user_management.view_users", "View users") }
        static var blockUser: String { text("user_management.block_user", "Block user") }
        static var assignModerator: String { text("user_management.assign_moderator", "Assign moderator") }
        static var assignAdmin: String { text("user_management.assign_admin", "Assign admin") }
        static var retry: String { text("user_management.retry", "Retry") }
        static var empty: String { text("user_management.empty", "No roles backfill issues found.") }
        static var permission: String { text("user_management.permission", "You do not have permission to view roles audit diagnostics.") }
        static var loadError: String { text("user_management.load_error", "Unable to load user diagnostics right now.") }
        static var uid: String { text("user_management.uid", "UID") }
        static var legacyRole: String { text("user_management.legacy_role", "Legacy Role") }
        static var globalRole: String { text("user_management.global_role", "Global Role") }
        static var moderatorSections: String { text("user_management.moderator_sections", "Moderator Sections") }
        static var accountStatus: String { text("user_management.account_status", "Account Status") }
        static var issue: String { text("user_management.issue", "Issue") }
        static var issueModeratorSectionsMissing: String { text("user_management.issue.moderator_sections_missing", "Legacy moderator has no assigned sections") }
        static var issueAdminGlobalRoleMismatch: String { text("user_management.issue.admin_global_role_mismatch", "Legacy admin is not mapped to Top Admin") }
        static var issueOwnerGlobalRoleMismatch: String { text("user_management.issue.owner_global_role_mismatch", "Legacy owner is not mapped to Owner") }
        static var issueUserGlobalRoleMissing: String { text("user_management.issue.user_global_role_missing", "Legacy user is missing global role") }
        static var issueBlockedStatusMismatch: String { text("user_management.issue.blocked_status_mismatch", "Blocked user still has active account status") }
    }

    enum FederalStates {
        static func title(for state: AustrianFederalState) -> String {
            switch state {
            case .burgenland:
                text("federal_state.burgenland", "Burgenland")
            case .kaernten:
                text("federal_state.kaernten", "Kaernten")
            case .niederoesterreich:
                text("federal_state.niederoesterreich", "Niederoesterreich")
            case .oberoesterreich:
                text("federal_state.oberoesterreich", "Oberoesterreich")
            case .salzburg:
                text("federal_state.salzburg", "Salzburg")
            case .steiermark:
                text("federal_state.steiermark", "Steiermark")
            case .tirol:
                text("federal_state.tirol", "Tirol")
            case .vorarlberg:
                text("federal_state.vorarlberg", "Vorarlberg")
            case .wien:
                text("federal_state.wien", "Wien")
            }
        }
    }

    enum Settings {
        static var title: String { text("settings.title", "Settings") }
        static var language: String { text("settings.language", "Language") }
        static var appearance: String { text("settings.appearance", "Appearance") }
        static var privacyPolicy: String { text("settings.privacy_policy", "Privacy Policy") }
        static var terms: String { text("settings.terms", "Terms") }
        static var placeholder: String { text("settings.placeholder", "Placeholder") }
        static var preferencesSubtitle: String { text("settings.preferences.subtitle", "Adjust the app language and appearance for this device.") }
        static var legalSection: String { text("settings.legal_section", "Legal") }
        static var legalSectionSubtitle: String { text("settings.legal_section.subtitle", "Review the current product terms and privacy information.") }
        static var sessionSection: String { text("settings.session_section", "Session") }
        static var sessionSubtitle: String { text("settings.session.subtitle", "You can sign out at any time and return to guest browsing.") }
        static var german: String { text("settings.language.german", "German") }
        static var ukrainian: String { text("settings.language.ukrainian", "Ukrainian") }
        static var system: String { text("settings.appearance.system", "System") }
        static var light: String { text("settings.appearance.light", "Light") }
        static var dark: String { text("settings.appearance.dark", "Dark") }
    }

    enum Legal {
        static var versionLabel: String { text("legal.version_label", "Version %@") }
        static var lastUpdatedLabel: String { text("legal.last_updated_label", "Last updated %@") }

        static var termsIntroTitle: String { text("legal.terms.intro.title", "Using the app") }
        static var termsIntroBody: String { text("legal.terms.intro.body", "Ukrainian Community Tirol helps people discover public updates, events, organizations, and practical guide content. By using the app with an account, you agree to use it lawfully, respectfully, and only for its intended community purpose.") }
        static var termsAccountTitle: String { text("legal.terms.account.title", "Account responsibilities") }
        static var termsAccountBody: String { text("legal.terms.account.body", "You are responsible for the accuracy of the profile details you provide, for keeping your sign-in credentials private, and for the actions taken through your account. You may not impersonate other people or create accounts to evade moderation.") }
        static var termsContentTitle: String { text("legal.terms.content.title", "Community content and moderation") }
        static var termsContentBody: String { text("legal.terms.content.body", "User-submitted content can be reviewed, limited, or removed when it is misleading, unsafe, unlawful, abusive, discriminatory, spam-like, or unrelated to the app’s purpose. Roles with moderation responsibilities may manage content according to the project’s moderation model.") }
        static var termsAvailabilityTitle: String { text("legal.terms.availability.title", "Availability and changes") }
        static var termsAvailabilityBody: String { text("legal.terms.availability.body", "We may improve, change, or temporarily limit parts of the service, including community features and account access, to maintain reliability, security, and compliance. We do not promise uninterrupted availability.") }
        static var termsLiabilityTitle: String { text("legal.terms.liability.title", "Information and responsibility") }
        static var termsLiabilityBody: String { text("legal.terms.liability.body", "The app is intended to support orientation and community coordination. It does not replace legal, medical, financial, or official government advice. Users remain responsible for decisions they make based on shared information.") }

        static var privacyIntroTitle: String { text("legal.privacy.intro.title", "What we store") }
        static var privacyIntroBody: String { text("legal.privacy.intro.body", "When you create an account, we store the profile fields needed for the app to function: email address, display name, optional Telegram username, selected federal state, role/status fields, and timestamps related to account creation and consent.") }
        static var privacyUsageTitle: String { text("legal.privacy.usage.title", "Why we use your data") }
        static var privacyUsageBody: String { text("legal.privacy.usage.body", "We use account data to authenticate you, show your profile, apply permissions, support feedback and event registration, and keep the community space safe through moderation and abuse prevention.") }
        static var privacyStorageTitle: String { text("legal.privacy.storage.title", "Storage and service providers") }
        static var privacyStorageBody: String { text("legal.privacy.storage.body", "This app uses Firebase services for authentication, database storage, and media storage. Data is processed only to deliver the app’s features, maintain security, and support internal operations.") }
        static var privacySharingTitle: String { text("legal.privacy.sharing.title", "Sharing and visibility") }
        static var privacySharingBody: String { text("legal.privacy.sharing.body", "We do not sell your personal data. Some profile information and user-generated content may be visible inside the app where needed for community features. Administrative and moderation roles may access relevant records to enforce rules and manage the service.") }
        static var privacyRightsTitle: String { text("legal.privacy.rights.title", "Your choices") }
        static var privacyRightsBody: String { text("legal.privacy.rights.body", "You can update supported profile fields in the app. If you need help with account data, moderation questions, or deletion requests, contact the project team through the provided support channel.") }
        static var screenIntro: String { text("legal.screen_intro", "These in-app documents describe the current product terms and privacy handling for internal and TestFlight-style use.") }
    }

    enum Roles {
        static var user: String { text("role.user", "User") }
        static var moderator: String { text("role.moderator", "Moderator") }
        static var admin: String { text("role.admin", "Admin") }
        static var owner: String { text("role.owner", "Owner") }
        static var topAdmin: String { text("role.top_admin", "Top Admin") }
        static var appModerator: String { text("role.app_moderator", "App Moderator") }
    }

    enum Common {
        static var app: String { text("common.app", "App") }
        static var ok: String { text("common.ok", "OK") }
        static var cancel: String { text("common.cancel", "Cancel") }
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

    enum Action {
        static var create: String { text("action.create", "Create") }
        static var edit: String { text("action.edit", "Edit") }
        static var delete: String { text("action.delete", "Delete") }
        static var like: String { text("action.like", "Like") }
        static var unlike: String { text("action.unlike", "Unlike") }
        static var register: String { text("action.register", "Register") }
        static var cancelRegistration: String { text("action.cancel_registration", "Cancel Registration") }
        static var saveChanges: String { text("action.save_changes", "Save Changes") }
    }

    enum Validation {
        static var authEmailRequired: String { text("validation.auth.email_required", "Email is required.") }
        static var authEmailInvalid: String { text("validation.auth.email_invalid", "Enter a valid email address.") }
        static var authPasswordTooShort: String { text("validation.auth.password_too_short", "Password must be at least 8 characters.") }
        static var authPasswordMismatch: String { text("validation.auth.password_mismatch", "Passwords do not match.") }
        static var authDisplayNameRequired: String { text("validation.auth.display_name_required", "Display name is required.") }
        static var authTermsRequired: String { text("validation.auth.terms_required", "You need to accept the Terms of Use.") }
        static var authPrivacyRequired: String { text("validation.auth.privacy_required", "You need to accept the Privacy Policy.") }
        static var newsTitleRequired: String { text("validation.news.title_required", "News title is required.") }
        static var newsSubtitleRequired: String { text("validation.news.subtitle_required", "News subtitle is required.") }
        static var newsBodyTooShort: String { text("validation.news.body_too_short", "News body is too short.") }
        static var eventTitleRequired: String { text("validation.event.title_required", "Event title is required.") }
        static var eventDetailsTooShort: String { text("validation.event.details_too_short", "Event details are too short.") }
        static var eventCityRequired: String { text("validation.event.city_required", "Event city is required.") }
        static var eventVenueRequired: String { text("validation.event.venue_required", "Event venue is required.") }
        static var eventDateOrderInvalid: String { text("validation.event.date_order_invalid", "Event end date must be after the start date.") }
        static var organizationNameRequired: String { text("validation.organization.name_required", "Organization name is required.") }
        static var organizationDescriptionTooShort: String { text("validation.organization.description_too_short", "Organization description is too short.") }
        static var organizationCityRequired: String { text("validation.organization.city_required", "Organization city is required.") }
        static var organizationEmailInvalid: String { text("validation.organization.email_invalid", "Contact email must be valid.") }
        static var organizationWebsiteInvalid: String { text("validation.organization.website_invalid", "Website must start with http:// or https://.") }
    }

    enum Auth {
        static var title: String { text("auth.title", "Account") }
        static var landingTitle: String { text("auth.landing.title", "Welcome") }
        static var landingSubtitle: String { text("auth.landing.subtitle", "Create an account or sign in to save likes, register for events, send feedback, and manage content if your role allows it.") }
        static var signIn: String { text("auth.sign_in", "Sign In") }
        static var createAccount: String { text("auth.create_account", "Create Account") }
        static var email: String { text("auth.email", "Email") }
        static var password: String { text("auth.password", "Password") }
        static var passwordRepeat: String { text("auth.password_repeat", "Repeat Password") }
        static var displayName: String { text("auth.display_name", "Display Name") }
        static var telegramUsername: String { text("auth.telegram", "Telegram Username") }
        static var forgotPassword: String { text("auth.forgot_password", "Forgot Password?") }
        static var sendResetLink: String { text("auth.send_reset_link", "Send Reset Link") }
        static var resetPasswordTitle: String { text("auth.reset_password.title", "Reset Password") }
        static var resetPasswordSubtitle: String { text("auth.reset_password.subtitle", "Enter the email linked to your account and we will send a reset link.") }
        static var resetPasswordSuccess: String { text("auth.reset_password.success", "The reset link has been sent.") }
        static var registerTitle: String { text("auth.register.title", "Create Account") }
        static var loginTitle: String { text("auth.login.title", "Sign In") }
        static var loginSubtitle: String { text("auth.login.subtitle", "Use your account email and password.") }
        static var signInAction: String { text("auth.sign_in.action", "Sign In") }
        static var createAccountAction: String { text("auth.create_account.action", "Create Account") }
        static var signingIn: String { text("auth.signing_in", "Signing In...") }
        static var creatingAccount: String { text("auth.creating_account", "Creating Account...") }
        static var resetPasswordSending: String { text("auth.reset_password.sending", "Sending...") }
        static var federalState: String { text("auth.federal_state", "Federal State") }
        static var signInInstead: String { text("auth.sign_in_instead", "Already have an account? Sign In") }
        static var createAccountInstead: String { text("auth.create_account_instead", "Need an account? Create one") }
        static var registerSubtitle: String { text("auth.register.subtitle", "Create an account with the essentials. You can complete your profile later.") }
        static var continueAsGuest: String { text("auth.continue_as_guest", "Continue as Guest") }
        static var consentTitle: String { text("auth.consent.title", "Terms & Privacy") }
        static var consentSubtitle: String { text("auth.consent.subtitle", "To create an account, please confirm that you accept the Terms of Use and the Privacy Policy.") }
        static var acceptTerms: String { text("auth.consent.accept_terms", "I accept the Terms of Use") }
        static var acceptPrivacy: String { text("auth.consent.accept_privacy", "I accept the Privacy Policy") }
        static var reviewTerms: String { text("auth.consent.review_terms", "Read Terms of Use") }
        static var reviewPrivacy: String { text("auth.consent.review_privacy", "Read Privacy Policy") }
        static var currentTermsVersion: String { text("auth.consent.current_terms_version", "Terms version %@") }
        static var currentPrivacyVersion: String { text("auth.consent.current_privacy_version", "Privacy version %@") }
        static var requiredTitle: String { text("auth.required.title", "Sign in required") }
        static var placeholderTitle: String { text("auth.placeholder.title", "Authentication is coming in the next phase") }
        static var placeholderMessage: String { text("auth.placeholder.message", "Full sign-in and account creation will be added in the next phase. You can keep browsing public content as a guest for now.") }
        static var signInFailed: String { text("auth.sign_in_failed", "We couldn’t sign you in right now.") }
        static var registrationFailed: String { text("auth.registration_failed", "We couldn’t create your account right now.") }
        static var registrationInvalidEmail: String { text("auth.registration.invalid_email", "Please enter a valid email address.") }
        static var registrationEmailAlreadyInUse: String { text("auth.registration.email_in_use", "This email address is already in use.") }
        static var registrationWeakPassword: String { text("auth.registration.weak_password", "Choose a stronger password with at least 8 characters.") }
        static var registrationNetworkError: String { text("auth.registration.network_error", "We couldn’t reach the server. Check your connection and try again.") }
        static var registrationOperationNotAllowed: String { text("auth.registration.operation_not_allowed", "Email registration is not enabled right now.") }
        static var registrationUnknownError: String { text("auth.registration.unknown_error", "We couldn’t finish registration right now. Please try again.") }
        static var registrationProfilePermissionError: String { text("auth.registration.profile_permission", "Your account was created, but the profile setup was blocked by backend rules. Please contact support or deploy the latest Firebase rules.") }
        static var registrationProfileNetworkError: String { text("auth.registration.profile_network", "Your account was created, but the profile setup could not finish because of a network problem. Please try again.") }
        static var registrationProfileUnknownError: String { text("auth.registration.profile_unknown", "Your account was created, but the profile setup could not be completed. Please try again later.") }
        static var resetPasswordFailed: String { text("auth.reset_password.failed", "We couldn’t send a reset link right now.") }
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

    static func commentLine(author: String, body: String) -> String {
        LocalizationStore.localizedFormat("common.comment_line", defaultValue: "%1$@: %2$@", arguments: [author, body])
    }

    static func contactLine(method: String, value: String) -> String {
        LocalizationStore.localizedFormat("common.contact_line", defaultValue: "%1$@: %2$@", arguments: [method, value])
    }

    static func authRequiredMessage(for capability: String) -> String {
        LocalizationStore.localizedFormat(
            "auth.required.message",
            defaultValue: "%1$@ requires an account. You can keep browsing as a guest for now.",
            arguments: [capability]
        )
    }

    static func profileRegistrationsCount(_ count: Int) -> String {
        LocalizationStore.localizedFormat(
            "profile.registrations.count",
            defaultValue: "%lld registered events",
            arguments: [count]
        )
    }

    static func legalVersionLabel(_ version: String) -> String {
        LocalizationStore.localizedFormat("legal.version_label", defaultValue: "Version %@", arguments: [version])
    }

    static func legalLastUpdatedLabel(_ date: String) -> String {
        LocalizationStore.localizedFormat("legal.last_updated_label", defaultValue: "Last updated %@", arguments: [date])
    }

    static func authCurrentTermsVersion(_ version: String) -> String {
        LocalizationStore.localizedFormat("auth.consent.current_terms_version", defaultValue: "Terms version %@", arguments: [version])
    }

    static func authCurrentPrivacyVersion(_ version: String) -> String {
        LocalizationStore.localizedFormat("auth.consent.current_privacy_version", defaultValue: "Privacy version %@", arguments: [version])
    }

    private static func text(_ key: String, _ defaultValue: String) -> String {
        LocalizationStore.localizedString(key, defaultValue: defaultValue)
    }
}
