import Foundation
import SwiftUI

enum GlobalRole: String, CaseIterable, Codable, Identifiable {
    case owner
    case topAdmin
    case appModerator
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner:
            AppStrings.Roles.owner
        case .topAdmin:
            AppStrings.Roles.topAdmin
        case .appModerator:
            AppStrings.Roles.appModerator
        case .user:
            AppStrings.Roles.user
        }
    }

    nonisolated init(legacyRole: UserRole) {
        switch legacyRole {
        case .owner:
            self = .owner
        case .admin:
            self = .topAdmin
        case .moderator:
            self = .appModerator
        case .user:
            self = .user
        }
    }
}

enum AppSection: String, CaseIterable, Codable, Identifiable {
    case news
    case events
    case organizations
    case marketplace
    case comments

    var id: String { rawValue }
}

enum AccountStatus: String, CaseIterable, Codable, Identifiable {
    case active
    case warned
    case temporarilyBanned
    case permanentlyBanned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:
            AppStrings.Common.active
        case .warned:
            AppStrings.Common.status
        case .temporarilyBanned:
            AppStrings.Common.blocked
        case .permanentlyBanned:
            AppStrings.Common.blocked
        }
    }
}

enum CommunityRole: String, CaseIterable, Codable, Identifiable {
    case communityOwner
    case communityAdmin
    case communityModerator
    case member

    var id: String { rawValue }
}

struct CommunityMembership: Codable, Hashable, Identifiable {
    let organizationId: String
    let role: CommunityRole

    var id: String { organizationId }
}

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
    let globalRole: GlobalRole
    let moderatorSections: [AppSection]
    let blockState: UserBlockState
    let accountStatus: AccountStatus
    let banExpiresAt: Date?
    let warningCount: Int
    let communityMemberships: [CommunityMembership]
    let createdAt: Date
    let updatedAt: Date

    var joinedAt: Date { createdAt }

    nonisolated init(
        id: String,
        fullName: String,
        city: String,
        email: String,
        bio: String,
        role: UserRole,
        globalRole: GlobalRole? = nil,
        moderatorSections: [AppSection] = [],
        blockState: UserBlockState,
        accountStatus: AccountStatus? = nil,
        banExpiresAt: Date? = nil,
        warningCount: Int = 0,
        communityMemberships: [CommunityMembership] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.fullName = fullName
        self.city = city
        self.email = email
        self.bio = bio
        self.role = role
        self.globalRole = globalRole ?? GlobalRole(legacyRole: role)
        self.moderatorSections = moderatorSections
        self.blockState = blockState
        self.accountStatus = accountStatus ?? (blockState == .blocked ? .temporarilyBanned : .active)
        self.banExpiresAt = banExpiresAt
        self.warningCount = warningCount
        self.communityMemberships = communityMemberships
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

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
