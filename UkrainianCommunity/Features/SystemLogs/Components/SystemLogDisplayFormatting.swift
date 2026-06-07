import SwiftUI

enum SystemLogDisplayFormatting {
    nonisolated static func summaryTitle(_ summary: String) -> String {
        if summary.hasPrefix("Technical failure in ") {
            let operation = summary.replacingOccurrences(of: "Technical failure in ", with: "")
            return LocalizationStore.localizedFormat(
                "system_logs.summary.technical_failure_in",
                defaultValue: "Технічна помилка: %@",
                arguments: [operation]
            )
        }

        return switch summary {
        case "News post created": localized("summary.news_created", "Новину створено")
        case "News post updated": localized("summary.news_updated", "Новину оновлено")
        case "News post deleted": localized("summary.news_deleted", "Новину видалено")
        case "Event created": localized("summary.event_created", "Подію створено")
        case "Event updated": localized("summary.event_updated", "Подію оновлено")
        case "Event deleted": localized("summary.event_deleted", "Подію видалено")
        case "Organization created": localized("summary.organization_created", "Організацію створено")
        case "Organization updated": localized("summary.organization_updated", "Організацію оновлено")
        case "Organization deleted": localized("summary.organization_deleted", "Організацію видалено")
        case "Guide article created": localized("summary.guide_created", "Статтю довідника створено")
        case "Guide article updated": localized("summary.guide_updated", "Статтю довідника оновлено")
        case "Guide article archived": localized("summary.guide_archived", "Статтю довідника архівовано")
        case "Featured banner created": localized("summary.banner_created", "Банер створено")
        case "Featured banner updated": localized("summary.banner_updated", "Банер оновлено")
        case "Featured banner archived": localized("summary.banner_archived", "Банер архівовано")
        case "Featured banner deleted": localized("summary.banner_deleted", "Банер видалено")
        case "Permission denied": localized("summary.permission_denied", "Доступ відхилено")
        case "Critical technical error": localized("summary.critical_error", "Критична технічна помилка")
        case "Moderation action completed": localized("summary.moderation_completed", "Модераційну дію виконано")
        case "Organization action completed": localized("summary.organization_action_completed", "Дію з організацією виконано")
        case "User profile action completed": localized("summary.user_profile_action_completed", "Дію з профілем виконано")
        default: summary
        }
    }

    nonisolated static func eventTypeTitle(_ eventType: SystemLogEventType) -> String {
        return switch eventType {
        case .signedIn: localized("event.signed_in", "Вхід виконано")
        case .signedOut: localized("event.signed_out", "Вихід виконано")
        case .permissionDenied: localized("event.permission_denied", "Доступ відхилено")
        case .roleAssigned: localized("event.role_assigned", "Роль призначено")
        case .roleRemoved: localized("event.role_removed", "Роль вилучено")
        case .accountBlocked: localized("event.account_blocked", "Обліковий запис заблоковано")
        case .accountUnblocked: localized("event.account_unblocked", "Обліковий запис розблоковано")
        case .userWarned: localized("event.user_warned", "Користувача попереджено")
        case .userProfileUpdated: localized("event.user_profile_updated", "Профіль користувача оновлено")
        case .contentCreated: localized("event.content_created", "Контент створено")
        case .contentUpdated: localized("event.content_updated", "Контент оновлено")
        case .contentDeleted: localized("event.content_deleted", "Контент видалено")
        case .contentApproved: localized("event.content_approved", "Контент схвалено")
        case .contentRejected: localized("event.content_rejected", "Контент відхилено")
        case .reportSubmitted: localized("event.report_submitted", "Скаргу подано")
        case .reportReviewed: localized("event.report_reviewed", "Скаргу переглянуто")
        case .organizationRequestSubmitted: localized("event.organization_request_submitted", "Запит організації подано")
        case .organizationRequestApproved: localized("event.organization_request_approved", "Запит організації схвалено")
        case .organizationRequestRejected: localized("event.organization_request_rejected", "Запит організації відхилено")
        case .configurationUpdated: localized("event.configuration_updated", "Налаштування оновлено")
        case .notificationQueued: localized("event.notification_queued", "Сповіщення поставлено в чергу")
        case .diagnosticSnapshotCreated: localized("event.diagnostic_snapshot_created", "Діагностичний знімок створено")
        case .technicalError: localized("event.technical_error", "Технічна помилка")
        case .dataValidationFailed: localized("event.data_validation_failed", "Перевірка даних не пройшла")
        case .unknown: localized("event.unknown", "Невідома подія")
        }
    }

    nonisolated static func retentionPolicyTitle(_ policy: SystemLogRetentionPolicy?) -> String {
        guard let policy else { return localized("not_recorded", "Не записано") }
        return switch policy {
        case .normalAudit: localized("retention.normal_audit", "Звичайний аудит")
        case .technicalError: localized("retention.technical_error", "Технічна помилка")
        case .security: localized("section.security", "Безпека")
        case .moderationDispute: localized("section.moderation", "Модерація")
        }
    }

    nonisolated static func severityTitle(_ severity: SystemLogSeverity) -> String {
        return switch severity {
        case .debug: localized("severity.debug", "Діагностика")
        case .info: localized("severity.info", "Інформація")
        case .notice: localized("severity.notice", "Повідомлення")
        case .warning: localized("severity.warning", "Попередження")
        case .error: localized("severity.error", "Помилка")
        case .critical: localized("filter.critical", "Критичні")
        }
    }

    nonisolated static func categoryTitle(_ category: SystemLogCategory) -> String {
        return switch category {
        case .authentication: localized("category.authentication", "Вхід")
        case .authorization: localized("section.security", "Безпека")
        case .audit: localized("category.audit", "Дія")
        case .moderation: localized("section.moderation", "Модерація")
        case .content: localized("category.content", "Контент")
        case .organization: localized("category.organization", "Організація")
        case .userAccount: localized("category.user_account", "Користувач")
        case .configuration: localized("category.configuration", "Налаштування")
        case .notification: localized("category.notification", "Сповіщення")
        case .dataIntegrity: localized("category.data_integrity", "Дані")
        case .diagnostics: localized("category.diagnostics", "Помилка")
        case .unknown: localized("unknown", "Невідомо")
        }
    }

    nonisolated static func outcomeTitle(_ outcome: SystemLogOutcome?) -> String {
        guard let outcome else { return localized("not_recorded", "Не записано") }
        return switch outcome {
        case .success: localized("outcome.success", "Успішно")
        case .failed: localized("outcome.failed", "Невдало")
        case .blocked: localized("outcome.blocked", "Заблоковано")
        case .pending: localized("outcome.pending", "Очікує")
        case .approved: localized("outcome.approved", "Схвалено")
        case .rejected: localized("outcome.rejected", "Відхилено")
        case .skipped: localized("outcome.skipped", "Пропущено")
        case .unknown: localized("unknown", "Невідомо")
        }
    }

    nonisolated static func actorRoleTitle(_ role: SystemLogActorRole) -> String {
        switch role {
        case .guest: localized("role.guest", "Гість")
        case .user: localized("role.user", "Користувач")
        case .organizationModerator: localized("role.organization_moderator", "Модератор організації")
        case .organizationAdmin: localized("role.organization_admin", "Адмін організації")
        case .organizationOwner: localized("role.organization_owner", "Власник організації")
        case .guideEditor: localized("role.guide_editor", "Редактор довідника")
        case .moderator: localized("role.moderator", "Модератор")
        case .admin: localized("role.admin", "Адміністратор")
        case .owner: localized("role.owner", "Власник")
        case .system: localized("role.system", "Система")
        case .unknown: localized("unknown", "Невідомо")
        }
    }

    nonisolated static func targetTypeTitle(_ targetType: SystemLogTargetType) -> String {
        switch targetType {
        case .account: localized("target.account", "Обліковий запис")
        case .userProfile: localized("target.user_profile", "Профіль")
        case .newsPost: localized("target.news_post", "Новина")
        case .event: localized("target.event", "Подія")
        case .organization: localized("target.organization", "Організація")
        case .organizationRequest: localized("target.organization_request", "Запит організації")
        case .guideArticle: localized("target.guide_article", "Стаття довідника")
        case .guideMaterial: localized("target.guide_material", "Матеріал довідника")
        case .feedback: localized("target.feedback", "Звернення")
        case .report: localized("target.report", "Скарга")
        case .notification: localized("target.notification", "Сповіщення")
        case .donationConfig: localized("target.donation_config", "Донати")
        case .legalDocument: localized("target.legal_document", "Правовий документ")
        case .systemConfiguration: localized("target.system_configuration", "Налаштування")
        case .diagnosticSnapshot: localized("target.diagnostic_snapshot", "Діагностика")
        case .none: localized("target.none", "Без цілі")
        case .unknown: localized("unknown", "Невідомо")
        }
    }

    nonisolated static func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func severityTint(_ severity: SystemLogSeverity) -> Color {
        switch severity {
        case .critical, .error:
            AppTheme.accentDestructive
        case .warning:
            Color.orange
        case .notice:
            AppTheme.accentPrimary
        case .info:
            Color.green
        case .debug:
            AppTheme.textSecondary
        }
    }

    static func severityFill(_ severity: SystemLogSeverity) -> Color {
        severityTint(severity).opacity(0.12)
    }

    static func toneTint(_ tone: SystemLogMetricTone) -> Color {
        switch tone {
        case .primary:
            AppTheme.accentPrimary
        case .warning:
            Color.orange
        case .critical:
            AppTheme.accentDestructive
        case .success:
            Color.green
        case .neutral:
            AppTheme.textSecondary
        }
    }

    static func toneFill(_ tone: SystemLogMetricTone) -> Color {
        toneTint(tone).opacity(0.12)
    }

    private nonisolated static func localized(_ key: String, _ defaultValue: String) -> String {
        LocalizationStore.localizedString("system_logs.\(key)", defaultValue: defaultValue)
    }
}
