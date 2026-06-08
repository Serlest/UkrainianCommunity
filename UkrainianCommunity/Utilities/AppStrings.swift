import Foundation

enum AppStrings {
    enum Tabs {
        static var home: String { text("tab.home", "Home") }
        static var events: String { text("tab.events", "Events") }
        static var organizations: String { text("tab.organizations", "Organizations") }
        static var info: String { text("tab.info", "Guide") }
        static var profile: String { text("tab.profile", "Profile") }
    }

    enum LocalNotifications {
        static var eventReminderFallbackBody: String {
            String(localized: "notifications.local.event_reminder.fallback_body", defaultValue: "Подія скоро почнеться", bundle: .main, locale: LocalizationStore.locale)
        }
        static var testTitle: String {
            String(localized: "notifications.local.test.title", defaultValue: "Тестове сповіщення", bundle: .main, locale: LocalizationStore.locale)
        }
        static var testBody: String {
            String(localized: "notifications.local.test.body", defaultValue: "Локальні сповіщення працюють.", bundle: .main, locale: LocalizationStore.locale)
        }
    }

    enum NotificationInbox {
        static var title: String { text("notifications.inbox.title", "Notifications") }
        static var subtitle: String { text("notifications.inbox.subtitle", "Updates about your requests and support messages.") }
        static var emptyTitle: String { text("notifications.inbox.empty.title", "No notifications yet") }
        static var emptyMessage: String { text("notifications.inbox.empty.message", "New replies and request updates will appear here.") }
        static var unreadEmptyTitle: String { text("notifications.inbox.unread.empty.title", "No unread notifications") }
        static var unreadEmptyMessage: String { text("notifications.inbox.unread.empty.message", "Unread updates will appear here.") }
        static var filterAll: String { text("notifications.inbox.filter.all", "All") }
        static var filterUnread: String { text("notifications.inbox.filter.unread", "Unread") }
        static var markAllRead: String { text("notifications.inbox.mark_all_read", "Mark all as read") }
        static var markRead: String { text("notifications.inbox.mark_read", "Mark read") }
        static var markUnread: String { text("notifications.inbox.mark_unread", "Mark unread") }
        static var archive: String { text("notifications.inbox.archive", "Archive") }
        static var delete: String { text("notifications.inbox.delete", "Delete") }
        static var destinationUnavailableTitle: String { text("notifications.inbox.destination_unavailable.title", "No longer available") }
        static var destinationUnavailableMessage: String { text("notifications.inbox.destination_unavailable.message", "This notification can no longer be opened.") }
        static var feedbackSubmittedTitle: String { text("notifications.inbox.feedback_submitted.title", "New user request") }
        static var feedbackSubmittedBody: String { text("notifications.inbox.feedback_submitted.body", "A user submitted a new request.") }
        static var feedbackReplyTitle: String { text("notifications.inbox.feedback_reply.title", "Support replied") }
        static var feedbackReplyBody: String { text("notifications.inbox.feedback_reply.body", "You have a new reply to your message.") }
        static var organizationApprovedTitle: String { text("notifications.inbox.organization_approved.title", "Organization approved") }
        static var organizationNeedsRevisionTitle: String { text("notifications.inbox.organization_needs_revision.title", "Organization needs revision") }
        static var organizationRejectedTitle: String { text("notifications.inbox.organization_rejected.title", "Organization rejected") }
        static var accountStatusChangedTitle: String { text("notifications.inbox.account_status_changed.title", "Account status updated") }
        static var legalDocumentsUpdatedTitle: String { text("notifications.inbox.legal_documents_updated.title", "Legal documents updated") }
        static var roleChangedTitle: String { text("notifications.inbox.role_changed.title", "Role updated") }
        static var organizationRoleAssignedTitle: String { text("notifications.inbox.organization_role_assigned.title", "Organization role assigned") }
        static var organizationRoleRemovedTitle: String { text("notifications.inbox.organization_role_removed.title", "Organization role removed") }
        static var reportReviewedTitle: String { text("notifications.inbox.report_reviewed.title", "Report reviewed") }
        static var eventUpdatedTitle: String { text("notifications.inbox.event_updated.title", "Event updated") }
        static var eventCancelledTitle: String { text("notifications.inbox.event_cancelled.title", "Event cancelled") }
        static var guideMaterialUpdatedTitle: String { text("notifications.inbox.guide_material_updated.title", "Guide material updated") }
        static var systemAnnouncementTitle: String { text("notifications.inbox.system_announcement.title", "System announcement") }
        static var genericBody: String { text("notifications.inbox.generic.body", "Open this notification for details.") }
        static var severityInfo: String { text("notifications.inbox.severity.info", "Info") }
        static var severitySuccess: String { text("notifications.inbox.severity.success", "Success") }
        static var severityWarning: String { text("notifications.inbox.severity.warning", "Warning") }
        static var severityCritical: String { text("notifications.inbox.severity.critical", "Critical") }

        static func organizationApprovedBody(_ organizationName: String) -> String {
            LocalizationStore.localizedFormat(
                "notifications.inbox.organization_approved.body",
                defaultValue: "%@ was approved.",
                arguments: [organizationName]
            )
        }

        static func organizationNeedsRevisionBody(_ organizationName: String) -> String {
            LocalizationStore.localizedFormat(
                "notifications.inbox.organization_needs_revision.body",
                defaultValue: "%@ needs changes before approval.",
                arguments: [organizationName]
            )
        }

        static func organizationRejectedBody(_ organizationName: String) -> String {
            LocalizationStore.localizedFormat(
                "notifications.inbox.organization_rejected.body",
                defaultValue: "%@ was rejected.",
                arguments: [organizationName]
            )
        }

        static func unreadCount(_ count: Int) -> String {
            LocalizationStore.localizedFormat(
                "notifications.inbox.unread_count",
                defaultValue: "%lld unread",
                arguments: [count]
            )
        }
    }

    enum NotificationPopup {
        static var actionButton: String { text("notifications.popup.action", "Open") }
        static var updateFailed: String { text("notifications.popup.error.update_failed", "Unable to update this notification right now.") }
    }

    enum Featured {
        static func bannerPageIndicator(current: Int, total: Int) -> String {
            LocalizationStore.localizedFormat(
                "featured.banner.page_indicator",
                defaultValue: "Featured banner %lld of %lld",
                arguments: [current, total]
            )
        }
    }

    enum AccountStatusAlert {
        static var warnedTitle: String { text("account_status_alert.warned.title", "Попередження для акаунта") }
        static var suspendedTitle: String { text("account_status_alert.suspended.title", "Акаунт тимчасово заблоковано") }
        static var bannedTitle: String { text("account_status_alert.banned.title", "Акаунт заблоковано") }
        static var deactivatedTitle: String { text("account_status_alert.deactivated.title", "Акаунт деактивовано") }
        static var restoredTitle: String { text("account_status_alert.restored.title", "Доступ до акаунта відновлено") }
        static var warnedMessage: String { text("account_status_alert.warned.message", "Ви можете й надалі користуватися застосунком, але повторні порушення можуть обмежити доступ до захищених дій.") }
        static var suspendedMessage: String { text("account_status_alert.suspended.message", "Захищені дії та розширені можливості обмежені до завершення тимчасового блокування.") }
        static var bannedMessage: String { text("account_status_alert.banned.message", "Захищені дії та можливості акаунта заблоковані. Публічний контент може залишатися доступним, якщо це дозволено правилами застосунку.") }
        static var deactivatedMessage: String { text("account_status_alert.deactivated.message", "Акаунт деактивовано. Захищені дії та персональні можливості недоступні.") }
        static var restoredMessage: String { text("account_status_alert.restored.message", "Ваш доступ відновлено. Ви знову можете користуватися можливостями акаунта відповідно до ваших ролей.") }
        static var reasonTitle: String { text("account_status_alert.reason", "Причина") }
        static var suspensionUntilTitle: String { text("account_status_alert.suspension_until", "Блокування діє до") }
        static var acknowledgementButton: String { text("account_status_alert.acknowledgement_button", "Зрозуміло") }
        static var acknowledgementLoading: String { text("account_status_alert.acknowledgement_loading", "Зберігаємо…") }
        static var acknowledgementFailed: String { text("account_status_alert.acknowledgement_failed", "Не вдалося підтвердити повідомлення. Перевірте з’єднання та спробуйте ще раз.") }
    }

    enum Search {
        static var open: String { text("search.open", "Search") }
        static var close: String { text("search.close", "Close search") }
        static var clear: String { text("search.clear", "Clear search") }
        static var noResultsTitle: String { text("search.no_results.title", "Nothing found") }
        static var noResultsMessage: String { text("search.no_results.message", "Try a different search term or adjust the current filters.") }
        static var homePlaceholder: String { text("search.placeholder.home", "Search updates, events, and organizations") }
        static var eventsPlaceholder: String { text("search.placeholder.events", "Search events") }
        static var organizationsPlaceholder: String { text("search.placeholder.organizations", "Search organizations") }
        static var guidePlaceholder: String { text("search.placeholder.guide", "Search guide") }
    }

    enum Images {
        enum Crop {
            static var title: String { text("image.crop.title", "Crop image") }
            static var hint: String { text("image.crop.hint", "Drag to reposition. Pinch to zoom.") }
            static var reset: String { text("image.crop.reset", "Reset") }
            static var cancel: String { text("image.crop.cancel", "Cancel") }
            static var apply: String { text("image.crop.apply", "Apply") }
        }

        enum Validation {
            static var squareAspectRatio: String { text("image.validation.aspect_ratio.square", "Image must be square. Crop it to fit the frame before uploading.") }
        }
    }

    enum FeaturedManagement {
        static var title: String { text("featured.management.title", "Featured Content") }
        static var profileEntryTitle: String { text("featured.management.profile_entry.title", "Featured Content") }
        static var profileEntrySubtitle: String { text("featured.management.profile_entry.subtitle", "Manage highlights shown across Home, Events, Organizations, and Guide.") }
        static var subtitle: String { text("featured.management.subtitle", "Review active and scheduled highlights. Full create and edit tools will be added in the next pass.") }
        static var emptyTitle: String { text("featured.management.empty.title", "No featured banners yet") }
        static var emptyMessage: String { text("featured.management.empty.message", "Create/edit controls will be added in the next pass.") }
        static var inactive: String { text("featured.management.inactive", "Inactive") }
        static var activeToggle: String { text("featured.management.active_toggle", "Active") }
        static var updating: String { text("featured.management.updating", "Updating") }
        static var deleteBanner: String { text("featured.management.delete", "Delete banner") }
        static var deleteConfirmationTitle: String { text("featured.management.delete.confirm.title", "Delete featured banner?") }
        static func deleteConfirmationMessage(_ title: String) -> String {
            LocalizationStore.localizedFormat(
                "featured.management.delete.confirm.message",
                defaultValue: "This will permanently delete “%@” from featured content.",
                arguments: [title]
            )
        }
        static var sectionsLabel: String { text("featured.management.sections", "Sections") }
        static var regionLabel: String { text("featured.management.region", "Region") }
        static var actionLabel: String { text("featured.management.action", "Action") }
        static var priorityLabel: String { text("featured.management.priority", "Priority") }
        static var missingRegion: String { text("featured.management.missing_region", "Missing region") }
        static var actionNone: String { text("featured.management.action.none", "No tap action") }
        static var actionExternalURL: String { text("featured.management.action.external_url", "External URL") }
        static var networkError: String { text("featured.management.error.network", "Unable to load featured content. Check your connection and try again.") }
        static var permissionError: String { text("featured.management.error.permission", "You do not have permission to manage featured content.") }
        static var validationError: String { text("featured.management.error.validation", "Featured content data is incomplete or invalid.") }
        static var notFoundError: String { text("featured.management.error.not_found", "Featured content was not found.") }
        static var unknownError: String { text("featured.management.error.unknown", "Unable to update featured content right now.") }

        static func fallbackBannerName(_ id: String, date: Date) -> String {
            LocalizationStore.localizedFormat(
                "featured.management.fallback_name",
                defaultValue: "Banner %@ · %@",
                arguments: [id, date.formatted(date: .abbreviated, time: .omitted)]
            )
        }
    }

    enum FeaturedEditor {
        static var createTitle: String { text("featured.editor.create.title", "Create Featured Banner") }
        static var editTitle: String { text("featured.editor.edit.title", "Edit Featured Banner") }
        static var subtitle: String { text("featured.editor.subtitle", "Configure the highlight shown in public banner carousels.") }
        static var createBanner: String { text("featured.editor.create_banner", "Create banner") }
        static var editBanner: String { text("featured.editor.edit_banner", "Edit banner") }
        static var createEntrySubtitle: String { text("featured.editor.create_entry.subtitle", "Add a new highlight for one or more sections.") }
        static var saveChanges: String { text("featured.editor.save_changes", "Save changes") }
        static var saving: String { text("featured.editor.saving", "Saving") }
        static var saveSuccess: String { text("featured.editor.save_success", "Featured banner saved.") }
        static var basicsSection: String { text("featured.editor.section.basics", "Basics") }
        static var imageSection: String { text("featured.editor.section.image", "Image") }
        static var targetingSection: String { text("featured.editor.section.targeting", "Targeting") }
        static var actionSection: String { text("featured.editor.section.action", "Action") }
        static var schedulingSection: String { text("featured.editor.section.scheduling", "Scheduling") }
        static var internalNameField: String { text("featured.editor.field.internal_name", "Internal Name") }
        static var titleField: String { text("featured.editor.field.title", "Headline") }
        static var subtitleField: String { text("featured.editor.field.subtitle", "Subtitle") }
        static var imageHelper: String { text("featured.editor.image.helper", "Use a wide 16:9 image. The public carousel crops safely inside the card bounds.") }
        static var replaceImage: String { text("featured.editor.image.replace", "Replace image") }
        static var uploadImage: String { text("featured.editor.image.upload", "Upload banner image") }
        static var uploadImageHelper: String { text("featured.editor.image.upload_helper", "A banner image is required before saving.") }
        static var imageLoadFailed: String { text("featured.editor.image.load_failed", "Unable to load the selected image.") }
        static var validationImageAspectRatio: String { text("featured.editor.validation.image_aspect_ratio", "Image must be 16:9. Choose a horizontal photo or crop it before uploading.") }
        static var cropTitle: String { text("featured.editor.crop.title", "Crop banner image") }
        static var cropInstructions: String { text("featured.editor.crop.instructions", "Move and scale the image inside the 16:9 frame.") }
        static var cropGestureHint: String { text("featured.editor.crop.gesture_hint", "Drag to reposition. Pinch to zoom.") }
        static var cropReset: String { text("featured.editor.crop.reset", "Reset") }
        static var cropApply: String { text("featured.editor.crop.apply", "Apply") }
        static var regionScopeField: String { text("featured.editor.field.region_scope", "Region scope") }
        static var regionScopeFederalState: String { text("featured.editor.region_scope.federal_state", "Federal state") }
        static var federalStateField: String { text("featured.editor.field.federal_state", "Federal state") }
        static var selectFederalState: String { text("featured.editor.select_federal_state", "Select federal state") }
        static var visibleSectionsField: String { text("featured.editor.field.visible_sections", "Visible sections") }
        static var actionTypeField: String { text("featured.editor.field.action_type", "Action type") }
        static var actionHelperNoTap: String { text("featured.editor.action.helper.no_tap", "This banner will display only. Tapping it will not open anything.") }
        static var actionHelperTarget: String { text("featured.editor.action.helper.target", "Tapping this banner opens the selected app content.") }
        static var actionHelperExternalURL: String { text("featured.editor.action.helper.external_url", "Tapping this banner opens the external URL.") }
        static var actionTargetField: String { text("featured.editor.field.action_target", "Target ID") }
        static var manualTargetHelper: String { text("featured.editor.action.manual_target_helper", "Enter the existing content ID manually for action types without picker support.") }
        static var selectTarget: String { text("featured.editor.action.select_target", "Select target") }
        static var clearTarget: String { text("featured.editor.action.clear_target", "Clear selected target") }
        static var targetPickerSearch: String { text("featured.editor.action.search_target", "Search by title, summary, source, location, type, or ID") }
        static var loadingTargets: String { text("featured.editor.action.loading_targets", "Loading targets") }
        static var noTargetsFound: String { text("featured.editor.action.no_targets.title", "No matching targets") }
        static var noTargetsFoundMessage: String { text("featured.editor.action.no_targets.message", "Try a different search or refresh the list.") }
        static var targetPickerLoadFailed: String { text("featured.editor.action.load_failed", "Unable to load selectable targets right now.") }
        static var externalURLField: String { text("featured.editor.field.external_url", "External URL") }
        static var durationField: String { text("featured.editor.field.duration", "Display duration") }
        static var priorityField: String { text("featured.editor.field.priority", "Priority") }
        static var startsAtEnabled: String { text("featured.editor.starts_at.enabled", "Use start date") }
        static var startsAtField: String { text("featured.editor.field.starts_at", "Starts at") }
        static var endsAtEnabled: String { text("featured.editor.ends_at.enabled", "Use end date") }
        static var endsAtField: String { text("featured.editor.field.ends_at", "Ends at") }
        static var validationTitleRequired: String { text("featured.editor.validation.title_required", "Title is required.") }
        static var validationImageRequired: String { text("featured.editor.validation.image_required", "Select or keep a banner image before saving.") }
        static var validationDuration: String { text("featured.editor.validation.duration", "Display duration must be between 3 and 12 seconds.") }
        static var validationPriority: String { text("featured.editor.validation.priority", "Priority must be between 0 and 1000.") }
        static var validationSections: String { text("featured.editor.validation.sections", "Select at least one visible section.") }
        static var validationFederalState: String { text("featured.editor.validation.federal_state", "Federal state is required for federal-state banners.") }
        static var validationExternalURL: String { text("featured.editor.validation.external_url", "Enter a valid external URL.") }
        static var validationTargetID: String { text("featured.editor.validation.target_id", "Target ID is required for this action type.") }
        static var validationDateWindow: String { text("featured.editor.validation.date_window", "Start date must be before end date.") }
        static var validationOwnerRequired: String { text("featured.editor.validation.owner_required", "Owner account is required to save featured content.") }
        static var saveNetworkError: String { text("featured.editor.error.network", "Unable to save featured content. Check your connection and try again.") }
        static var savePermissionError: String { text("featured.editor.error.permission", "You do not have permission to save featured content.") }
        static var saveValidationError: String { text("featured.editor.error.validation", "Featured banner data is incomplete or invalid.") }
        static var saveNotFoundError: String { text("featured.editor.error.not_found", "Featured banner was not found.") }
        static var saveUnknownError: String { text("featured.editor.error.unknown", "Unable to save featured content right now.") }

        static func durationValue(_ seconds: Int) -> String {
            LocalizationStore.localizedFormat(
                "featured.editor.duration.value",
                defaultValue: "%lld sec",
                arguments: [seconds]
            )
        }

        static func targetPickerTitle(_ contentType: String) -> String {
            LocalizationStore.localizedFormat(
                "featured.editor.action.picker_title",
                defaultValue: "Select %@",
                arguments: [contentType]
            )
        }

        static func selectedTargetID(_ id: String) -> String {
            LocalizationStore.localizedFormat(
                "featured.editor.action.selected_id",
                defaultValue: "ID: %@",
                arguments: [id]
            )
        }
    }

    enum Home {
        static var brandTitle: String { text("home.brand_title", "Ukrainian Community") }
        static var brandSubtitle: String { text("home.brand_subtitle", "Austria") }
        static var title: String { text("home.title", "Ukrainian Community Tirol") }
        static var subtitle: String { text("home.subtitle", "A calm, trusted place for updates, events, organizations, and neighbor-to-neighbor support.") }
        static var bannerTitle: String { text("home.banner.title", "Together, stronger") }
        static var bannerSubtitle: String { text("home.banner.subtitle", "Support, information, and opportunities for Ukrainians in Austria.") }
        static var regionAllAustria: String { text("home.region.all_austria", "Вся Австрія") }
        static var highlights: String { text("home.highlights", "Community Highlights") }
        static var latestNews: String { text("home.latest_news", "Latest updates") }
        static var filterAll: String { text("home.filter.all", "Усе") }
        static var filterNews: String { text("home.filter.news", "Новини") }
        static var filterEvents: String { text("home.filter.events", "Події") }
        static var filterOrganizations: String { text("home.filter.organizations", "Організації") }
        static var filterSubscriptions: String { text("home.filter.subscriptions", "Subscriptions") }
        static var filterFavorites: String { text("home.filter.favorites", "Favorites") }
        static var filterSaved: String { text("home.filter.saved", "Збережені") }
        static var filterSubscribed: String { text("home.filter.subscribed", "Підписані") }
        static var emptySaved: String { text("home.empty.saved", "У вас ще немає збережених матеріалів.") }
        static var emptySubscribed: String { text("home.empty.subscribed", "У вас ще немає підписок") }
        static var emptyRegion: String { text("home.empty.region", "Немає контенту в обраному регіоні.") }
        static var subscriberSuffixOne: String { text("home.subscribers.suffix.one", "підписник") }
        static var subscriberSuffixFew: String { text("home.subscribers.suffix.few", "підписники") }
        static var subscriberSuffixMany: String { text("home.subscribers.suffix.many", "підписників") }
        static var notifications: String { text("home.notifications", "Notifications") }
    }

    enum News {
        static var title: String { text("news.title", "News") }
        static var heroTitle: String { text("news.hero.title", "Новини громади") }
        static var heroSubtitle: String { text("news.hero.subtitle", "Важливі оновлення, оголошення та історії українців в Австрії.") }
        static var detailTitle: String { text("news.detail.title", "Деталі новини") }
        static var detailBadge: String { text("news.detail.badge", "Новина") }
        static var summarySectionTitle: String { text("news.detail.summary_section", "Коротко") }
        static var bodySectionTitle: String { text("news.detail.body_section", "Про що йдеться") }
        static var sourceSectionTitle: String { text("news.detail.source", "Source") }
        static var tagsSectionTitle: String { text("news.detail.tags_section", "Теги") }
        static var relatedSectionTitle: String { text("news.detail.related_section", "Вам також може бути цікаво") }
        static var relatedSectionAction: String { text("news.detail.related_action", "Дивитися всі") }
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
        static var missingOrganization: String { text("news.source.missing_organization", "Організація не вказана") }
        static func viewCount(_ count: Int) -> String {
            LocalizationStore.localizedFormat("news.view_count", defaultValue: "%lld переглядів", arguments: [count])
        }
    }

    enum NewsEditor {
        static var title: String { text("news.editor.title", "Додати новину") }
        static var addTitle: String { text("news.editor.add_title", "Додати новину") }
        static var editTitle: String { text("news.editor.edit_title", "Редагувати новину") }
        static var editorSubtitle: String { text("news.editor.subtitle", "Поділіться важливою інформацією з громадою.") }
        static var titleFieldRequired: String { text("news.editor.field.title_required", "Заголовок новини *") }
        static var titlePlaceholder: String { text("news.editor.placeholder.title", "Введіть заголовок") }
        static var summaryFieldRequired: String { text("news.editor.field.summary_required", "Короткий опис *") }
        static var summaryPlaceholder: String { text("news.editor.placeholder.summary", "Коротко опишіть новину. Цей текст буде відображатися в списку новин.") }
        static var coverSectionTitle: String { text("news.editor.cover.title", "Обкладинка новини") }
        static var coverUploadTitle: String { text("news.editor.cover.upload_title", "Додайте фото обкладинки") }
        static var coverUploadHelper: String { text("news.editor.cover.upload_helper", "JPG, PNG до 10 MB. Рекомендовано 16:9") }
        static var replacePhoto: String { text("news.editor.cover.replace", "Замінити фото") }
        static var organizerSectionTitle: String { text("news.editor.organizer.title", "Організація *") }
        static var selectOrganizer: String { text("news.editor.organizer.select", "Оберіть організацію") }
        static var noOrganizerAccess: String { text("news.editor.organizer.no_access", "У вас немає організацій для публікації новин.") }
        static var categoryNews: String { text("news.editor.category.news", "Новина") }
        static var categoryEvent: String { text("news.editor.category.event", "Подія") }
        static var categoryEducation: String { text("news.editor.category.education", "Освіта") }
        static var categoryCulture: String { text("news.editor.category.culture", "Культура") }
        static var categoryOther: String { text("news.editor.category.other", "Інше") }
        static var bodySectionTitle: String { text("news.editor.body.title", "Зміст новини *") }
        static var bodyPlaceholder: String { text("news.editor.body.placeholder", "Напишіть основний текст новини...") }
        static var sourceSectionTitle: String { text("news.editor.source.title", "Source") }
        static var sourcePlaceholder: String { text("news.editor.source.placeholder", "Website or source name") }
        static var sourceHelper: String { text("news.editor.source.helper", "Optional. Add a publication name or a link.") }
        static var tagsSectionTitle: String { text("news.editor.tags.title", "Теги (необов’язково)") }
        static var tagsPlaceholder: String { text("news.editor.tags.placeholder", "Додайте теги через кому") }
        static var tagsHelper: String { text("news.editor.tags.helper", "Наприклад: підтримка, освіта, інтеграція") }
        static var additionalSettingsTitle: String { text("news.editor.settings.title", "Додаткові налаштування") }
        static var regionSectionTitle: String { text("news.editor.region.title", "Регіон") }
        static var regionTitle: String { text("news.editor.region.field", "Федеральна земля") }
        static var publish: String { text("news.editor.publish", "Опублікувати") }
        static var saveChanges: String { text("news.editor.save_changes", "Зберегти") }
        static var primaryPublish: String { text("news.editor.primary_publish", "Опублікувати новину") }
        static var primarySaveChanges: String { text("news.editor.primary_save_changes", "Зберегти зміни") }
        static var publishing: String { text("news.editor.publishing", "Публікуємо...") }
        static var uploadingImage: String { text("news.editor.uploading_image", "Завантажуємо фото...") }
        static var processingImage: String { text("news.editor.processing_image", "Готуємо фото...") }
        static var publishedSuccessfully: String { text("news.editor.success", "News published successfully.") }
        static var updatedSuccessfully: String { text("news.editor.updated_success", "News updated successfully.") }
        static var titleRequired: String { text("news.editor.validation.title_required", "Title is required.") }
        static var summaryRequired: String { text("news.editor.validation.summary_required", "Short description is required.") }
        static var bodyRequired: String { text("news.editor.validation.body_required", "Body is required.") }
        static var organizationRequired: String { text("news.editor.validation.organization_required", "Оберіть організацію для новини.") }
        static var organizationRegionRequired: String { text("news.editor.validation.organization_region_required", "Перед публікацією заповніть регіон організації.") }
        static var imageLoadFailed: String { text("news.editor.image_load_failed", "Failed to load the selected image.") }
        static var imageProcessingFailed: String { text("news.editor.image_processing_failed", "Failed to process the selected image.") }
        static var imageTooLarge: String { text("news.editor.image_too_large", "Image is too large. Please choose a smaller photo.") }
        static var authorFallback: String { text("news.editor.author_fallback", "Anonymous") }
    }

    enum DraftRecovery {
        static var recoveryTitle: String { text("draft_recovery.recovery.title", "Continue saved draft?") }
        static var recoveryMessage: String { text("draft_recovery.recovery.message", "A local draft from your previous News create session is available.") }
        static var eventRecoveryMessage: String { text("draft_recovery.recovery.event_message", "A local draft from your previous Event create session is available.") }
        static var organizationRecoveryMessage: String { text("draft_recovery.recovery.organization_message", "A local draft from your previous Organization create session is available.") }
        static var continueDraft: String { text("draft_recovery.recovery.continue", "Continue draft") }
        static var createNew: String { text("draft_recovery.recovery.create_new", "Create new") }
        static var deleteDraft: String { text("draft_recovery.recovery.delete", "Delete draft") }
        static var closeTitle: String { text("draft_recovery.close.title", "Save this draft?") }
        static var closeMessage: String { text("draft_recovery.close.message", "You have unsaved News content. Save it locally before closing or discard it.") }
        static var eventCloseMessage: String { text("draft_recovery.close.event_message", "You have unsaved Event content. Save it locally before closing or discard it.") }
        static var organizationCloseMessage: String { text("draft_recovery.close.organization_message", "You have unsaved Organization content. Save it locally before closing or discard it.") }
        static var saveDraftAndClose: String { text("draft_recovery.close.save", "Save draft and close") }
        static var discardDraft: String { text("draft_recovery.close.discard", "Discard") }
        static var continueEditing: String { text("draft_recovery.close.continue_editing", "Continue editing") }
    }

    enum Events {
        static var title: String { text("events.title", "Events") }
        static var heroTitle: String { text("events.hero.title", "Події громади") }
        static var heroSubtitle: String { text("events.hero.subtitle", "Зустрічі, навчання та підтримка поруч із вами.") }
        static var upcomingTitle: String { text("events.section.upcoming", "Upcoming") }
        static var pastTitle: String { text("events.section.past", "Past") }
        static var filterAll: String { text("events.filter.all", "Усі") }
        static var filterToday: String { text("events.filter.today", "Today") }
        static var filterThisWeek: String { text("events.filter.this_week", "This week") }
        static var filterRegistered: String { text("events.filter.registered", "Зареєстровані") }
        static var allCategories: String { text("events.filter.all_categories", "Усі категорії") }
        static var categoryEducation: String { text("events.category.education", "Освіта") }
        static var categoryCulture: String { text("events.category.culture", "Культура") }
        static var categoryMeetups: String { text("events.category.meetups", "Зустрічі") }
        static var categoryMeetupSingular: String { text("events.category.meetup_singular", "Зустріч") }
        static var categoryChildren: String { text("events.category.children", "Для дітей") }
        static var categoryOther: String { text("events.category.other", "Інше") }
        static var emptySaved: String { text("events.empty.saved", "У вас ще немає збережених подій") }
        static var emptyRegistered: String { text("events.empty.registered", "У вас ще немає зареєстрованих подій.\nЗареєструйтесь на події, щоб бачити їх тут.") }
        static var filteredUpcomingEmpty: String { text("events.empty.filtered_upcoming", "No upcoming events match this time range right now.") }
        static var register: String { text("events.register", "Я піду") }
        static var registered: String { text("events.registered", "Я йду") }
        static var confirmRegisterTitle: String { text("events.registration.confirm_register.title", "Register for this event?") }
        static var confirmRegisterButton: String { text("events.registration.confirm_register.button", "Register") }
        static var confirmCancelRegistrationTitle: String { text("events.registration.confirm_cancel.title", "Cancel your registration?") }
        static var confirmCancelRegistrationButton: String { text("events.registration.confirm_cancel.button", "Cancel registration") }
        static func confirmRegisterMessage(_ eventTitle: String) -> String {
            LocalizationStore.localizedFormat(
                "events.registration.confirm_register.message",
                defaultValue: "You will be registered for “%@”.",
                arguments: [eventTitle]
            )
        }
        static func confirmCancelRegistrationMessage(_ eventTitle: String) -> String {
            LocalizationStore.localizedFormat(
                "events.registration.confirm_cancel.message",
                defaultValue: "You will no longer be registered for “%@”.",
                arguments: [eventTitle]
            )
        }
        static var waitlisted: String { text("events.waitlisted", "У списку очікування") }
        static var allDay: String { text("events.all_day", "Подія на весь день") }
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
        static var detailBadge: String { text("events.detail.badge", "Зустріч") }
        static var aboutSectionTitle: String { text("events.detail.about", "Про подію") }
        static var detailOrganizerSectionTitle: String { text("events.detail.organizer", "Organizer") }
        static var publishedBySectionTitle: String { text("events.detail.published_by", "Published by") }
        static var organizerContactSectionTitle: String { text("events.detail.organizer_contact", "Organizer and contact") }
        static var detailsSectionTitle: String { text("events.detail.details", "Деталі") }
        static var locationSectionTitle: String { text("events.detail.location", "Місце проведення") }
        static var similarEvents: String { text("events.detail.similar_events", "Схожі події") }
        static var addToCalendar: String { text("events.detail.add_to_calendar", "Додати в календар") }
        static var calendarAddedTitle: String { text("events.detail.calendar_added.title", "Додано в календар") }
        static var calendarAddedMessage: String { text("events.detail.calendar_added.message", "Подію збережено у вашому календарі.") }
        static var calendarAlreadyAddedTitle: String { text("events.detail.calendar_already_added.title", "Вже додано") }
        static var calendarAlreadyAddedMessage: String { text("events.detail.calendar_already_added.message", "Цю подію вже додано в календар у цій сесії.") }
        static var calendarPermissionTitle: String { text("events.detail.calendar_permission.title", "Немає доступу до календаря") }
        static var calendarPermissionMessage: String { text("events.detail.calendar_permission.message", "Дозвольте доступ до календаря в налаштуваннях iOS, щоб додавати події.") }
        static var calendarErrorTitle: String { text("events.detail.calendar_error.title", "Не вдалося додати подію") }
        static var calendarErrorMessage: String { text("events.detail.calendar_error.message", "Спробуйте ще раз пізніше.") }
        static var share: String { text("events.detail.share", "Поділитися") }
        static var viewOrganization: String { text("events.detail.view_organization", "Переглянути організацію") }
        static var genericEventBadge: String { text("events.detail.generic_badge", "Подія") }
        static var expectedParticipants: String { text("events.detail.expected_participants", "Очікувано учасників") }
        static var registrationNotRequired: String { text("events.detail.registration_not_required", "Registration is not required") }
        static var registrationManagementTitle: String { text("events.detail.registration_management.title", "Registered participants") }
        static var registrationManagementEmpty: String { text("events.detail.registration_management.empty", "Поки немає зареєстрованих учасників.") }
        static var registrationManagementLoading: String { text("events.detail.registration_management.loading", "Loading registered participants...") }
        static var registrationParticipantFallback: String { text("events.detail.registration_management.participant_fallback", "Registered user") }
        static var addedDate: String { text("events.detail.added_date", "Додано") }
        static var showOnMap: String { text("events.detail.show_on_map", "Показати на карті") }
        static var editorTitle: String { text("events.editor.title", "Створити подію") }
        static var editTitle: String { text("events.editor.edit_title", "Редагувати подію") }
        static var editorSubtitle: String { text("events.editor.subtitle", "Запросіть громаду на важливу подію.") }
        static var dateSectionTitle: String { text("events.editor.date_section", "Дата і час *") }
        static var imageSectionTitle: String { text("events.editor.image_section", "Обкладинка події") }
        static var coverUploadTitle: String { text("events.editor.cover_upload_title", "Додайте фото обкладинки") }
        static var coverUploadHelper: String { text("events.editor.cover_upload_helper", "JPG, PNG до 10 MB. Рекомендовано 16:9") }
        static var fieldTitle: String { text("events.editor.field.title", "Назва події *") }
        static var titlePlaceholder: String { text("events.editor.placeholder.title", "Введіть назву події") }
        static var fieldSummary: String { text("events.editor.field.summary", "Короткий опис *") }
        static var summaryPlaceholder: String { text("events.editor.placeholder.summary", "Коротко опишіть подію. Цей текст буде відображатися в списку подій.") }
        static var fieldDetails: String { text("events.editor.field.details", "Опис події *") }
        static var detailsPlaceholder: String { text("events.editor.placeholder.details", "Опишіть вашу подію. Що на учасників чекає?") }
        static var fieldLocation: String { text("events.editor.field.location", "Місце проведення *") }
        static var locationPlaceholder: String { text("events.editor.placeholder.location", "Введіть адресу або назву місця") }
        static var addressPlaceholder: String { text("events.editor.placeholder.address", "Адреса") }
        static var locationNoteTitle: String { text("events.editor.location_note.title", "Уточнення місця") }
        static var locationNotePlaceholder: String { text("events.editor.location_note.placeholder", "Наприклад: вхід з двору, 2 поверх, зал праворуч") }
        static var selectedLocation: String { text("events.editor.selected_location", "Обрана локація") }
        static var searchLocation: String { text("events.editor.search_location", "Пошук місця або адреси") }
        static var selectLocation: String { text("events.editor.select_location", "Вибрати") }
        static var noLocationResults: String { text("events.editor.no_location_results", "Нічого не знайдено") }
        static var chooseOnMap: String { text("events.editor.choose_on_map", "Вибрати на карті") }
        static var fieldStartDate: String { text("events.editor.field.start_date", "Дата") }
        static var startTime: String { text("events.editor.start_time", "Початок") }
        static var fieldEndDate: String { text("events.editor.field.end_date", "Закінчення") }
        static var endTime: String { text("events.editor.end_time", "Завершення") }
        static var editorPublisherSectionTitle: String { text("events.editor.publisher_section", "Publishing organization") }
        static var editorOrganizerSectionTitle: String { text("events.editor.organizer_section", "Organizer") }
        static var organizerNameField: String { text("events.editor.organizer_contact.name", "Organizer name") }
        static var organizerNamePlaceholder: String { text("events.editor.organizer_contact.name_placeholder", "External organizer, if different") }
        static var organizerURLField: String { text("events.editor.organizer_contact.url", "Organizer website") }
        static var organizerURLPlaceholder: String { text("events.editor.organizer_contact.url_placeholder", "https://example.org") }
        static var contactPhoneField: String { text("events.editor.organizer_contact.phone", "Contact phone") }
        static var contactPhonePlaceholder: String { text("events.editor.organizer_contact.phone_placeholder", "+43 ...") }
        static var contactEmailField: String { text("events.editor.organizer_contact.email", "Contact email") }
        static var contactEmailPlaceholder: String { text("events.editor.organizer_contact.email_placeholder", "name@example.org") }
        static var contactURLField: String { text("events.editor.organizer_contact.contact_url", "Contact link") }
        static var contactURLPlaceholder: String { text("events.editor.organizer_contact.contact_url_placeholder", "Registration or contact page") }
        static var organizerContactHelper: String { text("events.editor.organizer_contact.helper", "Optional. Add external organizer or contact details if different from the publishing organization.") }
        static var categorySectionTitle: String { text("events.editor.category_section", "Категорія *") }
        static var tagsSectionTitle: String { text("events.editor.tags_section", "Tags") }
        static var tagPlaceholder: String { text("events.editor.tag_placeholder", "Add a tag") }
        static var tagsHelper: String { text("events.editor.tags_helper", "Optional. Add short tags to help people understand the event topic.") }
        static var addTag: String { text("events.editor.add_tag", "Add tag") }
        static var removeTag: String { text("events.editor.remove_tag", "Remove tag") }
        static var categoryTraining: String { text("events.editor.category.training", "Навчання") }
        static var additionalSettingsTitle: String { text("events.editor.settings", "Додаткові налаштування") }
        static var requiresRegistrationToggle: String { text("events.editor.requires_registration", "Потрібна реєстрація") }
        static var requiresRegistrationHelper: String { text("events.editor.requires_registration_helper", "Turn on registration to manage price and participant capacity.") }
        static var priceTitle: String { text("events.editor.price", "Вартість") }
        static var pricePlaceholder: String { text("events.editor.price_placeholder", "0") }
        static var priceHelper: String { text("events.editor.price_helper", "0 = безкоштовно") }
        static var maxParticipantsTitle: String { text("events.editor.max_participants", "Максимальна кількість учасників") }
        static var unlimitedParticipants: String { text("events.editor.unlimited_participants", "Необмежена") }
        static var publishNotice: String { text("events.editor.publish_notice", "Після публікації подію буде видно у стрічці та в календарі подій.") }
        static var publish: String { text("events.editor.publish", "Створити подію") }
        static var saveChanges: String { text("events.editor.save_changes", "Зберегти") }
        static var primaryPublish: String { text("events.editor.primary_publish", "Опублікувати подію") }
        static var primarySaveChanges: String { text("events.editor.primary_save_changes", "Зберегти зміни") }
        static var publishing: String { text("events.editor.publishing", "Публікуємо...") }
        static var publishedSuccessfully: String { text("events.editor.success", "Event published successfully.") }
        static var updatedSuccessfully: String { text("events.editor.updated_success", "Event updated successfully.") }
        static var summaryRequired: String { text("events.editor.validation.summary_required", "Короткий опис обов'язковий.") }
        static var detailsRequired: String { text("events.editor.validation.details_required", "Details are required.") }
        static var descriptionRequired: String { text("events.editor.validation.description_required", "Description is required.") }
        static var invalidDateOrder: String { text("events.editor.validation.invalid_date_order", "End date must be after the start date.") }
        static var startDateInPast: String { text("events.editor.validation.start_date_in_past", "Дата початку не може бути в минулому.") }
        static var invalidCapacity: String { text("events.editor.validation.invalid_capacity", "Максимальна кількість учасників має бути більше 0.") }
        static var invalidPrice: String { text("events.editor.validation.invalid_price", "Вартість не може бути від’ємною.") }
        static var organizationRequired: String { text("events.editor.validation.organization_required", "Оберіть організацію для події.") }
        static var organizationRegionRequired: String { text("events.editor.validation.organization_region_required", "Перед публікацією заповніть регіон організації.") }
        static var deleteConfirmation: String { text("events.delete.confirmation", "Delete this event?") }
        static var delete: String { text("events.delete", "Delete") }
        static var cancel: String { text("events.cancel", "Cancel") }
        static var deleteFailed: String { text("events.delete_failed", "Delete Failed") }
        static var dismissError: String { text("events.dismiss_error", "OK") }
        static var freePrice: String { text("events.price.free", "Безкоштовно") }
        static var regionPlaceholder: String { text("events.editor.region.placeholder", "Оберіть регіон") }
        static func viewCount(_ count: Int) -> String {
            LocalizationStore.localizedFormat("events.view_count", defaultValue: "%lld переглядів", arguments: [count])
        }
    }

    enum Organizations {
        static var title: String { text("organizations.title", "Organizations") }
        static var detailTitle: String { text("organizations.detail.title", "Деталі організації") }
        static var detailBadge: String { text("organizations.detail.badge", "Організація") }
        static var activityTitle: String { text("organizations.activity.title", "Активність громади") }
        static var heroTitle: String { text("organizations.hero.title", "Разом — ми сильніші") }
        static var heroSubtitle: String { text("organizations.hero.subtitle", "Знайдіть організації, які підтримують українців в Австрії.") }
        static var popularTitle: String { text("organizations.popular.title", "Популярні організації") }
        static var categoriesTitle: String { text("organizations.categories.title", "Категорії") }
        static var searchPlaceholder: String { text("organizations.search.placeholder", "Пошук організацій") }
        static var categorySupport: String { text("organizations.category.support", "Підтримка") }
        static var categoryEducation: String { text("organizations.category.education", "Освіта") }
        static var categoryCulture: String { text("organizations.category.culture", "Культура") }
        static var categoryWork: String { text("organizations.category.work", "Робота") }
        static var categoryChildren: String { text("organizations.category.children", "Для дітей") }
        static var categoryLegal: String { text("organizations.category.legal", "Правова допомога") }
        static var categoryOther: String { text("organizations.category.other", "Інше") }
        static var filterBookmarks: String { text("organizations.filter.bookmarks", "Закладки") }
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
        static var editorTitle: String { text("organizations.editor.title", "Нова організація") }
        static var editTitle: String { text("organizations.editor.edit_title", "Редагувати організацію") }
        static var editorSubtitle: String { text("organizations.editor.subtitle", "Створіть простір для вашої спільноти, подій та новин.") }
        static var fieldName: String { text("organizations.editor.field.name", "Назва спільноти *") }
        static var fieldNamePlaceholder: String { text("organizations.editor.field.name_placeholder", "Наприклад, Український центр у Відні") }
        static var fieldDescription: String { text("organizations.editor.field.description", "Коротко про вас") }
        static var fieldDescriptionPlaceholder: String { text("organizations.editor.field.description_placeholder", "Кому допомагаєте і що робите") }
        static var fieldFullDescription: String { text("organizations.editor.field.full_description", "Детальніше про спільноту") }
        static var fieldFullDescriptionPlaceholder: String { text("organizations.editor.field.full_description_placeholder", "Розкажіть про послуги, події, команду та як до вас звернутися") }
        static var fieldContactEmail: String { text("organizations.editor.field.contact_email", "Email для зв’язку") }
        static var fieldWebsite: String { text("organizations.editor.field.website", "Сайт або сторінка") }
        static var fieldTelegramURL: String { text("organizations.editor.field.telegram_url", "Telegram канал або чат") }
        static var fieldDonationURL: String { text("organizations.editor.field.donation_url", "Посилання для підтримки") }
        static var fieldFacebookURL: String { text("organizations.editor.field.facebook_url", "Facebook") }
        static var fieldInstagramURL: String { text("organizations.editor.field.instagram_url", "Instagram") }
        static var fieldWhatsAppURL: String { text("organizations.editor.field.whatsapp_url", "WhatsApp") }
        static var fieldYouTubeURL: String { text("organizations.editor.field.youtube_url", "YouTube") }
        static var fieldLinkedInURL: String { text("organizations.editor.field.linkedin_url", "LinkedIn") }
        static var fieldMissionStatement: String { text("organizations.editor.field.mission_statement", "Чим ви займаєтесь") }
        static var detailMissionStatementTitle: String { text("organizations.detail.mission_statement", "Чим ми займаємось") }
        static var fieldMissionStatementPlaceholder: String { text("organizations.editor.field.mission_statement_placeholder", "Коротко опишіть головний напрям роботи") }
        static var fieldContactPerson: String { text("organizations.editor.field.contact_person", "Контактна людина") }
        static var fieldContactPersonDisplay: String { text("organizations.detail.contact_person", "Контактна особа") }
        static var fieldRegion: String { text("organizations.editor.field.region", "Федеральна земля *") }
        static var fieldRegionPlaceholder: String { text("organizations.editor.field.region_placeholder", "Оберіть федеральну землю") }
        static var fieldCity: String { text("organizations.editor.field.city", "Місто") }
        static var fieldAddress: String { text("organizations.editor.field.address", "Адреса або район") }
        static var fieldFoundedYear: String { text("organizations.editor.field.founded_year", "Рік заснування") }
        static var fieldFoundedMonth: String { text("organizations.editor.field.founded_month", "Місяць заснування") }
        static var fieldFoundedMonthNone: String { text("organizations.editor.field.founded_month_none", "Не вказано") }
        static var fieldLanguages: String { text("organizations.editor.field.languages", "Мови спілкування") }
        static var publish: String { text("organizations.editor.publish", "Опублікувати") }
        static var submitRequest: String { text("organizations.editor.submit_request", "Подати заявку") }
        static var resubmitRequest: String { text("organizations.editor.resubmit_request", "Надіслати повторно") }
        static var saveChanges: String { text("organizations.editor.save_changes", "Зберегти зміни") }
        static var publishing: String { text("organizations.editor.publishing", "Зберігаємо...") }
        static var publishedSuccessfully: String { text("organizations.editor.success", "Організацію опубліковано.") }
        static var requestSubmittedSuccessfully: String { text("organizations.editor.request_success", "Заявку надіслано на перевірку.") }
        static var updatedSuccessfully: String { text("organizations.editor.updated_success", "Зміни збережено.") }
        static var requestAlreadyReviewed: String { text("organizations.editor.error.request_already_reviewed", "Заявку вже було розглянуто. Оновіть сторінку.") }
        static var imageSectionTitle: String { text("organizations.editor.image_section", "Логотип") }
        static var logoUploadTitle: String { text("organizations.editor.logo_upload_title", "Додати логотип") }
        static var logoUploadHelper: String { text("organizations.editor.logo_upload_helper", "Квадратний логотип виглядатиме найкраще") }
        static var detailsSectionTitle: String { text("organizations.editor.details_section", "Основне") }
        static var categorySectionTitle: String { text("organizations.editor.category_section", "Напрям діяльності *") }
        static var categoryIntegration: String { text("organizations.editor.category.integration", "Інтеграція") }
        static var contactSectionTitle: String { text("organizations.editor.contact_section", "Контакти та посилання") }
        static var phonePlaceholder: String { text("organizations.editor.phone_placeholder", "Телефон") }
        static var socialLinksTitle: String { text("organizations.editor.social_title", "Соцмережі") }
        static var socialPlaceholder: String { text("organizations.editor.social_placeholder", "Instagram, Facebook або інші посилання") }
        static var locationSectionTitle: String { text("organizations.editor.location_section", "Локація") }
        static var locationPlaceholder: String { text("organizations.editor.location_placeholder", "Адреса або назва міста") }
        static var chooseOnMap: String { text("organizations.editor.choose_on_map", "Вибрати на карті") }
        static var aboutSectionTitle: String { text("organizations.about_section", "Про організацію") }
        static var aboutEmptyMessage: String { text("organizations.detail.about_empty", "Повний опис організації поки не додано.") }
        static var mainInformationTitle: String { text("organizations.detail.main_information", "Основна інформація") }
        static var categoryTitle: String { text("organizations.detail.category", "Категорія") }
        static var languagesTitle: String { text("organizations.detail.languages", "Мови") }
        static var foundedTitle: String { text("organizations.detail.founded", "Засновано") }
        static var aboutPlaceholder: String { text("organizations.editor.about_placeholder", "Розкажіть більше про вашу організацію, місію та цілі") }
        static var settingsSectionTitle: String { text("organizations.editor.settings_section", "Додаткові налаштування") }
        static var futureSectionTitle: String { text("organizations.editor.future_section", "Додатково") }
        static var organizationSizeTitle: String { text("organizations.editor.organization_size", "Розмір організації") }
        static var organizationSizeOptions: String { text("organizations.editor.organization_size_options", "Локальна, Регіональна, Всеавстрійська, Міжнародна") }
        static var volunteersNeededTitle: String { text("organizations.editor.volunteers_needed", "Потрібні волонтери") }
        static var volunteersNeededSubtitle: String { text("organizations.editor.volunteers_needed_subtitle", "Пізніше користувачі зможуть відгукуватися на волонтерські потреби.") }
        static var verificationRequestTitle: String { text("organizations.editor.verification_request", "Подати заявку на верифікацію") }
        static var verificationRequestSubtitle: String { text("organizations.editor.verification_request_subtitle", "Підтвердження організації буде доступне пізніше.") }
        static var teamManagementTitle: String { text("organizations.editor.team_management", "Команда організації") }
        static var teamManagementSubtitle: String { text("organizations.editor.team_management_subtitle", "Власник зможе додавати адміністраторів і модераторів.") }
        static var comingSoon: String { text("organizations.editor.coming_soon", "Незабаром") }
        static var visibilityTitle: String { text("organizations.editor.visibility_title", "Видимість організації") }
        static var visibilityPublic: String { text("organizations.editor.visibility_public", "Публічна") }
        static var visibilityHelper: String { text("organizations.editor.visibility_helper", "Хто може бачити вашу організацію") }
        static var moderationNotice: String { text("organizations.editor.moderation_notice", "Після створення ми перевіримо сторінку перед публікацією. Ви зможете оновлювати інформацію пізніше.") }
        static var follow: String { text("organizations.detail.follow", "Підписатися") }
        static var unfollow: String { text("organizations.detail.unfollow", "Відписатися") }
        static var confirmSubscribeTitle: String { text("organizations.subscription.confirm_subscribe.title", "Subscribe to this organization?") }
        static var confirmSubscribeButton: String { text("organizations.subscription.confirm_subscribe.button", "Subscribe") }
        static var confirmUnsubscribeTitle: String { text("organizations.subscription.confirm_unsubscribe.title", "Unsubscribe from this organization?") }
        static var confirmUnsubscribeButton: String { text("organizations.subscription.confirm_unsubscribe.button", "Unsubscribe") }
        static func confirmSubscribeMessage(_ organizationName: String) -> String {
            LocalizationStore.localizedFormat(
                "organizations.subscription.confirm_subscribe.message",
                defaultValue: "You will receive updates from “%@”.",
                arguments: [organizationName]
            )
        }
        static func confirmUnsubscribeMessage(_ organizationName: String) -> String {
            LocalizationStore.localizedFormat(
                "organizations.subscription.confirm_unsubscribe.message",
                defaultValue: "You will stop receiving updates from “%@”.",
                arguments: [organizationName]
            )
        }
        static var message: String { text("organizations.detail.message", "Повідомлення") }
        static var share: String { text("organizations.detail.share", "Поділитися") }
        static var support: String { text("organizations.detail.support", "Підтримати") }
        static var supportOrganizationTitle: String { text("organizations.detail.support_organization_title", "Підтримати організацію") }
        static var supportOrganizationSubtitle: String { text("organizations.detail.support_organization_subtitle", "Допоможіть розвитку спільноти") }
        static var telegramDiscussion: String { text("organizations.detail.telegram_discussion", "Обговорення") }
        static var followers: String { text("organizations.detail.followers", "Підписники") }
        static var verified: String { text("organizations.detail.verified", "Перевірено") }
        static var showOnMap: String { text("organizations.detail.show_on_map", "Показати на карті") }
        static var emptyOrganizationEvents: String { text("organizations.detail.empty_events", "У цієї організації поки немає подій.") }
        static var emptyOrganizationNews: String { text("organizations.detail.empty_news", "У цієї організації поки немає новин.") }
        static var noOrganizationContacts: String { text("organizations.detail.no_contacts", "Організація ще не додала контактів.") }
        static var contactsSubtitle: String { text("organizations.contacts.subtitle", "Зв’яжіться з організацією напряму.") }
        static var contactsEmptyTitle: String { text("organizations.contacts.empty_title", "Організація ще не додала контактів.") }
        static var contactsEmptyMessage: String { text("organizations.contacts.empty_message", "Коли команда додасть сайт, соцмережі або адресу, вони з’являться тут.") }
        static var contactsAdd: String { text("organizations.contacts.add", "Додати контакти") }
        static var contactsEdit: String { text("organizations.contacts.edit", "Редагувати контакти") }
        static var contactsOpenWebsite: String { text("organizations.contacts.open_website", "Відкрити сайт") }
        static var contactsOpenTelegram: String { text("organizations.contacts.open_telegram", "Відкрити Telegram") }
        static var fieldEmail: String { text("organizations.contacts.email", "Email") }
        static var fieldPhone: String { text("organizations.contacts.phone", "Телефон") }
        static var fieldTelegram: String { text("organizations.contacts.telegram", "Telegram") }
        static var fieldInstagram: String { text("organizations.contacts.instagram", "Instagram") }
        static var fieldFacebook: String { text("organizations.contacts.facebook", "Facebook") }
        static var fieldWhatsApp: String { text("organizations.contacts.whatsapp", "WhatsApp") }
        static var fieldYouTube: String { text("organizations.contacts.youtube", "YouTube") }
        static var fieldLinkedIn: String { text("organizations.contacts.linkedin", "LinkedIn") }
        static var fieldLocation: String { text("organizations.contacts.location", "Локація") }
        static var teamComingSoon: String { text("organizations.detail.team_coming_soon", "Власник зможе додавати адміністраторів і модераторів.") }
        static var photosComingSoon: String { text("organizations.detail.photos_coming_soon", "Галерея буде доступна пізніше.") }
        static var photosEmptyTitle: String { text("organizations.photos.empty_title", "Фото поки немає.") }
        static var photosEmptyMessage: String { text("organizations.photos.empty_message", "Коли команда додасть фото, вони з’являться тут.") }
        static var photosAdd: String { text("organizations.photos.add", "Додати фото") }
        static var photosCaption: String { text("organizations.photos.caption", "Підпис") }
        static var photosCaptionPlaceholder: String { text("organizations.photos.caption_placeholder", "Короткий опис фото") }
        static var photosUpload: String { text("organizations.photos.upload", "Завантажити") }
        static var photosUploading: String { text("organizations.photos.uploading", "Завантажуємо фото...") }
        static var photosUploadFailed: String { text("organizations.photos.upload_failed", "Не вдалося завантажити фото.") }
        static var photosLoadFailed: String { text("organizations.photos.load_failed", "Не вдалося завантажити фото організації.") }
        static var photosDelete: String { text("organizations.photos.delete", "Видалити фото") }
        static var photosDeleteConfirmation: String { text("organizations.photos.delete_confirmation", "Видалити це фото?") }
        static var photosDeleteFailed: String { text("organizations.photos.delete_failed", "Не вдалося видалити фото.") }
        static var photosLimitReached: String { text("organizations.photos.limit_reached", "Можна додати до 30 фото.") }
        static var photosPreparing: String { text("organizations.photos.preparing", "Готуємо фото...") }
        static var photosSelectionFailed: String { text("organizations.photos.selection_failed", "Не вдалося обрати фото.") }
        static var showMore: String { text("organizations.detail.show_more", "Показати більше") }
        static var showLess: String { text("organizations.detail.show_less", "Показати менше") }
        static var upcomingEventsTitle: String { text("organizations.detail.upcoming_events", "Найближчі події") }
        static var communityHighlightsTitle: String { text("organizations.detail.community_highlights", "Життя спільноти") }
        static var nearestEventTitle: String { text("organizations.detail.nearest_event", "Найближча подія") }
        static var latestNewsTitle: String { text("organizations.detail.latest_news", "Останні новини") }
        static var latestPhotosTitle: String { text("organizations.detail.latest_photos", "Останні фото") }
        static var viewAction: String { text("organizations.detail.view", "Переглянути") }
        static var allNewsAction: String { text("organizations.detail.all_news", "Усі новини") }
        static var pinnedLabel: String { text("organizations.detail.pinned", "Закріплено") }
        static var latestActivityPrefix: String { text("organizations.detail.latest_activity", "Активність") }
        static var activityEventsShort: String { text("organizations.detail.activity_events_short", "події") }
        static var activityNewsShort: String { text("organizations.detail.activity_news_short", "новини") }
        static var activityPhotosShort: String { text("organizations.detail.activity_photos_short", "фото") }
        static var tabEvents: String { text("organizations.detail.tab_events", "Події") }
        static var tabAbout: String { text("organizations.detail.tab_about", "Про нас") }
        static var tabNews: String { text("organizations.detail.tab_news", "Новини") }
        static var tabContacts: String { text("organizations.detail.tab_contacts", "Контакти") }
        static var tabPhoto: String { text("organizations.detail.tab_photo", "Фото") }
        static var tabTeam: String { text("organizations.detail.tab_team", "Спільнота") }
        static var communityEmpty: String { text("organizations.community.empty", "Поки немає учасників спільноти.") }
        static var communityLoadMore: String { text("organizations.community.load_more", "Показати ще") }
        static var communityPlaceholderProfileMessage: String { text("organizations.community.placeholder_profile_message", "Публічний профіль створиться після наступного входу користувача.") }
        static var communityProfileUnavailable: String { text("organizations.community.profile_unavailable", "Профіль ще не доступний") }
        static var communityOwner: String { text("organizations.community.role.owner", "Власник") }
        static var communityAdmin: String { text("organizations.community.role.admin", "Адмін") }
        static var communityModerator: String { text("organizations.community.role.moderator", "Модератор") }
        static var communityMember: String { text("organizations.community.role.member", "Учасник") }
        static var emptyBookmarked: String { text("organizations.empty.bookmarked", "У вас ще немає організацій у закладках.") }
        static var officialBadge: String { text("organizations.detail.official", "Офіційно") }
        static var addBookmark: String { text("organizations.bookmark.add", "Додати в закладки") }
        static var removeBookmark: String { text("organizations.bookmark.remove", "Прибрати із закладок") }
        static var userFallback: String { text("organizations.comments.user_fallback", "Користувач") }
        static var deleteConfirmation: String { text("organizations.delete.confirmation", "Delete this organization?") }
        static var delete: String { text("organizations.delete", "Delete") }
        static var cancel: String { text("organizations.cancel", "Cancel") }
        static var deleteFailed: String { text("organizations.delete_failed", "Delete Failed") }
        static var dismissError: String { text("organizations.dismiss_error", "OK") }
    }

    enum Guide {
        static var title: String { text("info.title", "Guide") }
        static var subtitle: String { text("guide.subtitle", "Curated practical guidance, official references, and everyday orientation for families in Austria.") }
        static var heroTitle: String { text("guide.hero.title", "Довідник громади") }
        static var heroSubtitle: String { text("guide.hero.subtitle", "Практичні поради, документи та корисні контакти для життя в Австрії.") }
        static var pinnedTitle: String { text("guide.pinned", "Important Now") }
        static var categoriesTitle: String { text("guide.categories", "Categories") }
        static var popularCategoriesTitle: String { text("guide.categories.popular", "Популярні категорії") }
        static var allCategories: String { text("guide.categories.all", "All") }
        static var allArticlesTitle: String { text("guide.articles", "Articles") }
        static var moreArticlesTitle: String { text("guide.articles.more", "More articles") }
        static var newcomersTitle: String { text("guide.section.newcomers", "First steps") }
        static var featuredTitle: String { text("guide.section.featured", "Featured guidance") }
        static var recentlyUpdatedTitle: String { text("guide.section.recently_updated", "Recently updated") }
        static var emergencyTitle: String { text("guide.section.emergency", "Emergency and urgent help") }
        static var officialSource: String { text("guide.official_source", "Official source") }
        static var sourceSectionTitle: String { text("guide.sources.title", "Sources") }
        static var sourceSectionSubtitle: String { text("guide.sources.subtitle", "Open the source directly to verify details and check the latest official information.") }
        static var sourceSectionPrimaryTitle: String { text("guide.sources.primary_title", "Primary source") }
        static var sourceSectionPrimarySubtitle: String { text("guide.sources.primary_subtitle", "Official information used as the main reference for this article.") }
        static var sourceSectionSupportingTitle: String { text("guide.sources.supporting_title", "Supporting sources") }
        static var sourceSectionSupportingSubtitle: String { text("guide.sources.supporting_subtitle", "Additional references and practical links related to this topic.") }
        static var openSourceAction: String { text("guide.sources.open", "Open source") }
        static var openOfficialSourceAction: String { text("guide.sources.open_official", "Open official source") }
        static var openExternalSourceAction: String { text("guide.sources.open_external", "Open external source") }
        static var opensExternalWebsiteHint: String { text("guide.sources.opens_external", "Opens external website") }
        static var articleOverviewLabel: String { text("guide.detail.overview_label", "Overview") }
        static var articleContainsTitle: String { text("guide.contains.title", "In this article") }
        static var articleContainsSubtitle: String { text("guide.contains.subtitle", "Quick overview of the sections below.") }
        static var activeFiltersTitle: String { text("guide.filters.active.title", "Current filters") }
        static var activeFiltersEmptyHint: String { text("guide.filters.active.empty_hint", "Use filters to narrow the guide by type, place, or audience.") }
        static var placeholderChipAccessibilityHint: String { text("guide.placeholder_chip.accessibility_hint", "Temporary filter") }
        static var filterSearchLabel: String { text("guide.filters.label.search", "Search") }
        static var filterCategoryLabel: String { text("guide.filters.label.category", "Category") }
        static var filterTypeLabel: String { text("guide.filters.label.type", "Type") }
        static var filterRegionLabel: String { text("guide.filters.label.region", "Region") }
        static var filterAudienceLabel: String { text("guide.filters.label.audience", "Audience") }
        static var searchPlaceholder: String { text("guide.search", "Search the guide") }
        static var filterAllTypes: String { text("guide.filter.all_types", "All types") }
        static var filterAllAudiences: String { text("guide.filter.all_audiences", "All audiences") }
        static var filterClear: String { text("guide.filter.clear", "Clear") }
        static var contentTypeGuide: String { text("guide.content_type.guide", "Guide") }
        static var contentTypeQuickInfo: String { text("guide.content_type.quick_info", "Quick info") }
        static var contentTypeChecklist: String { text("guide.content_type.checklist", "Checklist") }
        static var contentTypeContact: String { text("guide.content_type.contact", "Contacts") }
        static var contentTypeProcess: String { text("guide.content_type.process", "Process") }
        static var reviewDueSoon: String { text("guide.review.due_soon", "Review soon") }
        static var reviewOverdue: String { text("guide.review.overdue", "Needs review") }
        static var reviewArchived: String { text("guide.review.archived", "Archived") }
        static var loading: String { text("guide.loading", "Loading guide articles...") }
        static var emptyTitle: String { text("guide.empty.title", "No guide articles yet") }
        static var emptyMessage: String { text("guide.empty.message", "Practical guidance will appear here once it has been published.") }
        static var noMatchesTitle: String { text("guide.no_matches.title", "No matching articles") }
        static var noResults: String { text("guide.no_results", "No guide articles match this search right now.") }
        static var noResultsNarrowHint: String { text("guide.no_results.narrow_hint", "Your current search or filters may be too narrow. Try clearing one filter or broadening the search.") }
        static var sourceAvailableLabel: String { text("guide.source.available", "Source available") }
        static var officialSourceAvailableLabel: String { text("guide.source.official_available", "Official source") }
        static var blockTypeText: String { text("guide.block_type.text", "Text") }
        static var blockTypeWarning: String { text("guide.block_type.warning", "Warning") }
        static var blockTypeInfoBox: String { text("guide.block_type.info_box", "Info box") }
        static var blockTypeSteps: String { text("guide.block_type.steps", "Steps") }
        static var blockTypeChecklist: String { text("guide.block_type.checklist", "Checklist") }
        static var blockTypeLinks: String { text("guide.block_type.links", "Links") }
        static var blockTypeContacts: String { text("guide.block_type.contacts", "Contacts") }
        static var loadNetworkError: String { text("guide.error.load.network", "Unable to load guide articles. Check your connection and try again.") }
        static var loadPermissionError: String { text("guide.error.load.permission", "You do not have permission to view guide articles.") }
        static var loadValidationError: String { text("guide.error.load.validation", "The guide data could not be loaded.") }
        static var loadUnknownError: String { text("guide.error.load.unknown", "Something went wrong while loading guide articles.") }
        static var articleDetailTitle: String { text("guide.detail.title", "Guide Article") }
        static var categoryFirstSteps: String { text("guide.category.first_steps", "First steps") }
        static var categoryDocuments: String { text("guide.category.documents", "Documents") }
        static var categoryAnmeldung: String { text("guide.category.anmeldung", "Anmeldung") }
        static var categoryWork: String { text("guide.category.work", "Work") }
        static var categoryFinance: String { text("guide.category.finance", "Finance") }
        static var categoryFamily: String { text("guide.category.family", "Family") }
        static var categoryHealth: String { text("guide.category.health", "Health") }
        static var categoryHousing: String { text("guide.category.housing", "Housing") }
        static var categoryTransport: String { text("guide.category.transport", "Transport") }
        static var categoryEducation: String { text("guide.category.education", "Education") }
        static var categoryLaw: String { text("guide.category.law", "Law") }
        static var categoryEmergency: String { text("guide.category.emergency", "Emergency") }
        static var categoryUkrainianCommunity: String { text("guide.category.ukrainian_community", "Ukrainian community") }
        static var categoryLifeInAustria: String { text("guide.category.life_in_austria", "Life in Austria") }
        static var categoryAMS: String { text("guide.category.ams", "AMS") }
        static var categoryMedicine: String { text("guide.category.medicine", "Medicine") }
        static var categoryChildren: String { text("guide.category.children", "Children") }
        static var categoryBusiness: String { text("guide.category.business", "Business") }
        static var categoryContacts: String { text("guide.category.contacts", "Contacts") }

        static func resultsCount(_ count: Int) -> String {
            LocalizationStore.localizedFormat(
                "guide.results.count",
                defaultValue: "%lld articles",
                arguments: [count]
            )
        }

        static func noResultsForSummary(_ summary: String) -> String {
            LocalizationStore.localizedFormat(
                "guide.no_results.summary",
                defaultValue: "No guide articles match %@ right now.",
                arguments: [summary.lowercased()]
            )
        }

        static func filterSummaryItem(_ label: String, _ value: String) -> String {
            LocalizationStore.localizedFormat(
                "guide.filters.summary_item",
                defaultValue: "%1$@: %2$@",
                arguments: [label, value]
            )
        }
    }

    enum Info {
        static var title: String { Guide.title }
        static var subtitle: String { Guide.subtitle }
        static var heroTitle: String { Guide.heroTitle }
        static var heroSubtitle: String { Guide.heroSubtitle }
        static var pinnedTitle: String { Guide.pinnedTitle }
        static var categoriesTitle: String { Guide.categoriesTitle }
        static var popularCategoriesTitle: String { Guide.popularCategoriesTitle }
        static var allCategories: String { Guide.allCategories }
        static var allArticlesTitle: String { Guide.allArticlesTitle }
        static var newcomersTitle: String { Guide.newcomersTitle }
        static var featuredTitle: String { Guide.featuredTitle }
        static var recentlyUpdatedTitle: String { Guide.recentlyUpdatedTitle }
        static var emergencyTitle: String { Guide.emergencyTitle }
        static var officialSource: String { Guide.officialSource }
        static var searchPlaceholder: String { Guide.searchPlaceholder }
        static var filterAllTypes: String { Guide.filterAllTypes }
        static var filterAllAudiences: String { Guide.filterAllAudiences }
        static var filterClear: String { Guide.filterClear }
        static var contentTypeGuide: String { Guide.contentTypeGuide }
        static var contentTypeQuickInfo: String { Guide.contentTypeQuickInfo }
        static var contentTypeChecklist: String { Guide.contentTypeChecklist }
        static var contentTypeContact: String { Guide.contentTypeContact }
        static var contentTypeProcess: String { Guide.contentTypeProcess }
        static var reviewDueSoon: String { Guide.reviewDueSoon }
        static var reviewOverdue: String { Guide.reviewOverdue }
        static var reviewArchived: String { Guide.reviewArchived }
        static var loading: String { Guide.loading }
        static var emptyTitle: String { Guide.emptyTitle }
        static var emptyMessage: String { Guide.emptyMessage }
        static var noMatchesTitle: String { Guide.noMatchesTitle }
        static var noResults: String { Guide.noResults }
        static var loadNetworkError: String { Guide.loadNetworkError }
        static var loadPermissionError: String { Guide.loadPermissionError }
        static var loadValidationError: String { Guide.loadValidationError }
        static var loadUnknownError: String { Guide.loadUnknownError }
        static var articleDetailTitle: String { Guide.articleDetailTitle }
        static var categoryFirstSteps: String { Guide.categoryFirstSteps }
        static var categoryDocuments: String { Guide.categoryDocuments }
        static var categoryAnmeldung: String { Guide.categoryAnmeldung }
        static var categoryWork: String { Guide.categoryWork }
        static var categoryFinance: String { Guide.categoryFinance }
        static var categoryFamily: String { Guide.categoryFamily }
        static var categoryHealth: String { Guide.categoryHealth }
        static var categoryHousing: String { Guide.categoryHousing }
        static var categoryTransport: String { Guide.categoryTransport }
        static var categoryEducation: String { Guide.categoryEducation }
        static var categoryLaw: String { Guide.categoryLaw }
        static var categoryEmergency: String { Guide.categoryEmergency }
        static var categoryUkrainianCommunity: String { Guide.categoryUkrainianCommunity }
        static var categoryLifeInAustria: String { Guide.categoryLifeInAustria }
        static var categoryAMS: String { Guide.categoryAMS }
        static var categoryMedicine: String { Guide.categoryMedicine }
        static var categoryChildren: String { Guide.categoryChildren }
        static var categoryBusiness: String { Guide.categoryBusiness }
        static var categoryContacts: String { Guide.categoryContacts }
    }

    enum GuideManagement {
        static var title: String { text("guide.management.title", "Guide management") }
        static var subtitle: String { text("guide.management.subtitle", "Create, edit, and organize guide drafts before review.") }
        static var entrySubtitle: String { text("guide.management.entry.subtitle", "Prepare articles, reviews, reports, categories, and archive workflows.") }
        static var placeholderStatus: String { text("guide.management.placeholder.status", "Planned") }
        static var localEditorStatus: String { text("guide.management.local_editor.status", "Local editor") }
        static var createMaterial: String { text("guide.management.create_material", "Create material") }
        static var createMaterialSubtitle: String { text("guide.management.create_material.subtitle", "Draft a new guide item for the knowledge base.") }
        static var drafts: String { text("guide.management.drafts", "Drafts") }
        static var draftsSubtitle: String { text("guide.management.drafts.subtitle", "Materials that are not ready for review yet.") }
        static var inReview: String { text("guide.management.in_review", "In review") }
        static var inReviewSubtitle: String { text("guide.management.in_review.subtitle", "Items waiting for owner or editor review.") }
        static var approved: String { text("guide.management.approved", "Approved") }
        static var approvedSubtitle: String { text("guide.management.approved.subtitle", "Approved materials waiting for publishing.") }
        static var published: String { text("guide.management.published", "Published") }
        static var publishedSubtitle: String { text("guide.management.published.subtitle", "Live guide materials visible to the community.") }
        static var needsReview: String { text("guide.management.needs_review", "Needs review") }
        static var needsReviewSubtitle: String { text("guide.management.needs_review.subtitle", "Outdated or flagged materials to re-check.") }
        static var errorReports: String { text("guide.management.error_reports", "Error reports") }
        static var errorReportsSubtitle: String { text("guide.management.error_reports.subtitle", "Future user reports about incorrect or missing information.") }
        static var subcategories: String { text("guide.management.subcategories", "Subcategories") }
        static var subcategoriesSubtitle: String { text("guide.management.subcategories.subtitle", "Future organization for nested guide topics.") }
        static var archive: String { text("guide.management.archive", "Archive") }
        static var archiveSubtitle: String { text("guide.management.archive.subtitle", "Retired guide materials kept out of active use.") }
        static var editAction: String { text("guide.management.edit.action", "Edit") }
        static var deleteAction: String { text("guide.management.delete.action", "Delete") }
        static var deleteConfirmationTitle: String { text("guide.management.delete.confirm.title", "Delete guide article?") }
        static func deleteConfirmationMessage(_ title: String) -> String {
            LocalizationStore.localizedFormat(
                "guide.management.delete.confirm.message",
                defaultValue: "This permanently deletes “%@”. This cannot be undone.",
                arguments: [title]
            )
        }
        static var approveAction: String { text("guide.management.approve.action", "Approve") }
        static var approveConfirmationTitle: String { text("guide.management.approve.confirm.title", "Approve article?") }
        static var approveConfirmationMessage: String { text("guide.management.approve.confirm.message", "This marks the article approved but does not publish it yet.") }
        static var approving: String { text("guide.management.approve.saving", "Approving...") }
        static var approvePermissionError: String { text("guide.management.approve.error.permission", "Only owners can approve guide articles.") }
        static var approveValidationError: String { text("guide.management.approve.error.validation", "This article is no longer ready for approval.") }
        static var approveNotFoundError: String { text("guide.management.approve.error.not_found", "The selected guide article could not be found.") }
        static var approveFailed: String { text("guide.management.approve.error.unknown", "Something went wrong while approving this article.") }
        static var reviewMetadataTitle: String { text("guide.management.review_metadata.title", "Review metadata") }
        static var submittedAtLabel: String { text("guide.management.review_metadata.submitted_at", "Submitted") }
        static var submittedByLabel: String { text("guide.management.review_metadata.submitted_by", "Submitted by") }
        static var reviewedByLabel: String { text("guide.management.review_metadata.reviewed_by", "Reviewed by") }
        static var lastReviewedAtLabel: String { text("guide.management.review_metadata.last_reviewed_at", "Last reviewed") }
        static var nextReviewAtLabel: String { text("guide.management.review_metadata.next_review_at", "Next review") }
        static var reviewIntervalLabel: String { text("guide.management.review_metadata.review_interval", "Review interval") }
        static var reviewIntervalCritical: String { text("guide.management.review_interval.critical_months", "3 months") }
        static var reviewIntervalNormal: String { text("guide.management.review_interval.normal_months", "6 months") }
        static var reviewIntervalStable: String { text("guide.management.review_interval.stable_months", "12 months") }
        static var publishAction: String { text("guide.management.publish.action", "Publish") }
        static var publishConfirmationTitle: String { text("guide.management.publish.confirm.title", "Publish article?") }
        static var publishConfirmationMessage: String { text("guide.management.publish.confirm.message", "This makes the guide article visible to the community.") }
        static var publishing: String { text("guide.management.publish.saving", "Publishing...") }
        static var publishPermissionError: String { text("guide.management.publish.error.permission", "Only owners can publish guide articles.") }
        static var publishValidationError: String { text("guide.management.publish.error.validation", "This article is no longer ready for publishing.") }
        static var publishNotFoundError: String { text("guide.management.publish.error.not_found", "The selected guide article could not be found.") }
        static var publishFailed: String { text("guide.management.publish.error.unknown", "Something went wrong while publishing this article.") }
    }

    enum GuideEditor {
        static var title: String { text("guide.editor.title", "Create guide material") }
        static var subtitle: String { text("guide.editor.subtitle", "Draft editor for creating and updating guide materials before review.") }
        static var basicsSection: String { text("guide.editor.section.basics", "Basics") }
        static var classificationSection: String { text("guide.editor.section.classification", "Classification") }
        static var contentSection: String { text("guide.editor.section.content", "Content") }
        static var reviewSection: String { text("guide.editor.section.review", "Review settings") }
        static var titleField: String { text("guide.editor.field.title", "Title") }
        static var titlePlaceholder: String { text("guide.editor.placeholder.title", "Short, clear article title") }
        static var titleHelp: String { text("guide.editor.help.title", "Readers see this first in lists and again at the top of the article.") }
        static var summaryField: String { text("guide.editor.field.summary", "Summary") }
        static var summaryHelp: String { text("guide.editor.help.summary", "Use one or two short sentences. This appears in cards and under the article title.") }
        static var bodyFallbackField: String { text("guide.editor.field.body_fallback", "Body fallback") }
        static var bodyFallbackHelp: String { text("guide.editor.help.body_fallback", "Body is fallback content. Readers see it only when no content blocks are added below.") }
        static var categoryField: String { text("guide.editor.field.category", "Category") }
        static var categoryPlaceholder: String { text("guide.editor.placeholder.category", "Select category") }
        static var contentTypeField: String { text("guide.editor.field.content_type", "Content type") }
        static var federalStateField: String { text("guide.editor.field.federal_state", "Federal state") }
        static var austriaWide: String { text("guide.editor.option.austria_wide", "Austria-wide") }
        static var audienceField: String { text("guide.editor.field.audience", "Audience") }
        static var audiencePlaceholder: String { text("guide.editor.placeholder.audience", "newcomers, families, students") }
        static var audienceHelp: String { text("guide.editor.help.audience", "Separate audience values with commas.") }
        static var reviewIntervalField: String { text("guide.editor.field.review_interval", "Review interval") }
        static var priorityField: String { text("guide.editor.field.priority", "Priority") }
        static var isFeaturedField: String { text("guide.editor.field.is_featured", "Featured") }
        static var officialSourcesRequiredField: String { text("guide.editor.field.official_sources_required", "Official sources required") }
        static var contentBlocksField: String { text("guide.editor.field.content_blocks", "Content blocks") }
        static var contentBlocksPlaceholder: String { text("guide.editor.content_blocks.placeholder", "Structured content blocks will be added in a later pass. Use body fallback for now.") }
        static var contentBlocksEmpty: String { text("guide.editor.content_blocks.empty", "No structured content blocks yet.") }
        static var contentBlocksHelp: String { text("guide.editor.help.content_blocks", "If content blocks exist, readers see the blocks instead of the body. Blocks render in the order shown below.") }
        static var articleSourceLinksField: String { text("guide.editor.field.article_source_links", "Article sources") }
        static var articleSourceLinksEmpty: String { text("guide.editor.article_source_links.empty", "No article sources yet.") }
        static var articleSourceLinksHelp: String { text("guide.editor.help.article_source_links", "If Official sources required is enabled, add at least one article source and mark it as Official source.") }
        static var addArticleSourceLink: String { text("guide.editor.action.add_article_source_link", "Add article source") }
        static var addContentBlock: String { text("guide.editor.action.add_content_block", "Add content block") }
        static var readerOrderTitle: String { text("guide.editor.reader_order.title", "Reader order") }
        static var readerOrderHelp: String { text("guide.editor.reader_order.help", "This is the order readers see on the article page. Use the arrows on each block to move it earlier or later.") }
        static var blockSummaryUntitled: String { text("guide.editor.block_summary.untitled", "Untitled") }
        static var blockSummaryEmpty: String { text("guide.editor.block_summary.empty", "Add content to show a reader summary.") }
        static var blockTitlePlaceholder: String { text("guide.editor.placeholder.block_title", "Optional block title") }
        static var blockTextField: String { text("guide.editor.field.block_text", "Text") }
        static var blockMessageField: String { text("guide.editor.field.block_message", "Message") }
        static var blockStepsField: String { text("guide.editor.field.block_steps", "Steps") }
        static var blockStepsEmpty: String { text("guide.editor.block_steps.empty", "No steps yet.") }
        static var stepTextPlaceholder: String { text("guide.editor.placeholder.step_text", "Step text") }
        static var addStep: String { text("guide.editor.action.add_step", "Add step") }
        static var deleteStep: String { text("guide.editor.action.delete_step", "Delete step") }
        static var moveStepUp: String { text("guide.editor.action.move_step_up", "Move step up") }
        static var moveStepDown: String { text("guide.editor.action.move_step_down", "Move step down") }
        static var blockChecklistField: String { text("guide.editor.field.block_checklist", "Checklist") }
        static var blockChecklistEmpty: String { text("guide.editor.block_checklist.empty", "No checklist items yet.") }
        static var checklistItemPlaceholder: String { text("guide.editor.placeholder.checklist_item", "Checklist item") }
        static var addChecklistItem: String { text("guide.editor.action.add_checklist_item", "Add checklist item") }
        static var deleteChecklistItem: String { text("guide.editor.action.delete_checklist_item", "Delete checklist item") }
        static var moveChecklistItemUp: String { text("guide.editor.action.move_checklist_item_up", "Move checklist item up") }
        static var moveChecklistItemDown: String { text("guide.editor.action.move_checklist_item_down", "Move checklist item down") }
        static var blockLinksField: String { text("guide.editor.field.block_links", "Links") }
        static var blockLinksEmpty: String { text("guide.editor.block_links.empty", "No links yet.") }
        static var linkTitlePlaceholder: String { text("guide.editor.placeholder.link_title", "Link title") }
        static var linkURLPlaceholder: String { text("guide.editor.placeholder.link_url", "https://example.at") }
        static var linkSourceNamePlaceholder: String { text("guide.editor.placeholder.link_source_name", "Source name") }
        static var linkIsOfficial: String { text("guide.editor.field.link_is_official", "Official source") }
        static var addLink: String { text("guide.editor.action.add_link", "Add link") }
        static var deleteLink: String { text("guide.editor.action.delete_link", "Delete link") }
        static var moveLinkUp: String { text("guide.editor.action.move_link_up", "Move link up") }
        static var moveLinkDown: String { text("guide.editor.action.move_link_down", "Move link down") }
        static var blockContactsField: String { text("guide.editor.field.block_contacts", "Contacts") }
        static var blockContactsEmpty: String { text("guide.editor.block_contacts.empty", "No contacts yet.") }
        static var contactNamePlaceholder: String { text("guide.editor.placeholder.contact_name", "Contact name") }
        static var contactDescriptionPlaceholder: String { text("guide.editor.placeholder.contact_description", "Description") }
        static var contactPhonePlaceholder: String { text("guide.editor.placeholder.contact_phone", "Phone") }
        static var contactEmailPlaceholder: String { text("guide.editor.placeholder.contact_email", "Email") }
        static var contactWebsitePlaceholder: String { text("guide.editor.placeholder.contact_website", "Website") }
        static var addContact: String { text("guide.editor.action.add_contact", "Add contact") }
        static var deleteContact: String { text("guide.editor.action.delete_contact", "Delete contact") }
        static var moveContactUp: String { text("guide.editor.action.move_contact_up", "Move contact up") }
        static var moveContactDown: String { text("guide.editor.action.move_contact_down", "Move contact down") }
        static var blockTypeText: String { text("guide.editor.block_type.text", "Text") }
        static var blockTypeWarning: String { text("guide.editor.block_type.warning", "Warning") }
        static var blockTypeInfoBox: String { text("guide.editor.block_type.info_box", "Info box") }
        static var blockTypeSteps: String { text("guide.editor.block_type.steps", "Steps") }
        static var blockTypeChecklist: String { text("guide.editor.block_type.checklist", "Checklist") }
        static var blockTypeLinks: String { text("guide.editor.block_type.links", "Links") }
        static var blockTypeContacts: String { text("guide.editor.block_type.contacts", "Contacts") }
        static var moveBlockUp: String { text("guide.editor.action.move_block_up", "Move block up") }
        static var moveBlockDown: String { text("guide.editor.action.move_block_down", "Move block down") }
        static var deleteBlock: String { text("guide.editor.action.delete_block", "Delete block") }
        static var unsupportedBlockPlaceholder: String { text("guide.editor.unsupported_block.placeholder", "This block type will be editable in a later pass.") }
        static var backendNotice: String { text("guide.editor.backend_notice", "Drafts can be saved, reopened, edited, archived, and submitted for review. Approved articles are published from the review preview.") }
        static var validateAction: String { text("guide.editor.action.validate", "Validate") }
        static var saveDraftAction: String { text("guide.editor.action.save_draft", "Save draft") }
        static var saveChangesAction: String { text("guide.editor.action.save_changes", "Save changes") }
        static var submitForReviewAction: String { text("guide.editor.action.submit_for_review", "Submit for review") }
        static var submitForReviewConfirmationTitle: String { text("guide.editor.submit.confirm.title", "Submit for review?") }
        static var submitForReviewConfirmationMessage: String { text("guide.editor.submit.confirm.message", "This moves the draft out of editable drafts and into review.") }
        static var validationSuccess: String { text("guide.editor.validation.success", "Draft looks valid.") }
        static var savingDraft: String { text("guide.editor.save.saving", "Saving draft...") }
        static var draftSaved: String { text("guide.editor.save.saved", "Draft saved.") }
        static var missingAuthorError: String { text("guide.editor.save.missing_author", "Sign in before saving guide materials.") }
        static var archiveUnavailable: String { text("guide.editor.archive.unavailable", "Archive is available only for existing guide materials.") }
        static var submitUnavailable: String { text("guide.editor.submit.unavailable", "Save this draft before submitting it for review.") }
        static var submitUnsavedChanges: String { text("guide.editor.submit.unsaved_changes", "Save draft changes before submitting for review.") }
        static var saveNotImplemented: String { text("guide.editor.save.not_implemented", "This guide draft could not be saved. Check the draft state and try again.") }
        static var saveNetworkError: String { text("guide.editor.save.error.network", "Unable to save the guide draft. Check your connection and try again.") }
        static var savePermissionError: String { text("guide.editor.save.error.permission", "You do not have permission to save guide materials.") }
        static var saveNotFoundError: String { text("guide.editor.save.error.not_found", "The selected guide material could not be found.") }
        static var saveFailed: String { text("guide.editor.save.error.unknown", "Something went wrong while saving the guide draft.") }
        static var reviewIntervalCritical: String { text("guide.editor.review_interval.critical", "Critical") }
        static var reviewIntervalNormal: String { text("guide.editor.review_interval.normal", "Normal") }
        static var reviewIntervalStable: String { text("guide.editor.review_interval.stable", "Stable") }

        static func readerOrderPosition(_ position: Int, _ total: Int) -> String {
            "Reader order \(position) of \(total)"
        }
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
        static var organizationManagementIntro: String { text("profile.organization_management.intro", "Організації, якими ви керуєте або допомагаєте керувати.") }
        static var organizationRoleOwner: String { text("profile.organization.role.owner", "Власник") }
        static var organizationRoleAdmin: String { text("profile.organization.role.admin", "Адмін") }
        static var organizationRoleModerator: String { text("profile.organization.role.moderator", "Модератор") }
        static var organizationRoleMember: String { text("profile.organization.role.member", "Учасник") }
        static var organizationRolePlatformOwner: String { text("profile.organization.role.platform_owner", "Власник платформи") }
        static var organizationRequests: String { text("profile.organization.requests", "Мої заявки") }
        static var subscribedOrganizations: String { text("profile.organization.subscribed", "Підписані організації") }
        static var previewOrganizationRequest: String { text("profile.organization.request.preview", "Переглянути заявку") }
        static var organizationOpen: String { text("profile.organization.open", "Відкрити") }
        static var organizationManage: String { text("profile.organization.manage", "Керувати") }
        static var organizationStatEvents: String { text("profile.organization.stat.events", "події") }
        static var organizationStatNews: String { text("profile.organization.stat.news", "новини") }
        static var organizationStatSubscribers: String { text("profile.organization.stat.subscribers", "підписники") }
        static var organizationInfoSection: String { text("profile.organization.info_section", "Інформація організації") }
        static var organizationInfoLockedSubtitle: String { text("profile.organization.info_locked.subtitle", "Доступно для власника та адміна організації.") }
        static var organizationPhotosSection: String { text("profile.organization.photos_section", "Фото") }
        static var organizationPhotosPlaceholder: String { text("profile.organization.photos.placeholder", "Галерея організації буде додана пізніше.") }
        static var organizationContactsSection: String { text("profile.organization.contacts_section", "Контакти") }
        static var organizationContactsEditSubtitle: String { text("profile.organization.contacts.edit_subtitle", "Редагуються в інформації організації.") }
        static var organizationTeamSection: String { text("profile.organization.team.section", "Команда") }
        static var organizationTeamAddMember: String { text("profile.organization.team.add_member", "Додати учасника") }
        static var organizationTeamEmptyTitle: String { text("profile.organization.team.empty_title", "Команда не завантажена.") }
        static var organizationTeamEmptyMessage: String { text("profile.organization.team.empty_message", "Тут відображатимуться власник, адміни та модератори організації.") }
        static var organizationTeamSearchPlaceholder: String { text("profile.organization.team.search_placeholder", "Пошук за іменем або містом") }
        static var organizationTeamRolePicker: String { text("profile.organization.team.role_picker", "Роль") }
        static var organizationTeamNoUsers: String { text("profile.organization.team.no_users", "Користувачів не знайдено.") }
        static var organizationTeamMissingProfile: String { text("profile.organization.team.missing_profile", "Профіль ще не доступний") }
        static var organizationTeamSubscribeToAssign: String { text("profile.organization.team.subscribe_to_assign", "Щоб призначити користувача, він має підписатися на організацію.") }
        static var organizationTeamLoadFailed: String { text("profile.organization.team.error.load_failed", "Не вдалося завантажити команду організації.") }
        static var organizationTeamUserSearchFailed: String { text("profile.organization.team.error.user_search_failed", "Не вдалося завантажити користувачів для пошуку.") }
        static var organizationTeamPermissionDenied: String { text("profile.organization.team.error.permission_denied", "Недостатньо прав для керування командою.") }
        static var organizationTeamOwnerCanAssignOnlyAdminModerator: String { text("profile.organization.team.error.owner_assign_limited", "Власник організації може призначати лише адмінів і модераторів.") }
        static var organizationTeamOwnerCannotRemoveOwner: String { text("profile.organization.team.error.owner_remove_owner", "Власник організації не може зняти роль власника.") }
        static var organizationTeamCannotRemoveLastOwner: String { text("profile.organization.team.error.last_owner", "Не можна видалити останнього власника організації.") }
        static var organizationTeamUserProfileMissing: String { text("profile.organization.team.error.user_profile_missing", "Профіль користувача не знайдено.") }
        static var organizationTeamUpdated: String { text("profile.organization.team.status.updated", "Команду оновлено.") }
        static var organizationTeamSaveFailed: String { text("profile.organization.team.error.save_failed", "Не вдалося зберегти зміни команди.") }
        static var organizationTeamRemoveRole: String { text("profile.organization.team.remove_role", "Зняти роль") }
        static var organizationTeamSaveRole: String { text("profile.organization.team.save_role", "Зберегти роль") }
        static var organizationTeamChangeOwner: String { text("profile.organization.team.change_owner", "Змінити власника") }
        static var organizationTeamOwnerRequiredExplanation: String { text("profile.organization.team.owner_required_explanation", "Організація завжди повинна мати власника. Щоб змінити власника, оберіть нового.") }
        static var organizationTeamTransferOwnerConfirmation: String { text("profile.organization.team.transfer_owner_confirmation", "Передати власника організації?") }
        static var organizationTeamNoCurrentRole: String { text("profile.organization.team.no_current_role", "Без ролі в цій організації") }
        static var organizationTeamOwnerChangePlatformOnly: String { text("profile.organization.team.error.owner_change_platform_only", "Змінити власника може лише owner платформи.") }
        static var organizationTeamUnavailable: String { text("profile.organization.team.unavailable", "Недоступно") }
        static var organizationTeamRoleActions: String { text("profile.organization.team.role_actions", "Дії з роллю") }
        static var contentManagement: String { text("profile.content_management", "Content Management") }
        static var contentManagementSubtitle: String { text("profile.content_management.subtitle", "Manage app-owned community news and events.") }
        static var appAdministration: String { text("profile.app_administration", "App Administration") }
        static var feedbackSupport: String { text("profile.feedback_support", "Feedback & Support") }
        static var manageAppNews: String { text("profile.manage_app_news", "Manage app News") }
        static var manageAppEvents: String { text("profile.manage_app_events", "Manage app Events") }
        static var createOrganizationNews: String { text("profile.create_organization_news", "Create organization News") }
        static var createOrganizationEvent: String { text("profile.create_organization_event", "Create organization Event") }
        static var editOrganizationDetails: String { text("profile.edit_organization_details", "Edit organization details") }
        static var noManagedOrganizations: String { text("profile.no_managed_organizations", "У вас поки немає організацій для керування.") }
        static var noOrganizations: String { text("profile.no_organizations", "У вас поки немає організацій.") }
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
        static var profilePhoto: String { text("profile.photo", "Фото профілю") }
        static var emailReadOnlyHint: String { text("profile.email_read_only_hint", "Your email address is managed through account sign-in and cannot be changed here yet.") }
        static var telegramUsername: String { text("profile.telegram", "Telegram username") }
        static var region: String { text("profile.region", "Region") }
        static var saveProfile: String { text("profile.save", "Save") }
        static var saveChanges: String { text("profile.save_changes", "Зберегти зміни") }
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
        static var guestPlatformDescription: String { text("profile.guest.platform_description", "Новини, події, організації та довідник доступні для перегляду. Акаунт відкриває збереження, реєстрації та участь у спільнотах.") }
        static var guestWelcomeTitle: String { text("profile.guest.welcome_title", "Ласкаво просимо") }
        static var guestWelcomeSubtitle: String { text("profile.guest.welcome_subtitle", "Створіть акаунт, щоб зберігати події, підписуватись на організації та отримувати сповіщення.") }
        static var continueAsGuest: String { text("profile.guest.continue", "Продовжити як гість") }
        static var afterRegistrationTitle: String { text("profile.guest.after_registration.title", "Після реєстрації") }
        static var afterRegistrationSubtitle: String { text("profile.guest.after_registration.subtitle", "Особистий профіль відкриває збереження, підписки та персональні оновлення.") }
        static var afterRegistrationEventsSubtitle: String { text("profile.guest.after_registration.events", "Реєстрації та історія участі в одному місці.") }
        static var afterRegistrationSavedSubtitle: String { text("profile.guest.after_registration.saved", "Новини, події та довідник для швидкого повернення.") }
        static var personalRegion: String { text("profile.guest.personal_region", "Персональний регіон") }
        static var personalRegionSubtitle: String { text("profile.guest.personal_region.subtitle", "Локальні події та організації у вашій федеральній землі.") }
        static var guestAvailableTitle: String { text("profile.guest.available.title", "Доступно без акаунта") }
        static var guestAvailableSubtitle: String { text("profile.guest.available.subtitle", "Основний контент можна переглядати одразу.") }
        static var guestBrowseNews: String { text("profile.guest.available.news", "Перегляд новин") }
        static var guestBrowseEvents: String { text("profile.guest.available.events", "Перегляд подій") }
        static var guestBrowseOrganizations: String { text("profile.guest.available.organizations", "Перегляд організацій") }
        static var guestSettingsSupportTitle: String { text("profile.guest.settings_support.title", "Налаштування і підтримка") }
        static var guestSettingsSupportSubtitle: String { text("profile.guest.settings_support.subtitle", "Базові параметри застосунку та юридична інформація.") }
        static var platformPreviewTitle: String { text("profile.platform_preview.title", "Платформа") }
        static var platformPreviewSubtitle: String { text("profile.platform_preview.subtitle", "Основні розділи залишаються доступними для перегляду.") }
        static var previewNewsSubtitle: String { text("profile.preview.news", "Оновлення громади та важливі повідомлення.") }
        static var previewEventsSubtitle: String { text("profile.preview.events", "Зустрічі, консультації та події поруч.") }
        static var previewOrganizationsSubtitle: String { text("profile.preview.organizations", "Перевірені організації та ініціативи.") }
        static var previewGuideSubtitle: String { text("profile.preview.guide", "Практичний довідник для життя в Австрії.") }
        static var statRegistrations: String { text("profile.stat.registrations", "Реєстрації") }
        static var statLiked: String { text("profile.stat.liked", "Вподобано") }
        static var statOrganizations: String { text("profile.stat.organizations", "Організації") }
        static var statSaved: String { text("profile.stat.saved", "Збережене") }
        static var notAvailableValue: String { text("profile.stat.not_available", "—") }
        static var loadingStatValue: String { text("profile.stat.loading", "…") }
        static var myEvents: String { text("profile.my_events", "Мої події") }
        static var myEventsSubtitle: String { text("profile.my_events.subtitle", "Реєстрації, найближчі події та історія участі.") }
        static var quickActionSavedSubtitle: String { text("profile.quick_action.saved.subtitle", "Новини, події та довідник.") }
        static var quickActionRegisteredEventsSubtitle: String { text("profile.quick_action.registered_events.subtitle", "Зареєстровані події") }
        static var quickActionSavedContentSubtitle: String { text("profile.quick_action.saved_content.subtitle", "Новини, події та організації") }
        static var quickActionSubscriptionsSubtitle: String { text("profile.quick_action.subscriptions.subtitle", "Організації, за якими ви стежите.") }
        static var quickActionActivitySubtitle: String { text("profile.quick_action.activity.subtitle", "Ваші дії у застосунку.") }
        static var quickActionNotificationsSubtitle: String { text("profile.quick_action.notifications.subtitle", "Важливі оновлення спільноти.") }
        static var organizationRoleDashboardSubtitle: String { text("profile.organization_roles.dashboard.subtitle", "Організації, де ви маєте роль у команді керування.") }
        static var organizationEditOrganization: String { text("profile.organization_roles.edit_organization", "Редагувати організацію") }
        static var organizationEditInfo: String { text("profile.organization_roles.edit_info", "Редагувати інформацію") }
        static var organizationCreateEvent: String { text("profile.organization_roles.create_event", "Створити подію") }
        static var organizationCreateNews: String { text("profile.organization_roles.create_news", "Створити новину") }
        static var organizationTeamRoles: String { text("profile.organization_roles.team_roles", "Команда та ролі") }
        static var organizationTeamRolesSubtitle: String { text("profile.organization_roles.team_roles.subtitle", "Адміністратори, модератори та доступ команди.") }
        static var organizationModeration: String { text("profile.organization_roles.moderation", "Модерація") }
        static var organizationModerationScopedSubtitle: String { text("profile.organization_roles.moderation.subtitle", "Черга перевірки саме для цієї організації.") }
        static var organizationRequestsMessages: String { text("profile.organization_roles.requests_messages", "Заявки / повідомлення") }
        static var organizationRequestsMessagesSubtitle: String { text("profile.organization_roles.requests_messages.subtitle", "Звернення, заявки та майбутні inbox flows.") }
        static var organizationAnalytics: String { text("profile.organization_roles.analytics", "Аналітика") }
        static var organizationSettings: String { text("profile.organization_roles.settings", "Налаштування організації") }
        static var organizationSettingsSubtitle: String { text("profile.organization_roles.settings.subtitle", "Критичні параметри будуть доступні окремим flow.") }
        static var organizationScopedFutureSubtitle: String { text("profile.organization_roles.scoped_future.subtitle", "Scoped organization flow буде додано пізніше.") }
        static var organizationEventReview: String { text("profile.organization_roles.event_review", "Перевірка подій") }
        static var organizationNewsReview: String { text("profile.organization_roles.news_review", "Перевірка новин") }
        static var activityTitle: String { text("profile.activity.title", "Моя активність") }
        static var registeredEvents: String { text("profile.activity.registered_events", "Зареєстровані події") }
        static var likedNews: String { text("profile.activity.liked_news", "Вподобані новини") }
        static var likedNewsSubtitle: String { text("profile.activity.liked_news.subtitle", "Матеріали, які ви позначили як важливі.") }
        static var likedEvents: String { text("profile.activity.liked_events", "Вподобані події") }
        static var likedEventsSubtitle: String { text("profile.activity.liked_events.subtitle", "Події, до яких хочеться повернутися.") }
        static var recentlyViewed: String { text("profile.activity.recently_viewed", "Нещодавно переглянуте") }
        static var recentlyViewedSubtitle: String { text("profile.activity.recently_viewed.subtitle", "Останні відкриті новини, події та довідник.") }
        static var recentlyViewedIntro: String { text("profile.activity.recently_viewed.intro", "Останні матеріали, які ви відкривали.") }
        static var recentlyViewedEmptyTitle: String { text("profile.activity.recently_viewed.empty_title", "Тут поки немає переглянутих матеріалів.") }
        static var recentlyViewedEmptyMessage: String { text("profile.activity.recently_viewed.empty_message", "Відкривайте новини, події та організації, щоб швидко повертатися до них.") }
        static var activityHistoryIntro: String { text("profile.activity_history.intro", "Ваші останні дії у застосунку.") }
        static var activityHistoryEmptyTitle: String { text("profile.activity_history.empty_title", "Історія активності поки порожня.") }
        static var activityHistoryEmptyMessage: String { text("profile.activity_history.empty_message", "Тут з’являтимуться ваші реєстрації, підписки та збереження.") }
        static var activityHistorySavedFilter: String { text("profile.activity_history.filter.saved", "Збережене") }
        static var upcomingRegistrations: String { text("profile.upcoming_registrations", "Найближчі реєстрації") }
        static var recentEvents: String { text("profile.recent_events", "Останні події") }
        static var viewAll: String { text("profile.view_all", "Переглянути все") }
        static var emptyBioStatus: String { text("profile.bio.empty_status", "Додайте інформацію про себе.") }
        static var visitHistory: String { text("profile.visit_history", "Історія відвідувань") }
        static var visitHistorySubtitle: String { text("profile.visit_history.subtitle", "Минулі події та участь з’являться тут.") }
        static var organizationSubscriptions: String { text("profile.organization_subscriptions", "Підписки") }
        static var organizationSubscriptionsSubtitle: String { text("profile.organization_subscriptions.subtitle", "Оновлення від організацій, за якими ви стежите.") }
        static var organizationMemberships: String { text("profile.organization_memberships", "Участь") }
        static var communitySection: String { text("profile.community.section", "Спільнота") }
        static var communitySectionSubtitle: String { text("profile.community.section_subtitle", "Організації, участь та майбутні можливості спільноти.") }
        static var participationRequests: String { text("profile.community.participation_requests", "Заявки / участь") }
        static var communityBadges: String { text("profile.community.badges", "Значки спільноти") }
        static var savedContent: String { text("profile.saved_content", "Збережене") }
        static var savedContentSubtitle: String { text("profile.saved_content.subtitle", "Новини, події та довідкові матеріали, до яких ви повернетеся пізніше.") }
        static var savedNews: String { text("profile.saved.news", "Збережені новини") }
        static var savedNewsSubtitle: String { text("profile.saved.news.subtitle", "Підбірка новин буде доступна після запуску збережень.") }
        static var savedEvents: String { text("profile.saved.events", "Збережені події") }
        static var savedEventsSubtitle: String { text("profile.saved.events.subtitle", "Події для швидкого повернення з’являться тут.") }
        static var savedGuides: String { text("profile.saved.guides", "Збережений довідник") }
        static var savedGuidesSubtitle: String { text("profile.saved.guides.subtitle", "Корисні статті та категорії будуть доступні тут.") }
        static var organizationEventActionSubtitle: String { text("profile.organization.event_action.subtitle", "Опублікувати подію від імені організації.") }
        static var organizationNewsActionSubtitle: String { text("profile.organization.news_action.subtitle", "Опублікувати новину від імені організації.") }
        static var organizationMembers: String { text("profile.organization.members", "Керування учасниками") }
        static var organizationMembersSubtitle: String { text("profile.organization.members.subtitle", "Ролі, запити та доступ команди.") }
        static var organizationModerationQueue: String { text("profile.organization.moderation_queue", "Черга модерації") }
        static var organizationModerationSubtitle: String { text("profile.organization.moderation.subtitle", "Матеріали організації, які очікують перевірки.") }
        static var platformDashboard: String { text("profile.platform_dashboard", "Адміністрування платформи") }
        static var platformDashboardSubtitle: String { text("profile.platform_dashboard.subtitle", "Користувачі, контент, модерація та системні модулі відповідно до вашого доступу.") }
        static var platformUsers: String { text("profile.platform.users", "Користувачі") }
        static var platformUsersSubtitle: String { text("profile.platform.users.subtitle", "Ролі, блокування та стан акаунтів.") }
        static var platformOrganizations: String { text("profile.platform.organizations", "Організації") }
        static var platformOrganizationsSubtitle: String { text("profile.platform.organizations.subtitle", "Погодження, керування та передача власності.") }
        static var platformEvents: String { text("profile.platform.events", "Події") }
        static var platformEventsSubtitle: String { text("profile.platform.events.subtitle", "Керування всіма подіями платформи.") }
        static var platformNews: String { text("profile.platform.news", "Новини") }
        static var platformNewsSubtitle: String { text("profile.platform.news.subtitle", "Керування новинами та редакційними матеріалами.") }
        static var platformGuide: String { text("profile.platform.guide", "Довідник") }
        static var platformGuideSubtitle: String { text("profile.platform.guide.subtitle", "Статті, категорії та регіональні матеріали.") }
        static var platformModeration: String { text("profile.platform.moderation", "Модерація") }
        static var platformModerationSubtitle: String { text("profile.platform.moderation.subtitle", "Pending review, reports and rejected content.") }
        static var platformFeedbackQueue: String { text("profile.platform.feedback_queue", "Підтримка / feedback") }
        static var platformFeedbackSubtitle: String { text("profile.platform.feedback.subtitle", "Черга звернень користувачів.") }
        static var platformConfiguration: String { text("profile.platform.configuration", "Платформа") }
        static var platformConfigurationSubtitle: String { text("profile.platform.configuration.subtitle", "Банери, категорії, регіони та app configuration.") }
        static var platformAuditLog: String { text("profile.platform.audit_log", "Журнал дій") }
        static var platformAuditLogSubtitle: String { text("profile.platform.audit_log.subtitle", "Історія модерації та admin actions.") }
        static var platformStatUsers: String { text("profile.platform.stat.users", "Users") }
        static var platformStatOrganizations: String { text("profile.platform.stat.organizations", "Organizations") }
        static var platformStatEvents: String { text("profile.platform.stat.events", "Events") }
        static var platformStatQueue: String { text("profile.platform.stat.queue", "Queue") }
        static var platformOwnerBadge: String { text("profile.owner.badge", "Власник платформи") }
        static var platformAdminBadge: String { text("profile.admin.badge", "Адміністратор") }
        static var platformModeratorBadge: String { text("profile.moderator.badge", "Модератор") }
        static var guideEditorBadge: String { text("profile.guide_editor.badge", "Guide Editor") }
        static var ownerHeroStatus: String { text("profile.owner.hero_status", "Повний доступ до керування застосунком.") }
        static var adminHeroStatus: String { text("profile.admin.hero_status", "Операційне керування контентом, організаціями та модерацією.") }
        static var moderatorHeroStatus: String { text("profile.moderator.hero_status", "Фокус на перевірці матеріалів і роботі зі скаргами.") }
        static var guideEditorHeroStatus: String { text("profile.guide_editor.hero_status", "Доступ до керування довідником і матеріалами Guide.") }
        static var ownerFullAccess: String { text("profile.owner.full_access", "Повний доступ") }
        static var adminOperationalAccess: String { text("profile.admin.operational_access", "Операційний доступ") }
        static var moderatorContentAccess: String { text("profile.moderator.content_access", "Модерація контенту") }
        static var guideEditorAccess: String { text("profile.guide_editor.access", "Керування довідником") }
        static var ownerCreateNews: String { text("profile.owner.quick.create_news", "Створити новину") }
        static var ownerCreateNewsSubtitle: String { text("profile.owner.quick.create_news.subtitle", "Редакційний центр новин.") }
        static var ownerCreateEvent: String { text("profile.owner.quick.create_event", "Створити подію") }
        static var ownerCreateEventSubtitle: String { text("profile.owner.quick.create_event.subtitle", "Керування подіями платформи.") }
        static var ownerCreateOrganization: String { text("profile.owner.quick.create_organization", "Створити організацію") }
        static var ownerCreateOrganizationSubtitle: String { text("profile.owner.quick.create_organization.subtitle", "Організації та власники.") }
        static var ownerOpenModeration: String { text("profile.owner.quick.open_moderation", "Відкрити модерацію") }
        static var ownerOpenModerationSubtitle: String { text("profile.owner.quick.open_moderation.subtitle", "Матеріали, що очікують перевірки.") }
        static var ownerSendPush: String { text("profile.owner.quick.send_push", "Надіслати push") }
        static var ownerAddGuideArticle: String { text("profile.owner.quick.add_guide_article", "Додати статтю в довідник") }
        static var ownerPlatformManagement: String { text("profile.owner.platform_management", "Керування платформою") }
        static var ownerPlatformManagementSubtitle: String { text("profile.owner.platform_management.subtitle", "Основні модулі керування контентом і доступом.") }
        static var adminPlatformManagement: String { text("profile.admin.platform_management", "Операційне керування") }
        static var adminPlatformManagementSubtitle: String { text("profile.admin.platform_management.subtitle", "Контент, організації, довідник і частина user management.") }
        static var adminAssistanceSubtitle: String { text("profile.admin.assistance.subtitle", "Заявки організацій, модерація, feedback/reports і довідник лише за окремою роллю.") }
        static var guideEditorManagement: String { text("profile.guide_editor.management", "Керування довідником") }
        static var guideEditorManagementSubtitle: String { text("profile.guide_editor.management.subtitle", "Створення, редагування, перевірка здоровʼя та звіти Guide.") }
        static var ownerUsers: String { text("profile.owner.users", "Користувачі") }
        static var ownerUsersSubtitle: String { text("profile.owner.users.subtitle", "Ролі, блокування, статус акаунтів.") }
        static var adminUsersSubtitle: String { text("profile.admin.users.subtitle", "Статуси акаунтів і базова модерація користувачів.") }
        static var ownerOrganizations: String { text("profile.owner.organizations", "Організації") }
        static var ownerOrganizationsSubtitle: String { text("profile.owner.organizations.subtitle", "Створення, редагування, власники, модерація.") }
        static var ownerNews: String { text("profile.owner.news", "Новини") }
        static var ownerNewsSubtitle: String { text("profile.owner.news.subtitle", "Публікація, редагування, видалення.") }
        static var ownerEvents: String { text("profile.owner.events", "Події") }
        static var ownerEventsSubtitle: String { text("profile.owner.events.subtitle", "Створення, редагування, реєстрації.") }
        static var ownerGuide: String { text("profile.owner.guide", "Довідник") }
        static var ownerGuideSubtitle: String { text("profile.owner.guide.subtitle", "Категорії, статті, корисна інформація.") }
        static var ownerModeration: String { text("profile.owner.moderation", "Модерація") }
        static var ownerModerationSubtitle: String { text("profile.owner.moderation.subtitle", "Перевірка матеріалів і майбутня робота зі скаргами.") }
        static var ownerPendingReview: String { text("profile.owner.pending_review", "Очікують перевірки") }
        static var ownerPendingReviewSubtitle: String { text("profile.owner.pending_review.subtitle", "Новини, події та організації на перевірці.") }
        static var ownerUserReports: String { text("profile.owner.user_reports", "Скарги користувачів") }
        static var ownerUserReportsSubtitle: String { text("profile.owner.user_reports.subtitle", "Майбутній центр user reports.") }
        static var ownerComments: String { text("profile.owner.comments", "Коментарі") }
        static var ownerCommentsSubtitle: String { text("profile.owner.comments.subtitle", "Модерація коментарів буде додана пізніше.") }
        static var ownerRejectedContent: String { text("profile.owner.rejected_content", "Заблокований контент") }
        static var ownerRejectedContentSubtitle: String { text("profile.owner.rejected_content.subtitle", "Відхилені та архівні матеріали.") }
        static var ownerAccessRoles: String { text("profile.owner.access_roles", "Доступ і ролі") }
        static var ownerAccessRolesSubtitle: String { text("profile.owner.access_roles.subtitle", "Адміністратори, модератори та перевірка прав.") }
        static var ownerManageUsers: String { text("profile.owner.manage_users", "Керування користувачами") }
        static var ownerManageUsersSubtitle: String { text("profile.owner.manage_users.subtitle", "Акаунти, статуси та блокування.") }
        static var ownerAssignAdmin: String { text("profile.owner.assign_admin", "Призначити адміністратора") }
        static var ownerAssignAdminSubtitle: String { text("profile.owner.assign_admin.subtitle", "Окремий flow буде додано пізніше.") }
        static var ownerAssignModerator: String { text("profile.owner.assign_moderator", "Призначити модератора") }
        static var ownerAssignModeratorSubtitle: String { text("profile.owner.assign_moderator.subtitle", "Розподіл модерації по секціях.") }
        static var ownerCheckPermissions: String { text("profile.owner.check_permissions", "Перевірити права доступу") }
        static var ownerCheckPermissionsSubtitle: String { text("profile.owner.check_permissions.subtitle", "Валідація ролей і доступу.") }
        static var ownerBlockedUsers: String { text("profile.owner.blocked_users", "Заблоковані користувачі") }
        static var ownerBlockedUsersSubtitle: String { text("profile.owner.blocked_users.subtitle", "Окремий список блокувань буде доступний пізніше.") }
        static var ownerOrganizationTools: String { text("profile.owner.organization_tools", "Організації") }
        static var ownerOrganizationToolsSubtitle: String { text("profile.owner.organization_tools.subtitle", "Власники, заявки, верифікація та архів.") }
        static var ownerOrganizationRequests: String { text("profile.owner.organization_requests", "Заявки на організації") }
        static var ownerOrganizationOwnerAssignment: String { text("profile.owner.organization_owner_assignment", "Призначення власника організації") }
        static var ownerOrganizationsWithoutOwner: String { text("profile.owner.organizations_without_owner", "Організації без власника") }
        static var ownerVerifiedOrganizations: String { text("profile.owner.verified_organizations", "Верифіковані організації") }
        static var ownerOrganizationArchive: String { text("profile.owner.organization_archive", "Архів організацій") }
        static var ownerContentControl: String { text("profile.owner.content_control", "Контент") }
        static var ownerContentControlSubtitle: String { text("profile.owner.content_control.subtitle", "Банери, рекомендації, категорії та регіони.") }
        static var ownerFeaturedNews: String { text("profile.owner.featured_news", "Рекомендовані новини") }
        static var ownerFeaturedEvents: String { text("profile.owner.featured_events", "Рекомендовані події") }
        static var ownerFeaturedOrganizations: String { text("profile.owner.featured_organizations", "Рекомендовані організації") }
        static var adminContentControlSubtitle: String { text("profile.admin.content_control.subtitle", "Операційні рекомендації та банери без critical platform configuration.") }
        static var ownerCategories: String { text("profile.owner.categories", "Категорії") }
        static var ownerRegions: String { text("profile.owner.regions", "Регіони / федеральні землі") }
        static var ownerContentLanguages: String { text("profile.owner.content_languages", "Мови контенту") }
        static var ownerUserSupport: String { text("profile.owner.user_support", "Підтримка користувачів") }
        static var ownerUserSupportSubtitle: String { text("profile.owner.user_support.subtitle", "Відгуки, проблеми та FAQ.") }
        static var ownerUserFeedback: String { text("profile.owner.user_feedback", "Відгуки користувачів") }
        static var ownerProblemReports: String { text("profile.owner.problem_reports", "Повідомлення про проблеми") }
        static var ownerHelpRequests: String { text("profile.owner.help_requests", "Запити на допомогу") }
        static var ownerFAQ: String { text("profile.owner.faq", "FAQ / часті питання") }
        static var ownerAppSettings: String { text("profile.owner.app_settings", "Налаштування застосунку") }
        static var ownerAppSettingsSubtitle: String { text("profile.owner.app_settings.subtitle", "Правові документи, правила модерації та базові platform policies.") }
        static var ownerDefaultLanguage: String { text("profile.owner.default_language", "Мова за замовчуванням") }
        static var ownerAvailableRegions: String { text("profile.owner.available_regions", "Доступні регіони") }
        static var ownerEventCategories: String { text("profile.owner.event_categories", "Категорії подій") }
        static var ownerOrganizationCategories: String { text("profile.owner.organization_categories", "Категорії організацій") }
        static var ownerModerationRules: String { text("profile.owner.moderation_rules", "Правила модерації") }
        static var ownerPrivacyPlatformRules: String { text("profile.owner.privacy_platform_rules", "Приватність і правила платформи") }
        static var ownerPrivacyPlatformRulesSubtitle: String { text("profile.owner.privacy_platform_rules.subtitle", "Політики приватності та правила використання платформи.") }
        static var ownerLegalDocuments: String { text("profile.owner.legal_documents", "Правові документи") }
        static var ownerLegalDocumentsSubtitle: String { text("profile.owner.legal_documents.subtitle", "Умови користування та політика конфіденційності.") }
        static var ownerAnalytics: String { text("profile.owner.analytics", "Аналітика") }
        static var ownerAnalyticsSubtitle: String { text("profile.owner.analytics.subtitle", "Аналітичні модулі без fake numbers, поки backend не готовий.") }
        static var ownerAnalyticsAdvancedSubtitle: String { text("profile.owner.analytics.advanced_subtitle", "Активні користувачі, події, організації, регіони та retention.") }
        static var ownerActiveUsers: String { text("profile.owner.analytics.active_users", "Активні користувачі") }
        static var ownerPopularEvents: String { text("profile.owner.analytics.popular_events", "Популярні події") }
        static var ownerOrganizationActivity: String { text("profile.owner.analytics.organization_activity", "Активність організацій") }
        static var ownerRegionalStats: String { text("profile.owner.analytics.regional_stats", "Регіональна статистика") }
        static var ownerRetention: String { text("profile.owner.analytics.retention", "Утримання користувачів") }
        static var ownerAdvancedSystems: String { text("profile.owner.advanced_systems", "Розширені системи платформи") }
        static var ownerAdvancedSystemsSubtitle: String { text("profile.owner.advanced_systems.subtitle", "Аналітика, журнал дій, безпека, інтеграції та backup systems.") }
        static var ownerAuditSecurity: String { text("profile.owner.audit_security", "Безпека і журнал дій") }
        static var ownerAuditSecuritySubtitle: String { text("profile.owner.audit_security.subtitle", "Audit, moderation history та security modules.") }
        static var ownerAuditLogs: String { text("profile.owner.audit_logs", "Журнал дій") }
        static var ownerAuditLogsSubtitle: String { text("profile.owner.audit_logs.subtitle", "Admin actions, moderation history, role changes та deleted materials.") }
        static var ownerSecurityCenter: String { text("profile.owner.security_center", "Центр безпеки") }
        static var ownerSecurityCenterSubtitle: String { text("profile.owner.security_center.subtitle", "Безпека акаунтів, доступу та platform safeguards.") }
        static var ownerIntegrationsAPI: String { text("profile.owner.integrations_api", "Integrations/API") }
        static var ownerIntegrationsAPISubtitle: String { text("profile.owner.integrations_api.subtitle", "Майбутні інтеграції та API-доступ платформи.") }
        static var ownerBackupSystems: String { text("profile.owner.backup_systems", "Backup systems") }
        static var ownerBackupSystemsSubtitle: String { text("profile.owner.backup_systems.subtitle", "Backup, restore та operational safety modules.") }
        static var moderatorModerationQueue: String { text("profile.moderator.moderation_queue", "Черга модерації") }
        static var moderatorReviewQueues: String { text("profile.moderator.review_queues", "Review queues") }
        static var moderatorReviewQueuesSubtitle: String { text("profile.moderator.review_queues.subtitle", "Матеріали, які можуть потребувати перевірки за вашими секціями.") }
        static var moderatorNewsReviewSubtitle: String { text("profile.moderator.news_review.subtitle", "Перевірка новин і редакційних матеріалів.") }
        static var moderatorEventsReviewSubtitle: String { text("profile.moderator.events_review.subtitle", "Перевірка подій і пов’язаного контенту.") }
        static var moderatorOrganizationsReviewSubtitle: String { text("profile.moderator.organizations_review.subtitle", "Перевірка організацій і профілів спільнот.") }
        static var ownerAdminActionLog: String { text("profile.owner.admin_action_log", "Журнал дій адміністраторів") }
        static var ownerModerationHistory: String { text("profile.owner.moderation_history", "Історія модерації") }
        static var ownerRoleChanges: String { text("profile.owner.role_changes", "Зміни ролей") }
        static var ownerDeletedMaterials: String { text("profile.owner.deleted_materials", "Видалені матеріали") }
        static var ownerPersonalSettings: String { text("profile.owner.personal_settings", "Особисті налаштування") }
        static var ownerPersonalSettingsSubtitle: String { text("profile.owner.personal_settings.subtitle", "Профіль власника, мова, тема та особисті сповіщення.") }
        static var notificationSettings: String { text("profile.notifications.settings", "Сповіщення") }
        static var notificationSettingsSubtitle: String { text("profile.notifications.settings.subtitle", "Отримуйте відповіді та важливі оновлення у вхідних сповіщеннях застосунку.") }
        static var notificationsSectionSubtitle: String { text("profile.notifications.section_subtitle", "Отримуйте відповіді та важливі оновлення у вхідних сповіщеннях застосунку.") }
        static var notificationsEnabled: String {
            String(localized: "profile.notifications.enabled", defaultValue: "Внутрішні сповіщення", bundle: .main, locale: LocalizationStore.locale)
        }
        static var notificationsEnabledSubtitle: String {
            String(localized: "profile.notifications.enabled.subtitle", defaultValue: "Отримуйте відповіді та важливі оновлення у вхідних сповіщеннях застосунку.", bundle: .main, locale: LocalizationStore.locale)
        }
        static var eventRemindersEnabled: String {
            String(localized: "profile.notifications.event_reminders.enabled", defaultValue: "Нагадування про події", bundle: .main, locale: LocalizationStore.locale)
        }
        static var eventRemindersEnabledSubtitle: String {
            String(localized: "profile.notifications.event_reminders.enabled.subtitle", defaultValue: "Надсилати нагадування перед зареєстрованими подіями.", bundle: .main, locale: LocalizationStore.locale)
        }
        static var reminderLeadTime: String {
            String(localized: "profile.notifications.reminder_lead_time", defaultValue: "Час нагадування", bundle: .main, locale: LocalizationStore.locale)
        }
        static var reminderLeadTimeSubtitle: String {
            String(localized: "profile.notifications.reminder_lead_time.subtitle", defaultValue: "Коли нагадувати перед початком події.", bundle: .main, locale: LocalizationStore.locale)
        }
        static var notificationPermissionDenied: String {
            String(localized: "profile.notifications.permission_denied", defaultValue: "Дозвіл на сповіщення не надано. Увімкніть його в налаштуваннях iOS.", bundle: .main, locale: LocalizationStore.locale)
        }
        static var notificationPreferencesLoadFailed: String {
            String(localized: "profile.notifications.load_failed", defaultValue: "Не вдалося завантажити налаштування сповіщень.", bundle: .main, locale: LocalizationStore.locale)
        }
        static var notificationPreferencesSaveFailed: String {
            String(localized: "profile.notifications.save_failed", defaultValue: "Не вдалося зберегти налаштування сповіщень.", bundle: .main, locale: LocalizationStore.locale)
        }
        static var notificationPreferencesSaved: String {
            String(localized: "profile.notifications.saved", defaultValue: "Налаштування сповіщень збережено.", bundle: .main, locale: LocalizationStore.locale)
        }
        static var notificationTestButton: String {
            String(localized: "profile.notifications.test_button", defaultValue: "Тестове сповіщення", bundle: .main, locale: LocalizationStore.locale)
        }
        static var notificationTestSent: String {
            String(localized: "profile.notifications.test_sent", defaultValue: "Тестове сповіщення буде показано за кілька секунд.", bundle: .main, locale: LocalizationStore.locale)
        }
        static var notificationTestFailed: String {
            String(localized: "profile.notifications.test_failed", defaultValue: "Не вдалося надіслати тестове сповіщення.", bundle: .main, locale: LocalizationStore.locale)
        }
        static var organizationNewsNotifications: String { text("profile.notifications.organization_news", "Новини від організацій") }
        static var organizationNewsNotificationsSubtitle: String { text("profile.notifications.organization_news.subtitle", "Оновлення від організацій, на які ви підписані.") }
        static var eventReminders: String { text("profile.notifications.event_reminders", "Нагадування про події") }
        static var eventRemindersSubtitle: String { text("profile.notifications.event_reminders.subtitle", "Нагадування перед зареєстрованими подіями.") }
        static var importantMessages: String { text("profile.notifications.important_messages", "Важливі повідомлення") }
        static var importantMessagesSubtitle: String { text("profile.notifications.important_messages.subtitle", "Системні та безпекові повідомлення платформи.") }
        static var settingsSection: String { text("profile.settings.section", "Налаштування") }
        static var mainInformation: String { text("profile.edit.main_information", "Основна інформація") }
        static var contactsSection: String { text("profile.edit.contacts", "Контакти") }
        static var preferencesSection: String { text("profile.edit.preferences", "Preferences") }
        static var appSettings: String { text("profile.edit.app_settings", "Налаштування застосунку") }
        static var appSettingsSubtitle: String { text("profile.edit.app_settings.subtitle", "Мова та вигляд застосунку.") }
        static var appLanguage: String { text("profile.settings.app_language", "Мова застосунку") }
        static var languageSettingsSubtitle: String { text("profile.settings.language.subtitle", "Мова інтерфейсу застосунку.") }
        static var appAppearance: String { text("profile.settings.app_appearance", "Тема оформлення") }
        static var appearanceSettingsSubtitle: String { text("profile.settings.appearance.subtitle", "Системна, світла або темна тема.") }
        static var regionSettings: String { text("profile.settings.region", "Регіон / федеральна земля") }
        static var regionSettingsSubtitle: String { text("profile.settings.region.subtitle", "Регіон використовується для локального контенту.") }
        static var privacySettingsSubtitle: String { text("profile.settings.privacy.subtitle", "Політика приватності та обробка даних.") }
        static var accountSecurity: String { text("profile.settings.account_security", "Безпека акаунта") }
        static var accountSecuritySubtitle: String { text("profile.settings.account_security.subtitle", "Додаткові параметри безпеки з’являться пізніше.") }
        static var deleteAccount: String { text("profile.settings.delete_account", "Видалити акаунт") }
        static var deleteAccountSubtitle: String { text("profile.settings.delete_account.subtitle", "Видалення акаунта та очищення особистих даних.") }
        static var deleteAccountConfirmTitle: String { text("profile.settings.delete_account.confirm_title", "Підтвердити видалення") }
        static var deleteAccountConfirmMessage: String { text("profile.settings.delete_account.confirm_message", "Акаунт буде видалено. Особисті дані профілю будуть очищені. Створений публічний контент може залишитись, щоб не ламати спільноту. Дію неможливо швидко скасувати.") }
        static var deleteAccountTypePrompt: String { text("profile.settings.delete_account.type_prompt", "Введіть ВИДАЛИТИ, щоб підтвердити.") }
        static var deleteAccountConfirmationKeyword: String { text("profile.settings.delete_account.keyword", "ВИДАЛИТИ") }
        static var deleteAccountFinalAction: String { text("profile.settings.delete_account.final_action", "Видалити акаунт") }
        static var deleteAccountInProgress: String { text("profile.settings.delete_account.in_progress", "Видаляємо акаунт…") }
        static var deleteAccountFailed: String { text("profile.settings.delete_account.failed", "Не вдалося видалити акаунт. Спробуйте ще раз.") }
        static var deleteAccountCleanupFailed: String { text("profile.settings.delete_account.cleanup_failed", "Не вдалося очистити дані акаунта. Акаунт не видалено. Спробуйте ще раз.") }
        static var deleteAccountPermissionFailed: String { text("profile.settings.delete_account.permission_failed", "Немає доступу для завершення видалення акаунта. Акаунт не видалено. Спробуйте вийти й увійти знову.") }
        static var deleteAccountRequiresRecentLogin: String { text("profile.settings.delete_account.requires_recent_login", "Для видалення акаунта потрібно повторно увійти.") }
        static var deleteAccountOrganizationOwnerBlocked: String { text("profile.settings.delete_account.owner_blocked", "Неможливо видалити акаунт, поки ви є власником організації. Передайте організацію іншому власнику.") }
        static var deleteAccountPlatformOwnerBlocked: String { text("profile.settings.delete_account.platform_owner_blocked", "Platform owner акаунт не можна видалити з профілю.") }
        static var deletedUserDisplayName: String { text("profile.deleted_user.display_name", "Видалений користувач") }
        static var supportSectionSubtitle: String { text("profile.support.subtitle", "Зв’язок з командою, довідка та юридична інформація.") }
        static var sendFeedback: String { text("profile.support.send_feedback", "Надіслати відгук") }
        static var sendFeedbackSubtitle: String { text("profile.support.send_feedback.subtitle", "Коротке повідомлення команді застосунку.") }
        static var reportProblem: String { text("profile.support.report_problem", "Повідомити про проблему") }
        static var reportProblemSubtitle: String { text("profile.support.report_problem.subtitle", "Технічні помилки та проблеми з контентом.") }
        static var helpFAQ: String { text("profile.support.help_faq", "Допомога / FAQ") }
        static var helpCenter: String { text("profile.help_center", "Допомога") }
        static var helpCenterSubtitle: String { text("profile.help_center.subtitle", "Питання, інструкції та підтримка користувачів.") }
        static var aboutApp: String { text("profile.about_app", "Про застосунок") }
        static var aboutAppSubtitle: String { text("profile.about_app.subtitle", "Версія, команда та інформація про платформу.") }
        static var futureModules: String { text("profile.future_modules", "Майбутні модулі") }
        static var futureModulesSubtitle: String { text("profile.future_modules.subtitle", "Видимі в структурі профілю, але ще не активні.") }
        static var userFutureModulesSubtitle: String { text("profile.future_modules.user_subtitle", "Особисті модулі вже закладені в профіль і відкриються пізніше.") }
        static var futureModuleSubtitle: String { text("profile.future_module.subtitle", "Незабаром.") }
        static var managedNewsTitle: String { text("profile.managed_news.title", "Керовані новини") }
        static var managedNewsSubtitle: String { text("profile.managed_news.subtitle", "Новини організацій, де у вас є права редагування.") }
        static var managedNewsEmptyTitle: String { text("profile.managed_news.empty_title", "Новин поки немає") }
        static var managedNewsEmptyMessage: String { text("profile.managed_news.empty_message", "Створіть першу новину в розділі Контент.") }
        static var managedEventsTitle: String { text("profile.managed_events.title", "Керовані події") }
        static var managedEventsSubtitle: String { text("profile.managed_events.subtitle", "Події організацій, де у вас є права редагування.") }
        static var managedEventsEmptyTitle: String { text("profile.managed_events.empty_title", "Подій поки немає") }
        static var managedEventsEmptyMessage: String { text("profile.managed_events.empty_message", "Створіть першу подію в розділі Контент.") }
        static var accountRequiredBadge: String { text("profile.account_required_badge", "Після входу") }
        static var volunteeringModule: String { text("profile.future.volunteering", "Волонтерство") }
        static var communityAchievementsModule: String { text("profile.future.community_achievements", "Досягнення спільноти") }
        static var activityHistoryModule: String { text("profile.future.activity_history", "Історія активності") }
        static var analyticsModule: String { text("profile.future.analytics", "Analytics") }
        static var notificationsCenterModule: String { text("profile.future.notifications_center", "Notifications center") }
        static var reportsModule: String { text("profile.future.reports", "Reports") }
        static var integrationsModule: String { text("profile.future.integrations", "Integrations/API") }
        static var systemHealthModule: String { text("profile.future.system_health", "System health") }
        static var securityModule: String { text("profile.future.security", "Backup/security center") }
        static var accessLocked: String { text("profile.access_locked", "Недоступно") }
        static var verifiedAccess: String { text("profile.verified_access", "Verified") }
        static var systemAccessLevel: String { text("profile.system_access_level", "System access") }
        static var communityOwner: String { text("profile.community_role.owner", "Власник") }
        static var communityAdmin: String { text("profile.community_role.admin", "Адміністратор") }
        static var communityModerator: String { text("profile.community_role.moderator", "Модератор") }
        static var communityMember: String { text("profile.community_role.member", "Учасник") }
        static var contentSectionTitle: String { text("profile.content.section_title", "Контент") }
        static var contentSectionSubtitle: String { text("profile.content.section_subtitle", "Створення й редагування новин та подій від імені ваших організацій.") }
        static var createNews: String { text("profile.content.create_news", "Створити новину") }
        static var createEvent: String { text("profile.content.create_event", "Створити подію") }
        static var volunteeringSubtitle: String { text("profile.future.volunteering.subtitle", "Можливість відгукуватися на потреби організацій.") }
        static var participationRequestsSubtitle: String { text("profile.community.participation_requests.subtitle", "Майбутні заявки на участь у спільноті.") }
        static var communityBadgesSubtitle: String { text("profile.community.badges.subtitle", "Досягнення та внесок у спільноту.") }
        static var notificationSettingsRowSubtitle: String { text("profile.notifications.settings.row_subtitle", "Внутрішні сповіщення в застосунку.") }
        static var termsOfUse: String { text("profile.terms_of_use", "Умови користування") }
        static var privacyPolicy: String { text("profile.privacy_policy", "Політика конфіденційності") }
        static var savedContentIntro: String { text("profile.saved_content.intro", "Новини, події та організації, які ви зберегли.") }
        static var savedEmptyAll: String { text("profile.saved.empty.all", "Тут з’являться збережені новини, події та організації.") }
        static var savedEmptyNews: String { text("profile.saved.empty.news", "Тут з’являться збережені новини.") }
        static var savedEmptyEvents: String { text("profile.saved.empty.events", "Тут з’являться збережені події.") }
        static var savedEmptyOrganizations: String { text("profile.saved.empty.organizations", "Тут з’являться збережені організації.") }
        static var subscriptionsIntro: String { text("profile.organization_subscriptions.intro", "Організації, на які ви підписані.") }
        static var subscriptionsEmpty: String { text("profile.organization_subscriptions.empty", "Ви ще не підписані на організації. Підписуйтесь, щоб швидко знаходити їхні новини та події.") }
        static var unknownUser: String { text("profile.unknown_user", "Невідомий користувач") }
        static var comingSoon: String { text("profile.status.soon", "Скоро") }
        static var myEventsUpcoming: String { text("profile.my_events.filter.upcoming", "Майбутні") }
        static var myEventsPast: String { text("profile.my_events.filter.past", "Минулі") }
        static var myEventsEmptyAllTitle: String { text("profile.my_events.empty.all.title", "У вас ще немає зареєстрованих подій.") }
        static var myEventsEmptyUpcomingTitle: String { text("profile.my_events.empty.upcoming.title", "У вас ще немає майбутніх подій.") }
        static var myEventsEmptyPastTitle: String { text("profile.my_events.empty.past.title", "Немає минулих подій.") }
        static var myEventsEmptyRegisterMessage: String { text("profile.my_events.empty.register_message", "Зареєструйтесь на події, щоб бачити їх тут.") }
        static var myEventsEmptyUpcomingMessage: String { text("profile.my_events.empty.upcoming.message", "Ваші майбутні реєстрації з’являться тут.") }
        static var myEventsEmptyPastMessage: String { text("profile.my_events.empty.past.message", "Після завершення події вона з’явиться в цьому розділі.") }
        static var myEventsIntro: String { text("profile.my_events.intro", "Ваші зареєстровані події в одному місці.") }
        static func manageableOrganizationsAvailable(_ count: Int) -> String {
            LocalizationStore.localizedFormat("profile.content.organizations_available", defaultValue: "%lld організацій доступно", arguments: [count])
        }
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
        static var myFeedbackTitle: String { text("feedback.my.title", "Мої звернення") }
        static var myFeedbackSubtitle: String { text("feedback.my.subtitle", "Ваші звернення та відповіді власника додатку.") }
        static var myFeedbackEmpty: String { text("feedback.my.empty", "У вас поки немає звернень.") }
        static var yourFeedback: String { text("feedback.your_feedback", "Ваше звернення") }
        static var ownerReply: String { text("feedback.owner_reply", "Відповідь власника") }
        static var sendReply: String { text("feedback.action.send_reply", "Надіслати відповідь") }
        static var closeFeedback: String { text("feedback.action.close", "Закрити звернення") }
        static var replySent: String { text("feedback.reply_sent", "Відповідь надіслано") }
        static var replyPlaceholder: String { text("feedback.reply.placeholder", "Напишіть відповідь користувачу") }
        static var replyRequired: String { text("feedback.validation.reply_required", "Введіть відповідь.") }
        static var replyTooLong: String { text("feedback.validation.reply_too_long", "Відповідь має бути до 2000 символів.") }
        static var messagesTitle: String { text("feedback.messages.title", "Повідомлення") }
        static var noMessages: String { text("feedback.messages.empty", "Немає повідомлень.") }
        static var addReply: String { text("feedback.reply.add", "Додати відповідь") }
        static var reply: String { text("feedback.reply", "Відповісти") }
        static var send: String { text("feedback.send", "Надіслати") }
        static var sending: String { text("feedback.sending", "Надсилання...") }
        static var sendMessageFailed: String { text("feedback.error.send_message_failed", "Не вдалося надіслати повідомлення.") }
        static var tryAgain: String { text("feedback.try_again", "Спробуйте ще раз") }
        static var closedMessage: String { text("feedback.closed.message", "Звернення закрито.") }
        static var closedSystemMessage: String { text("feedback.closed.system_message", "Звернення закрито") }
        static var userSender: String { text("feedback.sender.user", "Користувач") }
        static var ownerSender: String { text("feedback.sender.owner", "Підтримка") }
        static var supportLabel: String { text("feedback.sender.support", "Support") }
        static var typeQuestion: String { text("feedback.type.question", "Question") }
        static var typeSuggestion: String { text("feedback.type.suggestion", "Suggestion") }
        static var typeBug: String { text("feedback.type.bug", "Bug") }
        static var typeReport: String { text("feedback.type.report", "Report") }
        static var inboxTitle: String { text("feedback.inbox.title", "Відгуки користувачів") }
        static var inboxSubtitle: String { text("feedback.inbox.subtitle", "Повідомлення, пропозиції та проблеми від користувачів.") }
        static var inboxEmpty: String { text("feedback.inbox.empty", "Нових відгуків поки немає") }
        static var inboxFilter: String { text("feedback.inbox.filter", "Фільтр") }
        static var inboxFilterEmpty: String { text("feedback.inbox.filter_empty", "У цьому фільтрі звернень немає.") }
        static var filterOpen: String { text("feedback.filter.open", "Відкриті") }
        static var filterAnswered: String { text("feedback.filter.answered", "Відповіді надано") }
        static var filterClosed: String { text("feedback.filter.closed", "Закриті") }
        static var markReviewed: String { text("feedback.action.mark_reviewed", "Позначити переглянутим") }
        static var archive: String { text("feedback.action.archive", "Архівувати") }
        static var statusOpen: String { text("feedback.status.open", "Очікує відповіді") }
        static var statusWaitingReply: String { text("feedback.status.waiting_reply", "Очікує відповіді") }
        static var statusAnswered: String { text("feedback.status.answered", "Відповідь отримано") }
        static var statusClosed: String { text("feedback.status.closed", "Закрито") }
        static var statusReviewed: String { text("feedback.status.reviewed", "Переглянуто") }
        static var statusArchived: String { text("feedback.status.archived", "Архів") }
        static var loadFailed: String { text("feedback.error.load_failed", "Не вдалося завантажити відгуки.") }
        static var updateFailed: String { text("feedback.error.update_failed", "Не вдалося оновити статус відгуку.") }
    }

    enum Moderation {
        static var title: String { text("moderation.title", "Moderation Tools") }
        static var subtitle: String { text("moderation.subtitle", "Review pending community content before it becomes visible to everyone.") }
        static var empty: String { text("moderation.empty", "No pending items right now.") }
        static var retry: String { text("moderation.retry", "Retry") }
        static var approve: String { text("moderation.approve", "Approve") }
        static var reject: String { text("moderation.reject", "Reject") }
        static var confirmReject: String { text("moderation.confirm.reject", "Reject") }
        static var rejectConfirmationTitle: String { text("moderation.reject.confirm.title", "Reject content?") }
        static func rejectConfirmationMessage(_ title: String) -> String {
            LocalizationStore.localizedFormat("moderation.reject.confirm.message", defaultValue: "This will reject “%@” and remove it from the moderation queue.", arguments: [title])
        }
        static var approveOrganizationConfirmationTitle: String { text("moderation.organization.approve.confirm.title", "Approve organization?") }
        static var approveOrganizationConfirmationMessage: String { text("moderation.organization.approve.confirm.message", "This will publish the organization and notify the applicant.") }
        static var confirmApproveOrganization: String { text("moderation.organization.approve.confirm.action", "Approve organization") }
        static var rejectOrganizationConfirmationTitle: String { text("moderation.organization.reject.confirm.title", "Reject organization request?") }
        static var rejectOrganizationConfirmationMessage: String { text("moderation.organization.reject.confirm.message", "The applicant will receive the rejection reason you entered.") }
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
        static var organizationTitle: String { text("moderation.organization.title", "Модерація організації") }
        static var organizationEmpty: String { text("moderation.organization.empty", "Немає матеріалів організації на перевірці") }
        static var organizationRequest: String { text("moderation.organization.request", "Заявка організації") }
        static var organizationPreviewTitle: String { text("moderation.organization.preview.title", "Попередній перегляд організації") }
        static var organizationPreviewSubtitle: String { text("moderation.organization.preview.subtitle", "Так організація виглядатиме після публікації") }
        static var requestData: String { text("moderation.organization.request_data", "Дані заявки") }
        static var openRequest: String { text("moderation.organization.open_request", "Відкрити заявку") }
        static var submittedBy: String { text("moderation.organization.submitted_by", "Автор заявки") }
        static var approveOrganization: String { text("moderation.organization.approve_organization", "Схвалити організацію") }
        static var requestRevision: String { text("moderation.organization.request_revision", "Повернути на доопрацювання") }
        static var rejectRequest: String { text("moderation.organization.reject_request", "Відхилити заявку") }
        static var revisionMessage: String { text("moderation.organization.revision_message", "Повідомлення для автора") }
        static var rejectionReason: String { text("moderation.organization.rejection_reason", "Причина відхилення") }
        static var requestMainInformation: String { text("moderation.organization.section.main_information", "Основна інформація") }
        static var requestDescription: String { text("moderation.organization.section.description", "Опис") }
        static var requestContacts: String { text("moderation.organization.section.contacts", "Контакти") }
        static var requestApplicant: String { text("moderation.organization.section.applicant", "Заявник") }
        static var requestAbout: String { text("moderation.organization.section.about", "Про організацію") }
        static var requestActivities: String { text("moderation.organization.section.activities", "Чим ми займаємось") }
        static var supportCard: String { text("moderation.organization.support_card", "Підтримати організацію") }
        static var supportCardSubtitle: String { text("moderation.organization.support_card.subtitle", "Donation/support link буде показано після публікації.") }
        static var eventsHeld: String { text("moderation.organization.metrics.events_held", "Проведено подій") }
        static var volunteers: String { text("moderation.organization.metrics.volunteers", "Волонтери") }
        static var helpedPeople: String { text("moderation.organization.metrics.helped_people", "Людей отримали допомогу") }
        static var shortDescription: String { text("moderation.organization.short_description", "Короткий опис") }
        static var fullDescription: String { text("moderation.organization.full_description", "Повний опис") }
        static var federalState: String { text("moderation.organization.federal_state", "Федеральна земля") }
        static var austriaScope: String { text("moderation.organization.region_scope.austria", "Австрія") }
        static var regionScope: String { text("moderation.organization.region_scope", "Охоплення") }
        static var socialLinks: String { text("moderation.organization.social_links", "Соцмережі") }
        static var submittedAt: String { text("moderation.organization.submitted_at", "Надіслано") }
        static var submittedByUserId: String { text("moderation.organization.submitted_by_user_id", "UID заявника") }
    }

    enum UserManagement {
        static var title: String { text("user_management.title", "Користувачі") }
        static var subtitle: String { text("user_management.subtitle", "Пошук, статуси та ролі користувачів.") }
        static var viewUsers: String { text("user_management.view_users", "View users") }
        static var blockUser: String { text("user_management.block_user", "Block user") }
        static var assignModerator: String { text("user_management.assign_moderator", "Assign moderator") }
        static var assignAdmin: String { text("user_management.assign_admin", "Assign admin") }
        static var retry: String { text("user_management.retry", "Retry") }
        static var empty: String { text("user_management.empty", "No roles backfill issues found.") }
        static var permission: String { text("user_management.permission", "У вас немає доступу до керування користувачами.") }
        static var loadError: String { text("user_management.load_error", "Не вдалося завантажити користувачів.") }
        static var searchPlaceholder: String { text("user_management.search.placeholder", "Пошук за імʼям, email, Telegram або UID") }
        static var organizationSearchPlaceholder: String { text("user_management.organization_search.placeholder", "Пошук організації") }
        static var contentSubtitle: String { text("user_management.content.subtitle", "Пошук, статуси, блокування та ролі користувачів в організаціях.") }
        static var registeredUsers: String { text("user_management.registered_users", "зареєстрованих користувачів") }
        static var noResultsTitle: String { text("user_management.no_results.title", "Нічого не знайдено") }
        static var noResultsMessage: String { text("user_management.no_results.message", "Змініть пошук або фільтр, щоб побачити користувачів.") }
        static var organizationsNotLoaded: String { text("user_management.organizations.not_loaded", "Організації ще не завантажені.") }
        static var organizationsNotFound: String { text("user_management.organizations.not_found", "Організацій за цим пошуком не знайдено.") }
        static var organizationPicker: String { text("user_management.organization_picker", "Організація") }
        static var rolePicker: String { text("user_management.role_picker", "Роль") }
        static var reasonPlaceholder: String { text("user_management.reason.placeholder", "Причина / note") }
        static var assignRoleButton: String { text("user_management.assign_role.button", "Призначити роль") }
        static var changeOwnerButton: String { text("user_management.change_owner.button", "Змінити власника") }
        static var assignRoleSectionTitle: String { text("user_management.assign_role.section_title", "Призначити роль") }
        static var assignRoleSectionSubtitle: String { text("user_management.assign_role.section_subtitle", "Owner платформи може призначити роль тільки в конкретній організації.") }
        static var platformRolesTitle: String { text("user_management.platform_roles.title", "Ролі платформи") }
        static var platformRolesSubtitle: String { text("user_management.platform_roles.subtitle", "App Admin, App Moderator і Guide Editor не повʼязані з ролями в організаціях.") }
        static var currentPlatformRole: String { text("user_management.platform_roles.current_role", "Поточна роль") }
        static var guideEditorRole: String { text("user_management.platform_roles.guide_editor", "Guide Editor") }
        static var guideEditorEnabled: String { text("user_management.platform_roles.guide_editor.enabled", "Так") }
        static var guideEditorDisabled: String { text("user_management.platform_roles.guide_editor.disabled", "Ні") }
        static var assignAppAdmin: String { text("user_management.platform_roles.assign_app_admin", "Призначити App Admin") }
        static var removeAppAdmin: String { text("user_management.platform_roles.remove_app_admin", "Зняти App Admin") }
        static var assignAppModerator: String { text("user_management.platform_roles.assign_app_moderator", "Призначити App Moderator") }
        static var removeAppModerator: String { text("user_management.platform_roles.remove_app_moderator", "Зняти App Moderator") }
        static var assignGuideEditor: String { text("user_management.platform_roles.assign_guide_editor", "Призначити Guide Editor") }
        static var removeGuideEditor: String { text("user_management.platform_roles.remove_guide_editor", "Зняти Guide Editor") }
        static var platformRoleActionFallbackTitle: String { text("user_management.platform_roles.action_title", "Зміна ролі платформи") }
        static var platformRoleAuditNotice: String { text("user_management.platform_roles.audit_notice", "Зміна ролі буде виконана через Cloud Function і записана в audit log. За потреби вкажіть причину в полі нижче перед підтвердженням.") }
        static var platformRolePermissionDenied: String { text("user_management.platform_roles.permission_denied", "Недостатньо прав для зміни ролі платформи.") }
        static var platformRoleTargetOwnerProtected: String { text("user_management.platform_roles.error.target_owner_protected", "App Owner захищений: змінити цю роль тут не можна.") }
        static var platformRoleSelfChangeRejected: String { text("user_management.platform_roles.error.self_change_rejected", "Власну роль не можна змінити в цьому екрані.") }
        static var platformRoleTargetAccountNotUsable: String { text("user_management.platform_roles.error.target_account_not_usable", "Роль можна надати лише користувачу з активним або попередженим акаунтом.") }
        static var platformRoleNoOp: String { text("user_management.platform_roles.error.no_op", "Ця зміна ролі вже застосована.") }
        static var platformRoleTargetMissing: String { text("user_management.platform_roles.error.target_missing", "Користувача для зміни ролі не знайдено.") }
        static var ownerRoleImmutableNotice: String { text("user_management.platform_roles.owner_immutable", "App Owner не змінюється в цьому екрані.") }
        static var selfRoleChangeNotice: String { text("user_management.platform_roles.self_change_blocked", "Власну роль не можна змінити тут.") }
        static var statusPermissionDenied: String { text("user_management.status.permission_denied", "Недостатньо прав для зміни статусу користувача.") }
        static var rolePermissionDenied: String { text("user_management.role.permission_denied", "Недостатньо прав для призначення ролі.") }
        static var removeRolePermissionDenied: String { text("user_management.role.remove_permission_denied", "Недостатньо прав для зняття ролі.") }
        static var ownerChangePermissionDenied: String { text("user_management.owner_change.permission_denied", "Змінити власника може лише owner платформи.") }
        static var ownerChangeSelectNewOwner: String { text("user_management.owner_change.select_new_owner", "Оберіть нового власника організації.") }
        static var changesSaved: String { text("user_management.changes_saved", "Зміни збережено.") }
        static var changesFailed: String { text("user_management.changes_failed", "Не вдалося зберегти зміни.") }
        static var ownerTransferOnly: String { text("user_management.owner_transfer_only", "Поточний власник може бути замінений лише через transfer owner: призначте власником іншого користувача в цій організації.") }
        static var actionFallbackTitle: String { text("user_management.action.fallback_title", "Дія") }
        static var actionAuditNotice: String { text("user_management.action.audit_notice", "Дія буде записана в audit log. За потреби вкажіть причину в полі нижче перед підтвердженням.") }
        static var removeOrganizationRoleTitle: String { text("user_management.role.remove_title", "Зняти роль в організації?") }
        static var removeOrganizationRoleButton: String { text("user_management.role.remove_button", "Зняти роль") }
        static var removeOwnerRoleWarning: String { text("user_management.role.remove_owner_warning", "Роль owner не знімається напряму, щоб не залишити організацію без власника.") }
        static var cityRegion: String { text("user_management.city_region", "Місто / регіон") }
        static var organizationRolesTitle: String { text("user_management.organization_roles.title", "Ролі в організаціях") }
        static var organizationRolesSubtitle: String { text("user_management.organization_roles.subtitle", "Організаційні ролі керують доступом до створення та модерації контенту.") }
        static var organizationRolesEmpty: String { text("user_management.organization_roles.empty", "Ролей в організаціях немає.") }
        static var blockedUntil: String { text("user_management.blocked_until", "Блокування до") }
        static var auditHistoryTitle: String { text("user_management.audit_history.title", "Історія дій") }
        static var auditHistorySubtitle: String { text("user_management.audit_history.subtitle", "Попередження, блокування, деактивації та зміни ролей.") }
        static var auditHistoryEmpty: String { text("user_management.audit_history.empty", "Історії дій поки немає.") }
        static var accountActionsTitle: String { text("user_management.account_actions.title", "Дії з акаунтом") }
        static var accountActionsSubtitle: String { text("user_management.account_actions.subtitle", "Фізичне видалення користувача не виконується. Деактивація зберігає авторство старого контенту.") }
        static var filterAll: String { text("user_management.filter.all", "Усі") }
        static var filterActive: String { text("user_management.filter.active", "Активні") }
        static var filterWarned: String { text("user_management.filter.warned", "Попередження") }
        static var filterSuspended: String { text("user_management.filter.suspended", "Тимчасово заблоковані") }
        static var filterBanned: String { text("user_management.filter.banned", "Заблоковані") }
        static var filterOrganizationOwners: String { text("user_management.filter.organization_owners", "Власники організацій") }
        static var filterOrganizationAdmins: String { text("user_management.filter.organization_admins", "Адміни організацій") }
        static var filterOrganizationModerators: String { text("user_management.filter.organization_moderators", "Модератори організацій") }
        static var actionWarn: String { text("user_management.action.warn", "Видати попередження") }
        static var actionSuspend: String { text("user_management.action.suspend", "Тимчасово заблокувати") }
        static var actionBan: String { text("user_management.action.ban", "Заблокувати назавжди") }
        static var actionUnblock: String { text("user_management.action.unblock", "Зняти блокування") }
        static var actionDeactivate: String { text("user_management.action.deactivate", "Деактивувати користувача") }
        static var organizationOwnerRole: String { text("user_management.organization_role.owner", "Власник організації") }
        static var organizationAdminRole: String { text("user_management.organization_role.admin", "Адмін організації") }
        static var organizationModeratorRole: String { text("user_management.organization_role.moderator", "Модератор організації") }
        static func organizationRolesAdditionalCount(_ count: Int) -> String {
            LocalizationStore.localizedFormat("user_management.organization_roles.additional_count", defaultValue: "%lld орг.", arguments: [count])
        }
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

    enum ActivityLog {
        static var registeredForEvent: String { text("activity_log.registered_for_event", "Зареєструвався на подію") }
        static var canceledEventRegistration: String { text("activity_log.canceled_event_registration", "Скасував реєстрацію на подію") }
        static var followedOrganization: String { text("activity_log.followed_organization", "Підписався на організацію") }
        static var unfollowedOrganization: String { text("activity_log.unfollowed_organization", "Відписався від організації") }
        static var savedNews: String { text("activity_log.saved_news", "Зберіг новину") }
        static var unsavedNews: String { text("activity_log.unsaved_news", "Прибрав новину зі збереженого") }
        static var savedEvent: String { text("activity_log.saved_event", "Зберіг подію") }
        static var unsavedEvent: String { text("activity_log.unsaved_event", "Прибрав подію зі збереженого") }
        static var savedOrganization: String { text("activity_log.saved_organization", "Зберіг організацію") }
        static var unsavedOrganization: String { text("activity_log.unsaved_organization", "Прибрав організацію зі збереженого") }
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

    enum LegalCompliance {
        static var title: String { text("legal_compliance.title", "Updated legal documents") }
        static var message: String { text("legal_compliance.message", "Please review and accept the updated Terms or Privacy Policy to continue using your registered account.") }
        static var readDocument: String { text("legal_compliance.read_document", "Read document") }
        static var readDocumentSubtitle: String { text("legal_compliance.read_document.subtitle", "Review the current active version before accepting.") }
        static var acceptAll: String { text("legal_compliance.accept_all", "Accept required documents") }
        static var accepting: String { text("legal_compliance.accepting", "Accepting…") }
        static var decline: String { text("legal_compliance.decline", "Decline and sign out") }
        static var declineConfirmTitle: String { text("legal_compliance.decline.confirm.title", "Decline updated terms?") }
        static var declineConfirmMessage: String { text("legal_compliance.decline.confirm.message", "Without accepting the updated terms, you cannot use your registered account. You will be signed out and returned to guest mode.") }
        static var declineConfirmAction: String { text("legal_compliance.decline.confirm.action", "Sign out") }
        static var loadFailed: String { text("legal_compliance.error.load_failed", "Unable to check the current legal documents right now.") }
        static var acceptFailed: String { text("legal_compliance.error.accept_failed", "Unable to save your acceptance. Check your connection and try again.") }
    }

    enum LegalManagement {
        static var title: String { text("legal_management.title", "Legal Documents") }
        static var subtitle: String { text("legal_management.subtitle", "Manage active Terms and Privacy documents, drafts, and required reacceptance.") }
        static var permissionTitle: String { text("legal_management.permission.title", "Owner access required") }
        static var permissionMessage: String { text("legal_management.permission.message", "Only the App Owner can manage legal documents.") }
        static var loadFailed: String { text("legal_management.error.load_failed", "Unable to load legal documents.") }
        static var termsSubtitle: String { text("legal_management.terms.subtitle", "Terms of Service shown to registered users.") }
        static var privacySubtitle: String { text("legal_management.privacy.subtitle", "Privacy Policy shown to registered users.") }
        static var requiresAcceptance: String { text("legal_management.requires_acceptance", "Requires acceptance") }
        static var acceptanceNotRequired: String { text("legal_management.acceptance_not_required", "Acceptance not required") }
        static var draftExists: String { text("legal_management.draft_exists", "Draft exists") }
        static var createDraft: String { text("legal_management.create_draft", "Create draft") }
        static var editDraft: String { text("legal_management.edit_draft", "Edit draft") }
        static var editorSubtitle: String { text("legal_management.editor.subtitle", "Edit localized Markdown and publish a new immutable version.") }
        static func editorTitle(_ documentTitle: String) -> String {
            LocalizationStore.localizedFormat(
                "legal_management.editor.title",
                defaultValue: "Edit %@",
                arguments: [documentTitle]
            )
        }
        static var editorIntro: String { text("legal_management.editor.intro", "Draft changes are private until published. Publishing updates the active version for all users.") }
        static var versionSection: String { text("legal_management.version.section", "Version and acceptance") }
        static var versionSectionSubtitle: String { text("legal_management.version.section.subtitle", "Publishing this draft creates the next active legal version.") }
        static var changeSummary: String { text("legal_management.change_summary", "Change summary") }
        static var localizedContent: String { text("legal_management.localized_content", "Localized content") }
        static var localizedContentSubtitle: String { text("legal_management.localized_content.subtitle", "Edit the title and Markdown body for each supported language.") }
        static var localePicker: String { text("legal_management.locale_picker", "Language") }
        static var localizedTitle: String { text("legal_management.localized_title", "Localized title") }
        static var saveDraft: String { text("legal_management.save_draft", "Save draft") }
        static var saving: String { text("legal_management.saving", "Saving…") }
        static var draftSaved: String { text("legal_management.draft_saved", "Draft saved.") }
        static var saveFailed: String { text("legal_management.error.save_failed", "Unable to save draft.") }
        static var preview: String { text("legal_management.preview", "Preview") }
        static var publish: String { text("legal_management.publish", "Publish new version") }
        static var publishing: String { text("legal_management.publishing", "Publishing…") }
        static var publishFailed: String { text("legal_management.error.publish_failed", "Unable to publish legal document.") }
        static var missingGermanTitle: String { text("legal_management.validation.missing_german_title", "Missing German title") }
        static var missingGermanContent: String { text("legal_management.validation.missing_german_content", "Missing German content") }
        static var missingUkrainianTitle: String { text("legal_management.validation.missing_ukrainian_title", "Missing Ukrainian title") }
        static var missingUkrainianContent: String { text("legal_management.validation.missing_ukrainian_content", "Missing Ukrainian content") }
        static var publishConfirmTitle: String { text("legal_management.publish.confirm.title", "Publish new legal version?") }
        static var publishConfirmMessage: String { text("legal_management.publish.confirm.message", "This version becomes immutable and replaces the active document. If acceptance is required, users with older accepted versions will need to accept again.") }
    }

    enum Roles {
        static var user: String { text("role.user", "User") }
        static var moderator: String { text("role.moderator", "Moderator") }
        static var admin: String { text("role.admin", "Admin") }
        static var owner: String { text("role.owner", "Owner") }
        static var topAdmin: String { text("role.top_admin", "Top Admin") }
        static var appModerator: String { text("role.app_moderator", "App Moderator") }
    }

    enum Dialogs {
        static var errorTitle: String {
            String(
                localized: "dialogs.error.title",
                defaultValue: "Something went wrong",
                bundle: .main,
                locale: LocalizationStore.locale
            )
        }

        static var successTitle: String {
            String(
                localized: "dialogs.success.title",
                defaultValue: "Done",
                bundle: .main,
                locale: LocalizationStore.locale
            )
        }
    }

    enum Common {
        static var app: String { text("common.app", "App") }
        static var ok: String { text("common.ok", "OK") }
        static var done: String { text("common.done", "Готово") }
        static var cancel: String { text("common.cancel", "Cancel") }
        static var back: String { text("common.back", "Back") }
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
        static var warned: String { text("common.warned", "Попередження") }
        static var temporarilyBlocked: String { text("common.temporarily_blocked", "Тимчасово заблоковано") }
        static var deactivated: String { text("common.deactivated", "Деактивовано") }
        static var draft: String { text("common.draft", "Draft") }
        static var pendingReview: String { text("common.pending_review", "Очікує підтвердження") }
        static var needsRevision: String { text("common.needs_revision", "Потребує доопрацювання") }
        static var approved: String { text("common.approved", "Approved") }
        static var rejected: String { text("common.rejected", "Відхилено") }
        static var archived: String { text("common.archived", "Archived") }
        static var noItems: String { text("common.no_items", "No items available.") }
        static var notAvailable: String { text("common.not_available", "Not available") }
        static var viewAll: String { text("common.view_all", "Дивитися всі") }
        static var commentsPlaceholder: String { text("common.comments_placeholder", "Comments UI will be expanded in a later phase.") }
        static var noCommentsYet: String { text("common.comments.empty", "Ще немає коментарів.") }
        static var commentInputPlaceholder: String { text("common.comments.input_placeholder", "Напишіть коментар…") }
        static var signInToComment: String { text("common.comments.sign_in", "Увійдіть, щоб коментувати") }
        static var deleteCommentConfirmation: String { text("common.comments.delete_confirmation", "Видалити цей коментар?") }
        static var deleteCommentFailed: String { text("common.comments.delete_failed", "Не вдалося видалити коментар") }
        static var legalPlaceholder: String { text("common.placeholder.legal", "Placeholder") }
        static var uploadImageTitle: String { text("common.upload_image.title", "Add image") }
        static var uploadImageHelper: String { text("common.upload_image.helper", "JPG, PNG up to 10 MB. Recommended 16:9") }
        static var communityMemberFallback: String { text("common.community_member_fallback", "Учасник спільноти") }
    }

    enum Action {
        static var create: String { text("action.create", "Create") }
        static var edit: String { text("action.edit", "Edit") }
        static var open: String { text("action.open", "Відкрити") }
        static var retry: String { text("action.retry", "Спробувати ще раз") }
        static var delete: String { text("action.delete", "Delete") }
        static var cancel: String { text("action.cancel", "Cancel") }
        static var share: String { text("action.share", "Share") }
        static var save: String { text("action.save", "Save") }
        static var like: String { text("action.like", "Like") }
        static var unlike: String { text("action.unlike", "Unlike") }
        static var comingSoon: String { text("action.coming_soon", "Coming soon") }
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
        static var guideTitleRequired: String { text("validation.guide.title_required", "Guide title is required.") }
        static var guideSummaryRequired: String { text("validation.guide.summary_required", "Guide summary is required.") }
        static var guideCategoryRequired: String { text("validation.guide.category_required", "Select a guide category.") }
        static var guideContentRequired: String { text("validation.guide.content_required", "Add at least one content block or body text.") }
        static var guideOfficialSourceRequired: String { text("validation.guide.official_source_required", "Add at least one official source.") }
        static var eventTitleRequired: String { text("validation.event.title_required", "Event title is required.") }
        static var eventDetailsTooShort: String { text("validation.event.details_too_short", "Event details are too short.") }
        static var eventCityRequired: String { text("validation.event.city_required", "Event city is required.") }
        static var eventVenueRequired: String { text("validation.event.venue_required", "Event venue is required.") }
        static var eventDateOrderInvalid: String { text("validation.event.date_order_invalid", "Event end date must be after the start date.") }
        static var organizationNameRequired: String { text("validation.organization.name_required", "Додайте назву спільноти.") }
        static var organizationDescriptionTooShort: String { text("validation.organization.description_too_short", "Додайте короткий опис щонайменше на 20 символів.") }
        static var organizationCityRequired: String { text("validation.organization.city_required", "Вкажіть місто спільноти.") }
        static var organizationRegionRequired: String { text("validation.organization.region_required", "Оберіть федеральну землю, де працює спільнота.") }
        static var organizationEmailInvalid: String { text("validation.organization.email_invalid", "Перевірте email для зв’язку.") }
        static var organizationWebsiteInvalid: String { text("validation.organization.website_invalid", "Додайте повне посилання, наприклад https://example.org.") }
        static var organizationFoundedYearInvalid: String { text("validation.organization.founded_year_invalid", "Вкажіть коректний рік заснування.") }
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
        static var loadUserProfileFailed: String { text("auth.load_user_profile.failed", "Failed to load user profile.") }
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

    static func profileNotificationReminderMinutes(_ count: Int) -> String {
        let format = String(
            localized: "profile.notifications.reminder.minutes",
            defaultValue: "%lld min",
            bundle: .main,
            locale: LocalizationStore.locale
        )
        return String(format: format, locale: LocalizationStore.locale, arguments: [count])
    }

    static func profileNotificationReminderDays(_ count: Int) -> String {
        let format = String(
            localized: "profile.notifications.reminder.days",
            defaultValue: "%lld day(s)",
            bundle: .main,
            locale: LocalizationStore.locale
        )
        return String(format: format, locale: LocalizationStore.locale, arguments: [count])
    }

    static func profileOrganizationsCount(_ count: Int) -> String {
        LocalizationStore.localizedFormat(
            "profile.organizations.count",
            defaultValue: "%lld memberships",
            arguments: [count]
        )
    }

    static func profileBioCounter(_ count: Int, _ limit: Int) -> String {
        LocalizationStore.localizedFormat(
            "profile.bio.counter",
            defaultValue: "%lld/%lld",
            arguments: [count, limit]
        )
    }

    static func profileOrganizationID(_ organizationID: String) -> String {
        LocalizationStore.localizedFormat(
            "profile.organization.id",
            defaultValue: "Organization %@",
            arguments: [organizationID]
        )
    }

    static func profileOrganizationRole(_ role: String) -> String {
        LocalizationStore.localizedFormat(
            "profile.organization.role",
            defaultValue: "Role: %@",
            arguments: [role]
        )
    }

    static func profileOrganizationScopedSubtitle(_ organizationID: String) -> String {
        LocalizationStore.localizedFormat(
            "profile.organization.scoped_subtitle",
            defaultValue: "Scoped to organization %@.",
            arguments: [organizationID]
        )
    }

    static func profileOrganizationTeamAssignConfirmation(userName: String, role: String) -> String {
        LocalizationStore.localizedFormat(
            "profile.organization.team.confirm.assign",
            defaultValue: "Призначити %@ як %@?",
            arguments: [userName, role]
        )
    }

    static func profileOrganizationTeamChangeOwnerConfirmation(_ userName: String) -> String {
        LocalizationStore.localizedFormat(
            "profile.organization.team.confirm.change_owner",
            defaultValue: "Змінити власника на %@?",
            arguments: [userName]
        )
    }

    static func profileOrganizationTeamRemoveConfirmation(role: String, userName: String) -> String {
        LocalizationStore.localizedFormat(
            "profile.organization.team.confirm.remove",
            defaultValue: "Зняти роль %@ для %@?",
            arguments: [role, userName]
        )
    }

    static func profileOrganizationTeamMakeRole(_ role: String) -> String {
        LocalizationStore.localizedFormat(
            "profile.organization.team.make_role",
            defaultValue: "Зробити %@",
            arguments: [role]
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

    enum SystemLogs {
        static var ownerTitle: String { text("system_logs.owner.title", "Журнал системи") }
        static var ownerSubtitle: String { text("system_logs.owner.subtitle", "Дії, помилки та технічна діагностика") }
        static var ownerProfileSubtitle: String { text("system_logs.owner.profile_subtitle", "Дії, помилки, безпека та модерація") }
        static var appAdminTitle: String { text("system_logs.app_admin.title", "Журнал модерації") }
        static var appAdminSubtitle: String { text("system_logs.app_admin.subtitle", "Помилки, модерація та організації") }
        static var all: String { text("system_logs.section.all", "Усі") }
        static var actions: String { text("system_logs.section.actions", "Дії") }
        static var errors: String { text("system_logs.section.errors", "Помилки") }
        static var security: String { text("system_logs.section.security", "Безпека") }
        static var moderation: String { text("system_logs.section.moderation", "Модерація") }
        static var organizations: String { text("system_logs.section.organizations", "Організації") }
        static var users: String { text("system_logs.section.users", "Користувачі") }
        static var unreviewed: String { text("system_logs.filter.unreviewed", "Непереглянуті") }
        static var critical: String { text("system_logs.filter.critical", "Критичні") }
        static var today: String { text("system_logs.filter.today", "Сьогодні") }
        static var sevenDays: String { text("system_logs.filter.seven_days", "7 днів") }
        static var sectionPickerLabel: String { text("system_logs.filter.section_picker", "Розділ журналу") }
        static var markReviewed: String { text("system_logs.action.mark_reviewed", "Позначити як переглянуте") }
        static var filteredEmptyTitle: String { text("system_logs.empty.filtered.title", "Немає записів за вибраними фільтрами") }
        static var reviewed: String { text("system_logs.reviewed", "Переглянуто") }
        static var notReviewed: String { text("system_logs.not_reviewed", "Не переглянуто") }
        static var notRecorded: String { text("system_logs.not_recorded", "Не записано") }
        static var unknown: String { text("system_logs.unknown", "Невідомо") }
        static var reviewedByCurrentUser: String { text("system_logs.reviewed_by.current_user", "Поточний адміністратор") }
        static var reviewedByAdmin: String { text("system_logs.reviewed_by.admin", "Адміністратор") }
        static var records: String { text("system_logs.records.title", "Записи") }
        static var recordsCountSuffix: String { text("system_logs.records.count_suffix", "записів") }
        static var loading: String { text("system_logs.loading", "Завантаження журналу") }
        static var clearSearch: String { text("system_logs.search.clear", "Очистити пошук") }
        static var searchPlaceholder: String { text("system_logs.search.placeholder", "Пошук у журналі") }
        static var emptyTitle: String { text("system_logs.empty.title", "Журнал поки порожній") }
        static var emptyMessage: String { text("system_logs.empty.message", "Події з’являться тут після підключення системного логування.") }
        static var filteredEmptyMessage: String { text("system_logs.empty.filtered.message", "Змініть пошук або фільтри, щоб побачити інші записи.") }
        static var detailTitle: String { text("system_logs.detail.title", "Деталі запису") }
        static var actorSection: String { text("system_logs.detail.section.actor", "Виконавець") }
        static var targetSection: String { text("system_logs.detail.section.target", "Ціль") }
        static var organizationSection: String { text("system_logs.detail.section.organization", "Організація") }
        static var classificationSection: String { text("system_logs.detail.section.classification", "Класифікація") }
        static var diagnosticsSection: String { text("system_logs.detail.section.diagnostics", "Діагностика") }
        static var deviceSection: String { text("system_logs.detail.section.device", "Застосунок і пристрій") }
        static var reviewSection: String { text("system_logs.detail.section.review", "Перегляд") }
        static var metadataSection: String { text("system_logs.detail.section.metadata", "Метадані") }
        static var tracingSection: String { text("system_logs.detail.section.tracing", "Трасування") }
        static var reviewStatusSection: String { text("system_logs.review_action.title", "Статус перегляду") }
        static var reviewInstruction: String { text("system_logs.review_action.message", "Позначте запис переглянутим після перевірки, що він не потребує додаткової дії.") }
        static var markingReviewed: String { text("system_logs.action.marking_reviewed", "Позначення") }
        static var nameLabel: String { text("system_logs.detail.label.name", "Ім’я") }
        static var roleLabel: String { text("system_logs.detail.label.role", "Роль") }
        static var typeLabel: String { text("system_logs.detail.label.type", "Тип") }
        static var titleLabel: String { text("system_logs.detail.label.title", "Назва") }
        static var categoryLabel: String { text("system_logs.detail.label.category", "Категорія") }
        static var severityLabel: String { text("system_logs.detail.label.severity", "Рівень") }
        static var eventLabel: String { text("system_logs.detail.label.event", "Подія") }
        static var outcomeLabel: String { text("system_logs.detail.label.outcome", "Результат") }
        static var retentionLabel: String { text("system_logs.detail.label.retention", "Зберігання") }
        static var errorCodeLabel: String { text("system_logs.detail.label.error_code", "Код помилки") }
        static var moduleLabel: String { text("system_logs.detail.label.module", "Модуль") }
        static var screenLabel: String { text("system_logs.detail.label.screen", "Екран") }
        static var operationLabel: String { text("system_logs.detail.label.operation", "Операція") }
        static var appVersionLabel: String { text("system_logs.detail.label.app_version", "Версія застосунку") }
        static var osVersionLabel: String { text("system_logs.detail.label.os_version", "Версія ОС") }
        static var deviceLabel: String { text("system_logs.detail.label.device", "Пристрій") }
        static var statusLabel: String { text("system_logs.detail.label.status", "Статус") }
        static var reviewedAtLabel: String { text("system_logs.detail.label.reviewed_at", "Переглянуто о") }
        static var reviewedByLabel: String { text("system_logs.detail.label.reviewed_by", "Переглянув") }
        static var createdAtLabel: String { text("system_logs.detail.label.created_at", "Створено") }
        static var correlationIdLabel: String { text("system_logs.detail.label.correlation_id", "ID зв’язку") }
        static var adminUnreviewedSubtitle: String { text("system_logs.metric.unreviewed.admin_subtitle", "Потребує уваги адміністратора") }
        static var ownerUnreviewedSubtitle: String { text("system_logs.metric.unreviewed.owner_subtitle", "Потребує уваги власника") }
        static var highestLevelSubtitle: String { text("system_logs.metric.critical.subtitle", "Найвищий рівень") }
        static var technicalDiagnosticsSubtitle: String { text("system_logs.metric.errors.subtitle", "Технічна діагностика") }
        static var adminAvailableSubtitle: String { text("system_logs.metric.moderation.subtitle", "Доступно адміністратору") }
        static var restrictedJournalSubtitle: String { text("system_logs.metric.security.subtitle", "Обмежений журнал") }
        static var ownerLoadPermissionError: String { text("system_logs.error.load.owner_permission", "Не вдалося завантажити журнал. Перевірте права доступу власника.") }
        static var adminLoadPermissionError: String { text("system_logs.error.load.admin_permission", "Не вдалося завантажити журнал модерації. Перевірте права доступу адміністратора.") }
        static var indexRequiredError: String { text("system_logs.error.load.index_required", "Для цього запиту журналу потрібен індекс Firestore. Перевірте налаштування індексів.") }
        static var networkLoadError: String { text("system_logs.error.load.network", "Журнал тимчасово недоступний. Перевірте з’єднання та спробуйте ще раз.") }
        static var genericLoadError: String { text("system_logs.error.load.generic", "Не вдалося завантажити журнал системи. Спробуйте оновити сторінку.") }
        static var missingReviewerError: String { text("system_logs.error.review.missing_reviewer", "Не вдалося визначити користувача для позначення перегляду.") }
        static var ownerReviewPermissionError: String { text("system_logs.error.review.owner_permission", "Не вдалося позначити запис переглянутим. Перевірте права власника.") }
        static var adminReviewPermissionError: String { text("system_logs.error.review.admin_permission", "Не вдалося позначити запис переглянутим. Перевірте права адміністратора.") }
        static var networkReviewError: String { text("system_logs.error.review.network", "Не вдалося зберегти статус перегляду. Перевірте з’єднання та спробуйте ще раз.") }
        static var genericReviewError: String { text("system_logs.error.review.generic", "Не вдалося позначити запис переглянутим. Спробуйте ще раз.") }
    }

    private static func text(_ key: String, _ defaultValue: String) -> String {
        LocalizationStore.localizedString(key, defaultValue: defaultValue)
    }
}
