import Foundation

/// Explains the recorded evidence; it never infers an incident's root cause from timing alone.
enum SystemLogExplanation {
    static func operationAliases(matching query: String) -> [String] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let supportMatches = LocalSearchMatcher.matches(query: query, values: [ProjectSupportText.journalAction]) ? ["saveDonationConfig"] : []
        return supportMatches + defaults.keys.filter { $0.hasPrefix("action.") && LocalSearchMatcher.matches(query: query, values: [text($0)]) }
            .map { String($0.dropFirst("action.".count)) }.sorted()
    }

    nonisolated static func text(_ key: String) -> String {
        LocalizationStore.localizedString("system_logs.explanation." + key, defaultValue: defaults[key] ?? key)
    }

    nonisolated static func kind(_ log: SystemLogEntry) -> String {
        if log.operationName == "decodeOwnerBanner" { return "parsing" }
        return switch log.errorCode ?? "" {
        case "network.connectionLost": "connection"
        case "network.secureConnectionFailed", "network.certificateDateInvalid", "network.certificateUntrusted": "secure"
        case "network.dnsFailed": "dns"
        case "cloudFunctions.failedPrecondition", "cloudFunctions.9", "firestore.9": "precondition"
        case "network.notConnectedToInternet": "offline"
        case "network.timedOut", "firestore.deadlineExceeded", "cloudFunctions.deadlineExceeded": "timeout"
        case "firestore.permissionDenied", "cloudFunctions.permissionDenied", "storage.unauthorized", "app.permissionDenied": "permission"
        case "cloudFunctions.unauthenticated", "firestore.16": "auth"
        case "cloudFunctions.mfaRequired": "mfa"
        case "firestore.unavailable", "cloudFunctions.unavailable", "app.networkUnavailable": "unavailable"
        case "network.cancelled", "storage.cancelled": "cancelled"
        case "parsing.decodingFailed", "parsing.invalidBanner": "parsing"
        default: "unknown"
        }
    }

    nonisolated static func isFailure(_ log: SystemLogEntry) -> Bool {
        log.eventType == .technicalError || log.errorCode != nil || log.outcome == .failed
    }

    nonisolated static func title(_ log: SystemLogEntry) -> String {
        if log.errorCode == "configuration.conflict" { return ProjectSupportText.conflictTitle }
        if log.errorCode == "configuration.unconfirmed" { return ProjectSupportText.unconfirmedTitle }
        if log.operationName == "saveDonationConfig", !isFailure(log) { return ProjectSupportText.journalSaved }
        if isFailure(log), log.operationName == "decodeOwnerBanner" { return text("bannerDecode.title") }
        if isFailure(log), log.moduleName == "Analytics", log.operationName == "deliverAggregate" { return text("background.title") }
        return isFailure(log) ? text(kind(log) + ".title") : SystemLogDisplayFormatting.summaryTitle(log.summary)
    }

    nonisolated static func cause(_ log: SystemLogEntry) -> String {
        if log.errorCode == "configuration.conflict" { return ProjectSupportText.conflictCause }
        if log.errorCode == "configuration.unconfirmed" { return ProjectSupportText.unconfirmedCause }
        if log.operationName == "decodeOwnerBanner", log.metadata["invalidField"] != nil { return text("bannerDecode.cause") }
        if let reason = log.metadata["diagnosticReason"], defaults["reason." + reason] != nil { return text("reason." + reason) }
        return text(kind(log) + ".cause")
    }

    nonisolated static func nextStep(_ log: SystemLogEntry) -> String {
        if log.errorCode?.hasPrefix("configuration.") == true { return ProjectSupportText.journalNext }
        return switch kind(log) {
        case "connection", "offline", "timeout", "unavailable": text("network.next")
        case "permission": text("permission.next")
        case "auth": text("auth.next")
        case "mfa": text("mfa.next")
        default: text("unknown.next")
        }
    }

    nonisolated static func action(_ log: SystemLogEntry) -> String {
        if log.operationName == "saveDonationConfig" { return ProjectSupportText.journalAction }
        if let operation = log.operationName, defaults["action." + operation] != nil {
            return text("action." + operation)
        }
        if let operation = log.operationName, !operation.isEmpty {
            return text("action.technical") + " " + [log.moduleName, operation].compactMap { $0 }.joined(separator: ".")
        }
        return isFailure(log) ? text("action.unknown") : SystemLogDisplayFormatting.eventTypeTitle(log.eventType)
    }

    nonisolated static func impact(_ log: SystemLogEntry) -> String {
        if log.moduleName == "Analytics", log.operationName == "deliverAggregate" { return text("impact.analytics") }
        if log.operationName == "decodeOwnerBanner" { return text("impact.bannerDecode") }
        if log.moduleName == "Notifications", log.operationName == "listenNotifications" { return text("impact.notificationInbox") }
        if log.moduleName == "Notifications", log.operationName == "fetchUnreadCount" { return text("impact.notificationBadge") }
        if log.operationName == "listenOrganizationRequests" { return text("impact.organizationRequests") }
        if log.operationName == "deleteFeaturedBannerImage" { return text("impact.bannerImage") }
        if log.metadata["failureStage"] == "decodeResponse" { return text("impact.decodeResponse") }
        return text("impact.unconfirmed")
    }

    nonisolated static func contextValue(_ value: String?, prefix: String) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if prefix == "stage", value == "writeConfiguration" { return ProjectSupportText.writeStage }
        if prefix == "stage", value == "confirmConfiguration" { return ProjectSupportText.confirmStage }
        let key = prefix + "." + value
        return defaults[key] == nil ? value : text(key)
    }

    nonisolated private static let defaults: [String: String] = [
        "section": "Що сталося",
        "action": "Під час якої дії",
        "cause": "Що відомо про причину",
        "next": "Що перевірити",
        "technical": "Технічні подробиці",
        "unknown.title": "Дію не вдалося завершити",
        "unknown.cause": "Точну причину в цьому записі не встановлено. Технічний код сам по собі її не пояснює.",
        "unknown.next": "Скопіюйте подробиці запису для перевірки. Для з’ясування причини можуть знадобитися серверний журнал і повторення дії.",
        "connection.title": "З’єднання із сервером перервалося",
        "connection.cause": "Запис підтверджує розрив з’єднання під час запиту. Чому саме воно перервалося, не записано.",
        "network.next": "Перевірте з’єднання та оновіть дані. Якщо це була зміна або видалення, спочатку перевірте результат, щоб не повторити вже виконану дію.",
        "offline.title": "Немає доступу до інтернету",
        "offline.cause": "Пристрій повідомив про відсутність підключення до інтернету під час запиту.",
        "timeout.title": "Відповідь не надійшла вчасно",
        "timeout.cause": "Час очікування запиту минув. Це не підтверджує, що сервер не виконав дію; точну причину затримки не встановлено.",
        "permission.title": "Доступ до дії або даних відхилено",
        "permission.cause": "Перевірка доступу відхилила запит. Сам запис не визначає, чи змінилися права користувача, стан об’єкта або його доступність.",
        "permission.next": "Перевірте користувача, його поточні права та чи існує об’єкт. Зіставте час із видаленням або зміною об’єкта.",
        "auth.title": "Сервер не підтвердив сесію входу",
        "auth.cause": "Запит не мав прийнятного підтвердження входу. Причина втрати або відхилення сесії не записана.",
        "auth.next": "Перевірте стан входу користувача. За потреби увійдіть повторно.",
        "mfa.title": "Не завершено перевірку кодом автентифікатора",
        "mfa.cause": "Для привілейованого акаунта сервер вимагає сесію з підтвердженням TOTP.",
        "mfa.next": "Увійдіть повторно з кодом автентифікатора.",
        "unavailable.title": "Сервіс тимчасово недоступний",
        "unavailable.cause": "Запит не зміг отримати доступ до сервісу. Цей запис не відрізняє збій мережі від недоступності сервера.",
        "cancelled.title": "Запит скасовано",
        "cancelled.cause": "Операцію скасовано. Сам запис не вказує, чи це сталося через вихід з екрана, зміну сесії або іншу причину.",
        "parsing.title": "Не вдалося прочитати отримані дані",
        "parsing.cause": "Структура отриманих даних не відповідає формату, який очікував застосунок. Конкретне поле може бути не записане.",
        "action.unknown": "Дію не уточнено; технічна назва — у подробицях",
        "secure.title": "Не вдалося встановити захищене з’єднання",
        "secure.cause": "Перевірка захищеного з’єднання не пройшла. Цей запис сам по собі не доводить проблему сертифіката, VPN або мережі.",
        "dns.title": "Не вдалося знайти адресу сервера",
        "dns.cause": "Система не змогла визначити мережеву адресу сервера. Точну причину збою визначення адреси не записано.",
        "precondition.title": "Не виконано умову для цієї дії",
        "precondition.cause": "Сервер відхилив дію через невиконану умову. Яку саме — цей код не уточнює; потрібні додаткові дані сервера.",
        "action.getBlockedOrganizations": "Завантаження заблокованих організацій",
        "action.getBlockedUsers": "Завантаження заблокованих користувачів",
        "action.listenNewsComments": "Оновлення коментарів новини",
        "action.listenEventComments": "Оновлення коментарів події",
        "action.listenNotifications": "Оновлення списку сповіщень",
        "action.fetchNotifications": "Завантаження сповіщень",
        "action.fetchUnreadCount": "Підрахунок непрочитаних сповіщень",
        "action.deleteNotificationPushRegistration": "Відключення push-сповіщень пристрою",
        "action.deleteOwnAccount": "Видалення власного акаунта",
        "action.deleteOrganization": "Видалення організації",
        "action.deleteNews": "Видалення новини",
        "action.cancelEvent": "Скасування події",
        "action.deleteEvent": "Видалення події",
        "action.technical": "Операція:",
        "background.title": "Не надіслано фоновий сигнал аналітики",
        "impact": "Вплив на користувача",
        "impact.analytics": "Збій стосується передачі аналітики у фоновому режимі. Цей запис не означає, що публікація, звернення або інша основна дія користувача не виконалася.",
        "impact.bannerDecode": "Не вдалося прочитати налаштування цього банера. У керуванні показано запис для відновлення; це не невдала публікація користувача.",
        "impact.bannerImage": "Не вдалося видалити файл зображення банера. Це окрема операція очищення; стан самого банера перевіряється за його записом.",
        "impact.decodeResponse": "Сервер відповів, але застосунок не зміг прочитати відповідь. Дія на сервері могла виконатися; перед повторенням перевірте її результат.",
        "impact.unconfirmed": "Застосунок не отримав підтвердження завершення цієї операції. Запис помилки сам по собі не підтверджує результат зміни на сервері.",
        "reason.analyticsConsentRequired": "Сервер не визнав чинну згоду на необов’язкову аналітику. Потрібно перевірити серверну сумісність версії згоди та її синхронізацію.",
        "reason.legalAcknowledgementRequired": "На сервері не підтверджено прийняття актуальних правових документів для цього акаунта.",
        "reason.analyticsActionUnverified": "Сервер не знайшов належного підтвердження дії для аналітичного сигналу. Це не доводить, що сама дія користувача не виконалася.",
        "reason.mfaRequired": "Для цієї привілейованої операції не підтверджено вхід із другим фактором.",
        "reason.firebaseConfigurationMissing": "Застосунок не зміг визначити серверний проєкт для відправлення запиту.",
        "failureStage": "Етап збою",
        "analyticsEvent": "Тип аналітичного сигналу",
        "invalidField": "Проблемне поле",
        "validationRule": "Умова перевірки",
        "deliveryDisposition": "Обробка сигналу",
        "retryCount": "Попередні повторні спроби",
        "appBuild": "Білд застосунку",
        "stage.encodeRequest": "Підготовка запиту",
        "stage.invokeServer": "Виклик сервера",
        "stage.decodeResponse": "Читання відповіді сервера",
        "disposition.discarded": "Сигнал відкинуто як неприйнятний; повтор не заплановано",
        "disposition.retryScheduled": "Заплановано повторну спробу",
        "field.imageURL": "Зображення банера (imageURL)",
        "field.externalURL": "Посилання банера (externalURL)",
        "field.createdBy": "Автор запису (createdBy)",
        "field.localizations": "Мовні версії банера (localizations)",
        "rule.missingOrInvalidType": "Поле відсутнє або має неправильний тип",
        "rule.invalidHTTPURL": "Потрібне коректне HTTP/HTTPS-посилання",
        "rule.required": "Обов’язкове поле порожнє",
        "rule.outOfRange": "Значення поза дозволеним діапазоном",
        "rule.lengthExceeded": "Перевищено допустиму довжину",
        "rule.invalidDateOrder": "Завершення має бути пізніше початку",
        "rule.invalidLocalizedFields": "Неправильна структура мовних версій",
        "rule.invalidType": "Неправильний тип даних",
        "rule.empty": "Потрібно вибрати хоча б один розділ",
        "rule.unsupported": "Непідтримуване значення",
        "rule.unsupportedLanguage": "Непідтримувана мова",
        "rule.unknownOrDuplicateSection": "Невідомий або повторений розділ",
        "action.deliverAggregate": "Фонова передача аналітики",
        "action.decodeOwnerBanner": "Завантаження налаштувань банера для керування",
        "action.deleteFeaturedBannerImage": "Очищення зображення банера",
        "action.assignOrganizationAdmin": "Надання прав адміністратора організації",
        "action.removeOrganizationAdmin": "Відкликання прав адміністратора організації",
        "action.assignOrganizationModerator": "Надання прав модератора організації",
        "action.removeOrganizationModerator": "Відкликання прав модератора організації",
        "action.transferOrganizationOwnership": "Передача власності організації",
        "action.listOrganizationReviewHistory": "Перегляд історії рішень щодо організацій",
        "action.approveOrganization": "Схвалення організації",
        "action.rejectOrganization": "Відхилення організації",
        "action.requestOrganizationRevision": "Повернення організації на доопрацювання",
        "action.registerForEvent": "Реєстрація на подію",
        "action.unregisterFromEvent": "Скасування реєстрації на подію",
        "action.assignAppAdmin": "Надання прав адміністратора застосунку",
        "action.removeAppAdmin": "Відкликання прав адміністратора застосунку",
        "action.warnUser": "Попередження користувача",
        "action.suspendUser": "Тимчасове блокування користувача",
        "action.banUser": "Постійне блокування користувача",
        "action.deactivateUser": "Деактивація акаунта",
        "action.restoreUser": "Відновлення доступу користувача",
        "action.searchManagedUsers": "Пошук користувачів",
        "action.getManagedUserSecurityMetadata": "Завантаження стану безпеки акаунта",
        "action.acceptLegalDocument": "Підтвердження правових документів",
        "action.acceptOrganizationRules": "Підтвердження правил організації",
        "action.listLegalEvidence": "Завантаження історії підтверджень",
        "action.listLegalEvidenceAccounts": "Пошук акаунтів в історії підтверджень",
        "action.getLegalEvidenceForUser": "Завантаження підтверджень користувача",
        "action.getLegalEvidencePage": "Завантаження сторінки історії підтверджень",
        "action.listFeedbackInbox": "Завантаження звернень і скарг",
        "action.manageOrganizationWorkspace": "Керування організаціями",
        "action.manageContentModeration": "Керування модерацією контенту",
        "action.deleteFeedback": "Видалення звернення",
        "action.clearFeedbackInbox": "Очищення списку звернень",
        "action.saveFeaturedBanner": "Збереження банера",
        "action.setFeaturedBannerActive": "Зміна активності банера",
        "action.deleteFeaturedBanner": "Видалення банера",
        "action.submitContentReport": "Надсилання скарги на контент",
        "action.reviewContentModeration": "Розгляд скарги на контент",
        "action.decideDsaCase": "Рішення за справою DSA",
        "action.submitDsaAppeal": "Подання апеляції DSA",
        "action.decideDsaAppeal": "Рішення за апеляцією DSA",
        "action.getMyDsaStatement": "Завантаження рішення DSA",
        "action.setUserBlocked": "Зміна особистого блокування користувача",
        "action.setOrganizationBlocked": "Зміна особистого блокування організації",
        "action.createOrganizationPhotoMetadata": "Додавання фотографії організації",
        "action.deleteOrganizationPhotoMetadata": "Видалення фотографії організації",
        "action.uploadOrganizationContentCover": "Завантаження обкладинки контенту",
        "action.sendTestPushNotification": "Надсилання тестового push-сповіщення",
        "action.activatePrivilegedMFAProtection": "Увімкнення обов’язкового двофакторного захисту",
        "field.id": "Ідентифікатор (id)",
        "field.actionType": "Дія банера (actionType)",
        "field.regionScope": "Охоплення регіонів (regionScope)",
        "field.visibleSections": "Розділи показу (visibleSections)",
        "field.displayDurationSeconds": "Тривалість показу (displayDurationSeconds)",
        "field.priority": "Пріоритет (priority)",
        "field.isActive": "Активність (isActive)",
        "field.createdAt": "Дата створення (createdAt)",
        "field.updatedAt": "Дата оновлення (updatedAt)",
        "field.actionTargetID": "Об’єкт переходу (actionTargetID)",
        "field.federalState": "Федеральна земля (federalState)",
        "field.startsAt/endsAt": "Період показу (startsAt/endsAt)",
        "field.internalName": "Внутрішня назва (internalName)",
        "field.title": "Заголовок (title)",
        "field.subtitle": "Підзаголовок (subtitle)",
        "event.news_view": "Перегляд новини",
        "event.event_view": "Перегляд події",
        "event.organization_view": "Перегляд організації",
        "event.news_like": "Вподобання новини",
        "event.news_bookmark": "Збереження новини",
        "event.event_register": "Реєстрація на подію",
        "event.event_cancel_registration": "Скасування реєстрації",
        "event.event_bookmark": "Збереження події",
        "event.organization_follow": "Підписка на організацію",
        "event.organization_unfollow": "Скасування підписки",
        "event.organization_bookmark": "Збереження організації",
        "bannerDecode.title": "Не вдалося прочитати налаштування банера",
        "bannerDecode.cause": "Збережені налаштування банера не пройшли перевірку. Проблемне поле та умову перевірки наведено нижче.",
        "impact.notificationInbox": "Не вдалося оновити список сповіщень цього акаунта. Запис стосується читання повідомлень, а не створення чи публікації контенту.",
        "impact.notificationBadge": "Не вдалося оновити кількість непрочитаних сповіщень. Це окреме фонове читання лічильника.",
        "stage.listenServerUpdates": "Отримання оновлень із сервера",
        "stage.readServerAggregation": "Читання лічильника із сервера",
        "action.listenOrganizationRequests": "Завантаження заявок організації",
        "impact.organizationRequests": "Не вдалося отримати оновлення списку заявок організації. Цей запис стосується читання списку; результат подання чи розгляду конкретної заявки він не встановлює.",
    ]
}
