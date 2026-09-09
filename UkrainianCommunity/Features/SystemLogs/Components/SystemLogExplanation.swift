import Foundation

/// Explains the recorded evidence; it never infers an incident's root cause from timing alone.
enum SystemLogExplanation {
    nonisolated static func text(_ key: String) -> String {
        LocalizationStore.localizedString("system_logs.explanation." + key, defaultValue: defaults[key] ?? key)
    }

    nonisolated static func kind(_ log: SystemLogEntry) -> String {
        switch log.errorCode ?? "" {
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
        case "parsing.decodingFailed": "parsing"
        default: "unknown"
        }
    }

    nonisolated static func isFailure(_ log: SystemLogEntry) -> Bool {
        log.eventType == .technicalError || log.errorCode != nil || log.outcome == .failed
    }

    nonisolated static func title(_ log: SystemLogEntry) -> String {
        isFailure(log) ? text(kind(log) + ".title") : SystemLogDisplayFormatting.summaryTitle(log.summary)
    }

    nonisolated static func cause(_ log: SystemLogEntry) -> String {
        text(kind(log) + ".cause")
    }

    nonisolated static func nextStep(_ log: SystemLogEntry) -> String {
        switch kind(log) {
        case "connection", "offline", "timeout", "unavailable": text("network.next")
        case "permission": text("permission.next")
        case "auth": text("auth.next")
        case "mfa": text("mfa.next")
        default: text("unknown.next")
        }
    }

    nonisolated static func action(_ log: SystemLogEntry) -> String {
        if let operation = log.operationName, defaults["action." + operation] != nil {
            return text("action." + operation)
        }
        return isFailure(log) ? text("action.unknown") : SystemLogDisplayFormatting.eventTypeTitle(log.eventType)
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
    ]
}
