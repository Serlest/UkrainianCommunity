import SwiftUI

enum OrganizationTeamRole: String, CaseIterable, Identifiable {
    case owner
    case admin
    case moderator
    case member

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner:
            AppStrings.Profile.organizationRoleOwner
        case .admin:
            AppStrings.Profile.organizationRoleAdmin
        case .moderator:
            AppStrings.Profile.organizationRoleModerator
        case .member:
            AppStrings.Profile.organizationRoleMember
        }
    }

    var tint: Color {
        switch self {
        case .owner:
            AppTheme.accentPrimary
        case .admin:
            Color.blue
        case .moderator:
            Color.orange
        case .member:
            AppTheme.textSecondary
        }
    }

    var communityRole: CommunityRole {
        switch self {
        case .owner:
            .communityOwner
        case .admin:
            .communityAdmin
        case .moderator:
            .communityModerator
        case .member:
            .member
        }
    }

    init?(_ role: CommunityRole) {
        switch role {
        case .communityOwner:
            self = .owner
        case .communityAdmin:
            self = .admin
        case .communityModerator:
            self = .moderator
        case .member:
            self = .member
        }
    }
}

struct OrganizationTeamMember: Identifiable {
    let profile: PublicUserProfile?
    let userID: String
    let role: OrganizationTeamRole

    var id: String { userID }

    var displayName: String {
        profile?.preferredDisplayName ?? AppStrings.Profile.organizationTeamMissingProfile
    }

    @MainActor var locationText: String? {
        guard let profile else { return nil }
        let city = profile.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = profile.federalState.map(AppStrings.FederalStates.title(for:))
        if city.isEmpty {
            return region
        }
        if let region, region != city {
            return "\(city), \(region)"
        }
        return city
    }

    var initials: String {
        guard let profile else { return "?" }
        let parts = profile.preferredDisplayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(parts).uppercased()
        return value.isEmpty ? "?" : value
    }
}

enum OrganizationTeamAction: Identifiable {
    case assign(member: OrganizationTeamMember, role: OrganizationTeamRole)
    case changeOwner(member: OrganizationTeamMember)
    case remove(member: OrganizationTeamMember)

    var id: String {
        switch self {
        case let .assign(member, role):
            "assign-\(member.userID)-\(role.rawValue)"
        case let .changeOwner(member):
            "change-owner-\(member.userID)"
        case let .remove(member):
            "remove-\(member.userID)-\(member.role.rawValue)"
        }
    }

    var title: String {
        switch self {
        case let .assign(member, role):
            AppStrings.profileOrganizationTeamAssignConfirmation(userName: member.displayName, role: role.title.lowercased())
        case let .changeOwner(member):
            AppStrings.profileOrganizationTeamChangeOwnerConfirmation(member.displayName)
        case let .remove(member):
            AppStrings.profileOrganizationTeamRemoveConfirmation(role: member.role.title.lowercased(), userName: member.displayName)
        }
    }

    var confirmTitle: String {
        switch self {
        case .assign:
            AppStrings.Profile.organizationTeamSaveRole
        case .changeOwner:
            AppStrings.Profile.organizationTeamChangeOwner
        case .remove:
            AppStrings.Profile.organizationTeamRemoveRole
        }
    }
}
