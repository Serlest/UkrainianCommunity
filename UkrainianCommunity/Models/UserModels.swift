import Foundation
import SwiftUI

enum UserRole: String, CaseIterable, Codable, Identifiable {
    case user
    case moderator
    case admin
    case owner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user:
            AppStrings.Roles.user
        case .moderator:
            AppStrings.Roles.moderator
        case .admin:
            AppStrings.Roles.admin
        case .owner:
            AppStrings.Roles.owner
        }
    }

    var permissions: PermissionService { PermissionService(role: self) }
    var canLikeContent: Bool { permissions.canLikeContent }
    var canCreateContent: Bool { permissions.canCreateContent }
    var canEditContent: Bool { permissions.canEditContent }
    var canManageModerators: Bool { permissions.canManageModerators }
    var canManageUsers: Bool { permissions.canManageUsers }
}

enum UserBlockState: String, Codable {
    case active
    case blocked

    var title: String {
        switch self {
        case .active:
            AppStrings.Common.active
        case .blocked:
            AppStrings.Common.blocked
        }
    }
}

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    nonisolated private static let storageKey = "selectedAppLanguage"

    case german = "de"
    case ukrainian = "uk"

    nonisolated var id: String { rawValue }
    nonisolated var localeIdentifier: String { rawValue }

    var title: String {
        switch self {
        case .german:
            AppStrings.Settings.german
        case .ukrainian:
            AppStrings.Settings.ukrainian
        }
    }

    nonisolated static var stored: AppLanguage {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
                  let language = AppLanguage(rawValue: rawValue) else {
                return preferred
            }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    nonisolated private static var preferred: AppLanguage {
        let preferredLanguageCode = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferredLanguageCode.hasPrefix(ukrainian.rawValue) ? .ukrainian : .german
    }
}

enum AppAppearance: String, CaseIterable, Codable, Identifiable {
    nonisolated private static let storageKey = "selectedAppAppearance"

    case system
    case light
    case dark

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            AppStrings.Settings.system
        case .light:
            AppStrings.Settings.light
        case .dark:
            AppStrings.Settings.dark
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    nonisolated static var stored: AppAppearance {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
                  let appearance = AppAppearance(rawValue: rawValue) else {
                return .system
            }
            return appearance
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }
}

struct UserSettings: Codable {
    var language: AppLanguage
    var appearance: AppAppearance

    nonisolated static var stored: UserSettings {
        get {
            UserSettings(language: AppLanguage.stored, appearance: AppAppearance.stored)
        }
        set {
            AppLanguage.stored = newValue.language
            AppAppearance.stored = newValue.appearance
        }
    }
}

struct AppUser: Identifiable, Codable {
    let id: String
    let fullName: String
    let city: String
    let email: String
    let bio: String
    let role: UserRole
    let blockState: UserBlockState
    let createdAt: Date
    let updatedAt: Date

    var joinedAt: Date { createdAt }

    static let placeholder = AppUser(
        id: "placeholder-user",
        fullName: "",
        city: "",
        email: "",
        bio: "",
        role: .user,
        blockState: .active,
        createdAt: .now,
        updatedAt: .now
    )
}
