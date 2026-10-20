import SwiftUI

enum ProfileDashboardMode {
    case owner
    case admin

    init?(user: AppUser) {
        guard PermissionService.isUsableAccount(user: user) else { return nil }
        switch user.globalRole.authorizationRole {
        case .owner:
            self = .owner
        case .admin:
            self = .admin
        case .user, .topAdmin:
            return nil
        }
    }

    var badgeTitle: String {
        switch self {
        case .owner:
            return AppStrings.Profile.platformOwnerBadge
        case .admin:
            return AppStrings.Profile.platformAdminBadge
        }
    }

    var statusText: String {
        switch self {
        case .owner:
            return AppStrings.Profile.ownerHeroStatus
        case .admin:
            return AppStrings.Profile.adminHeroStatus
        }
    }

    var accessLevel: String {
        switch self {
        case .owner:
            return AppStrings.Profile.ownerFullAccess
        case .admin:
            return AppStrings.Profile.adminOperationalAccess
        }
    }

    var badgeSymbol: String {
        switch self {
        case .owner:
            return "crown"
        case .admin:
            return "person.badge.key"
        }
    }
}

struct OwnerHeroCard: View {
    let user: AppUser
    let readableFederalState: String?
    let mode: ProfileDashboardMode

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 14) {
                    ProfileAvatarView(user: user)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.preferredDisplayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if case .admin = mode {
                            Text(mode.statusText)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                ProfileBadge(title: mode.badgeTitle, systemImage: mode.badgeSymbol)
                                ProfileBadge(title: user.accountStatus.title, systemImage: "checkmark.seal")
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ProfileBadge(title: mode.badgeTitle, systemImage: mode.badgeSymbol)
                                ProfileBadge(title: user.accountStatus.title, systemImage: "checkmark.seal")
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    if let city = profileOwnerNilIfEmpty(user.city) {
                        ProfileMetadataRow(title: AppStrings.Common.city, value: city, systemImage: "mappin.and.ellipse")
                    }

                    if let readableFederalState {
                        ProfileMetadataRow(title: AppStrings.Profile.region, value: readableFederalState, systemImage: "globe.europe.africa")
                    }

                    if case .admin = mode {
                        ProfileMetadataRow(title: AppStrings.Profile.systemAccessLevel, value: mode.accessLevel, systemImage: "lock.shield")
                    }
                }
            }
        }
    }
}

private func profileOwnerNilIfEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Owner dashboard copy is kept together so section labels stay consistent in both app languages.
enum OwnerProfileText {
    static func value(_ uk: String, _ de: String) -> String {
        AppLanguage.stored == .german ? de : uk
    }
    static var adminToolsSubtitle: String { value("Користувачі та журнал адміністративних дій.", "Nutzer und Protokoll der Verwaltungsaktionen.") }
    static var adminUsersSubtitle: String { value("Пошук, попередження та статуси користувачів.", "Suche, Verwarnungen und Kontostatus.") }
    static var accessTitle: String { value("Організації та доступ", "Organisationen und Zugriff") }
    static var contentTitle: String { value("Публікації та повідомлення", "Inhalte und Mitteilungen") }
    static var reportsTitle: String { value("Аналітика та контроль", "Auswertung und Kontrolle") }
    static var platformSettingsTitle: String { value("Налаштування платформи", "Plattformeinstellungen") }
    static var organizations: String { value("Керування організаціями", "Organisationen verwalten") }
    static var organizationsSubtitle: String { value("Усі організації платформи та допомога їхнім власникам.", "Alle Organisationen der Plattform und Unterstützung ihrer Eigentümer.") }
    static var directoryEditors: String { value("Редактори довідника", "Ratgeberredakteure") }
    static var directoryEditorsSubtitle: String { value("Хто може додавати й редагувати матеріали.", "Zugriff auf die Bearbeitung der Inhalte.") }
    static var notificationsSubtitle: String { value("Сповіщення про заявки, звернення та роботу платформи.", "Benachrichtigungen zu Anträgen, Anfragen und zum Plattformbetrieb.") }
    static var accountSubtitle: String { value("Сповіщення, безпека та особисті налаштування.", "Benachrichtigungen, Sicherheit und persönliche Einstellungen.") }
    static var ownerAccountTitle: String { value("Обліковий запис власника", "Inhaberkonto") }
    static var legalDocumentsSubtitle: String { value("Умови користування, конфіденційність і правила організацій.", "Nutzungsbedingungen, Datenschutz und Organisationsregeln.") }
    static var registrations: String { value("Мої реєстрації на події", "Meine Veranstaltungsanmeldungen") }
}
