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
        static var notifications: String { text("home.notifications", "Notifications") }
        static var changeBanner: String { text("home.banner.change", "Change banner image") }
        static var bannerUploadFailed: String { text("home.banner.upload_failed", "Unable to update the banner image.") }
    }

    enum News {
        static var title: String { text("news.title", "News") }
        static var detailTitle: String { text("news.detail.title", "Деталі новини") }
        static var detailBadge: String { text("news.detail.badge", "Новина") }
        static var summarySectionTitle: String { text("news.detail.summary_section", "Коротко") }
        static var bodySectionTitle: String { text("news.detail.body_section", "Про що йдеться") }
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
        static var tagsSectionTitle: String { text("news.editor.tags.title", "Теги (необов’язково)") }
        static var tagsPlaceholder: String { text("news.editor.tags.placeholder", "Додайте теги через кому") }
        static var tagsHelper: String { text("news.editor.tags.helper", "Наприклад: підтримка, освіта, інтеграція") }
        static var additionalSettingsTitle: String { text("news.editor.settings.title", "Додаткові налаштування") }
        static var regionSectionTitle: String { text("news.editor.region.title", "Регіон") }
        static var regionTitle: String { text("news.editor.region.field", "Bundesland") }
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
        static var detailOrganizerSectionTitle: String { text("events.detail.organizer", "Організатор") }
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
        static var editorOrganizerSectionTitle: String { text("events.editor.organizer_section", "Організатор *") }
        static var categorySectionTitle: String { text("events.editor.category_section", "Категорія *") }
        static var categoryTraining: String { text("events.editor.category.training", "Навчання") }
        static var additionalSettingsTitle: String { text("events.editor.settings", "Додаткові налаштування") }
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
        static var organizationRegionRequired: String { text("events.editor.validation.organization_region_required", "Перед публікацією заповніть регіон організації.") }
        static var deleteConfirmation: String { text("events.delete.confirmation", "Delete this event?") }
        static var delete: String { text("events.delete", "Delete") }
        static var cancel: String { text("events.cancel", "Cancel") }
        static var deleteFailed: String { text("events.delete_failed", "Delete Failed") }
        static var dismissError: String { text("events.dismiss_error", "OK") }
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
        static var editorTitle: String { text("organizations.editor.title", "Створити організацію") }
        static var editTitle: String { text("organizations.editor.edit_title", "Редагувати організацію") }
        static var editorSubtitle: String { text("organizations.editor.subtitle", "Заповніть інформацію про вашу організацію.") }
        static var fieldName: String { text("organizations.editor.field.name", "Назва організації *") }
        static var fieldNamePlaceholder: String { text("organizations.editor.field.name_placeholder", "Введіть назву організації") }
        static var fieldDescription: String { text("organizations.editor.field.description", "Короткий опис") }
        static var fieldDescriptionPlaceholder: String { text("organizations.editor.field.description_placeholder", "Коротко опишіть діяльність організації") }
        static var fieldFullDescription: String { text("organizations.editor.field.full_description", "Повний опис організації") }
        static var fieldFullDescriptionPlaceholder: String { text("organizations.editor.field.full_description_placeholder", "Розкажіть більше про організацію, місію та цілі") }
        static var fieldContactEmail: String { text("organizations.editor.field.contact_email", "Контактний email") }
        static var fieldWebsite: String { text("organizations.editor.field.website", "Вебсайт") }
        static var fieldTelegramURL: String { text("organizations.editor.field.telegram_url", "Telegram канал або чат") }
        static var fieldDonationURL: String { text("organizations.editor.field.donation_url", "Посилання на донат") }
        static var fieldMissionStatement: String { text("organizations.editor.field.mission_statement", "Місія") }
        static var fieldMissionStatementPlaceholder: String { text("organizations.editor.field.mission_statement_placeholder", "Коротко опишіть місію організації") }
        static var fieldContactPerson: String { text("organizations.editor.field.contact_person", "Контактна особа (необов’язково)") }
        static var fieldContactPersonDisplay: String { text("organizations.detail.contact_person", "Контактна особа") }
        static var fieldRegion: String { text("organizations.editor.field.region", "Bundesland *") }
        static var fieldRegionPlaceholder: String { text("organizations.editor.field.region_placeholder", "Оберіть регіон") }
        static var fieldCity: String { text("organizations.editor.field.city", "Місто") }
        static var fieldAddress: String { text("organizations.editor.field.address", "Адреса") }
        static var fieldFoundedYear: String { text("organizations.editor.field.founded_year", "Рік заснування") }
        static var fieldLanguages: String { text("organizations.editor.field.languages", "Мови спілкування") }
        static var publish: String { text("organizations.editor.publish", "Створити організацію") }
        static var saveChanges: String { text("organizations.editor.save_changes", "Зберегти") }
        static var publishing: String { text("organizations.editor.publishing", "Зберігаємо...") }
        static var publishedSuccessfully: String { text("organizations.editor.success", "Organization published successfully.") }
        static var updatedSuccessfully: String { text("organizations.editor.updated_success", "Organization updated successfully.") }
        static var imageSectionTitle: String { text("organizations.editor.image_section", "Логотип організації") }
        static var logoUploadTitle: String { text("organizations.editor.logo_upload_title", "Додайте логотип") }
        static var logoUploadHelper: String { text("organizations.editor.logo_upload_helper", "JPG, PNG до 5 MB. Рекомендовано 1:1") }
        static var detailsSectionTitle: String { text("organizations.editor.details_section", "Основна інформація") }
        static var categorySectionTitle: String { text("organizations.editor.category_section", "Категорія діяльності *") }
        static var categoryIntegration: String { text("organizations.editor.category.integration", "Інтеграція") }
        static var contactSectionTitle: String { text("organizations.editor.contact_section", "Контактна інформація") }
        static var phonePlaceholder: String { text("organizations.editor.phone_placeholder", "Номер телефону") }
        static var socialLinksTitle: String { text("organizations.editor.social_title", "Соціальні мережі") }
        static var socialPlaceholder: String { text("organizations.editor.social_placeholder", "Instagram, Facebook, TikTok...") }
        static var locationSectionTitle: String { text("organizations.editor.location_section", "Місцезнаходження") }
        static var locationPlaceholder: String { text("organizations.editor.location_placeholder", "Введіть адресу або назву міста") }
        static var chooseOnMap: String { text("organizations.editor.choose_on_map", "Вибрати на карті") }
        static var aboutSectionTitle: String { text("organizations.about_section", "Про організацію") }
        static var aboutEmptyMessage: String { text("organizations.detail.about_empty", "Повний опис організації поки не додано.") }
        static var mainInformationTitle: String { text("organizations.detail.main_information", "Основна інформація") }
        static var categoryTitle: String { text("organizations.detail.category", "Категорія") }
        static var languagesTitle: String { text("organizations.detail.languages", "Мови") }
        static var foundedTitle: String { text("organizations.detail.founded", "Засновано") }
        static var aboutPlaceholder: String { text("organizations.editor.about_placeholder", "Розкажіть більше про вашу організацію, місію та цілі") }
        static var settingsSectionTitle: String { text("organizations.editor.settings_section", "Додаткові налаштування") }
        static var futureSectionTitle: String { text("organizations.editor.future_section", "Майбутні можливості") }
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
        static var moderationNotice: String { text("organizations.editor.moderation_notice", "Після створення організація буде відправлена на модерацію. Ви зможете редагувати інформацію після публікації.") }
        static var follow: String { text("organizations.detail.follow", "Підписатися") }
        static var message: String { text("organizations.detail.message", "Повідомлення") }
        static var share: String { text("organizations.detail.share", "Поділитися") }
        static var support: String { text("organizations.detail.support", "Підтримати") }
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
        static var tabTeam: String { text("organizations.detail.tab_team", "Команда") }
        static var deleteConfirmation: String { text("organizations.delete.confirmation", "Delete this organization?") }
        static var delete: String { text("organizations.delete", "Delete") }
        static var cancel: String { text("organizations.cancel", "Cancel") }
        static var deleteFailed: String { text("organizations.delete_failed", "Delete Failed") }
        static var dismissError: String { text("organizations.dismiss_error", "OK") }
    }

    enum Info {
        static var title: String { text("info.title", "Guide") }
        static var subtitle: String { text("guide.subtitle", "Curated practical guidance, official references, and everyday orientation for families in Austria.") }
        static var heroTitle: String { text("guide.hero.title", "Довідник громади") }
        static var heroSubtitle: String { text("guide.hero.subtitle", "Практичні поради, документи та корисні контакти для життя в Австрії.") }
        static var pinnedTitle: String { text("guide.pinned", "Important Now") }
        static var categoriesTitle: String { text("guide.categories", "Categories") }
        static var popularCategoriesTitle: String { text("guide.categories.popular", "Популярні категорії") }
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
        static var organizationManagementIntro: String { text("profile.organization_management.intro", "Організації, якими ви керуєте або допомагаєте керувати.") }
        static var organizationRoleOwner: String { text("profile.organization.role.owner", "Власник") }
        static var organizationRoleAdmin: String { text("profile.organization.role.admin", "Адмін") }
        static var organizationRoleModerator: String { text("profile.organization.role.moderator", "Модератор") }
        static var organizationRolePlatformOwner: String { text("profile.organization.role.platform_owner", "Власник платформи") }
        static var organizationOpen: String { text("profile.organization.open", "Відкрити") }
        static var organizationManage: String { text("profile.organization.manage", "Керувати") }
        static var organizationStatEvents: String { text("profile.organization.stat.events", "події") }
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
        static var organizationTeamSearchPlaceholder: String { text("profile.organization.team.search_placeholder", "Пошук за іменем, email або nickname") }
        static var organizationTeamRolePicker: String { text("profile.organization.team.role_picker", "Роль") }
        static var organizationTeamNoUsers: String { text("profile.organization.team.no_users", "Користувачів не знайдено.") }
        static var organizationTeamMissingProfile: String { text("profile.organization.team.missing_profile", "Профіль не знайдено") }
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
        static var personalRegionSubtitle: String { text("profile.guest.personal_region.subtitle", "Локальні події та організації за вашим Bundesland.") }
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
        static var ownerHeroStatus: String { text("profile.owner.hero_status", "Повний доступ до керування застосунком.") }
        static var adminHeroStatus: String { text("profile.admin.hero_status", "Операційне керування контентом, організаціями та модерацією.") }
        static var moderatorHeroStatus: String { text("profile.moderator.hero_status", "Фокус на перевірці матеріалів і роботі зі скаргами.") }
        static var ownerFullAccess: String { text("profile.owner.full_access", "Повний доступ") }
        static var adminOperationalAccess: String { text("profile.admin.operational_access", "Операційний доступ") }
        static var moderatorContentAccess: String { text("profile.moderator.content_access", "Модерація контенту") }
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
        static var ownerHomeBanners: String { text("profile.owner.home_banners", "Банери головної сторінки") }
        static var ownerHomeBannersSubtitle: String { text("profile.owner.home_banners.subtitle", "Редагуються у відповідних розділах застосунку.") }
        static var ownerFeaturedNews: String { text("profile.owner.featured_news", "Рекомендовані новини") }
        static var ownerFeaturedEvents: String { text("profile.owner.featured_events", "Рекомендовані події") }
        static var ownerFeaturedOrganizations: String { text("profile.owner.featured_organizations", "Рекомендовані організації") }
        static var adminContentControlSubtitle: String { text("profile.admin.content_control.subtitle", "Операційні рекомендації та банери без critical platform configuration.") }
        static var ownerCategories: String { text("profile.owner.categories", "Категорії") }
        static var ownerRegions: String { text("profile.owner.regions", "Регіони / Bundesländer") }
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
        static var notificationSettingsSubtitle: String { text("profile.notifications.settings.subtitle", "Email, push та важливі оновлення.") }
        static var notificationsSectionSubtitle: String { text("profile.notifications.section_subtitle", "Майбутній центр push, email та важливих повідомлень.") }
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
        static var appLanguage: String { text("profile.settings.app_language", "Мова застосунку") }
        static var languageSettingsSubtitle: String { text("profile.settings.language.subtitle", "Мова інтерфейсу застосунку.") }
        static var appAppearance: String { text("profile.settings.app_appearance", "Тема оформлення") }
        static var appearanceSettingsSubtitle: String { text("profile.settings.appearance.subtitle", "Системна, світла або темна тема.") }
        static var regionSettings: String { text("profile.settings.region", "Регіон / Bundesland") }
        static var regionSettingsSubtitle: String { text("profile.settings.region.subtitle", "Регіон використовується для локального контенту.") }
        static var privacySettingsSubtitle: String { text("profile.settings.privacy.subtitle", "Політика приватності та обробка даних.") }
        static var accountSecurity: String { text("profile.settings.account_security", "Безпека акаунта") }
        static var accountSecuritySubtitle: String { text("profile.settings.account_security.subtitle", "Додаткові параметри безпеки з’являться пізніше.") }
        static var deleteAccount: String { text("profile.settings.delete_account", "Видалити акаунт") }
        static var deleteAccountSubtitle: String { text("profile.settings.delete_account.subtitle", "Backend flow для видалення акаунта ще не активний.") }
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
        static var inboxTitle: String { text("feedback.inbox.title", "Відгуки користувачів") }
        static var inboxSubtitle: String { text("feedback.inbox.subtitle", "Повідомлення, пропозиції та проблеми від користувачів.") }
        static var inboxEmpty: String { text("feedback.inbox.empty", "Нових відгуків поки немає") }
        static var markReviewed: String { text("feedback.action.mark_reviewed", "Позначити переглянутим") }
        static var archive: String { text("feedback.action.archive", "Архівувати") }
        static var statusOpen: String { text("feedback.status.open", "Новий") }
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
        static var statusPermissionDenied: String { text("user_management.status.permission_denied", "Недостатньо прав для зміни статусу користувача.") }
        static var rolePermissionDenied: String { text("user_management.role.permission_denied", "Недостатньо прав для призначення ролі.") }
        static var removeRolePermissionDenied: String { text("user_management.role.remove_permission_denied", "Недостатньо прав для зняття ролі.") }
        static var changesSaved: String { text("user_management.changes_saved", "Зміни збережено.") }
        static var changesFailed: String { text("user_management.changes_failed", "Не вдалося зберегти зміни.") }
        static var ownerTransferOnly: String { text("user_management.owner_transfer_only", "Поточний власник може бути замінений лише через transfer owner: призначте власником іншого користувача в цій організації.") }
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
        static var draft: String { text("common.draft", "Draft") }
        static var pendingReview: String { text("common.pending_review", "Pending review") }
        static var approved: String { text("common.approved", "Approved") }
        static var rejected: String { text("common.rejected", "Rejected") }
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
    }

    enum Action {
        static var create: String { text("action.create", "Create") }
        static var edit: String { text("action.edit", "Edit") }
        static var delete: String { text("action.delete", "Delete") }
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
        static var eventTitleRequired: String { text("validation.event.title_required", "Event title is required.") }
        static var eventDetailsTooShort: String { text("validation.event.details_too_short", "Event details are too short.") }
        static var eventCityRequired: String { text("validation.event.city_required", "Event city is required.") }
        static var eventVenueRequired: String { text("validation.event.venue_required", "Event venue is required.") }
        static var eventDateOrderInvalid: String { text("validation.event.date_order_invalid", "Event end date must be after the start date.") }
        static var organizationNameRequired: String { text("validation.organization.name_required", "Organization name is required.") }
        static var organizationDescriptionTooShort: String { text("validation.organization.description_too_short", "Organization description is too short.") }
        static var organizationCityRequired: String { text("validation.organization.city_required", "Organization city is required.") }
        static var organizationRegionRequired: String { text("validation.organization.region_required", "Organization region is required.") }
        static var organizationEmailInvalid: String { text("validation.organization.email_invalid", "Contact email must be valid.") }
        static var organizationWebsiteInvalid: String { text("validation.organization.website_invalid", "Website must start with http:// or https://.") }
        static var organizationFoundedYearInvalid: String { text("validation.organization.founded_year_invalid", "Founded year must be a valid year.") }
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

    private static func text(_ key: String, _ defaultValue: String) -> String {
        LocalizationStore.localizedString(key, defaultValue: defaultValue)
    }
}
