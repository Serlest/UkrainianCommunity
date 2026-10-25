import Foundation

enum UserAdministrationCopy {
    static var warningCount: String { text("warning_count", "Кількість попереджень") }
    static var auditNotice: String { text("audit_notice", "Успішну зміну буде збережено в історії. Відповідні користувачі отримають сповіщення.") }
    static var unavailable: String { text("unavailable", "Акаунт видалено або він більше недоступний.") }
    static var reviewChanged: String { text("review_changed", "Дані користувача або ваші права змінилися. Закрийте це вікно, оновіть картку та перевірте дію ще раз.") }
    static var reasonLimit: String { text("reason_limit", "Причина: не більше 2000 символів.") }
    private static func text(_ key: String, _ fallback: String) -> String {
        LocalizationStore.localizedString("users_audit." + key, defaultValue: fallback, table: "UserManagementAudit")
    }
}
