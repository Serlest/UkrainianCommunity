import Foundation

struct PermissionService {
    let role: UserRole

    var canLikeContent: Bool {
        true
    }

    var canCreateNews: Bool {
        isModeratorTier
    }

    var canEditNews: Bool {
        isModeratorTier
    }

    var canDeleteNews: Bool {
        isOwner
    }

    var canCreateEvent: Bool {
        isModeratorTier
    }

    var canCreateOrganization: Bool {
        isModeratorTier
    }

    var canEditEvent: Bool {
        isModeratorTier
    }

    var canEditOrganization: Bool {
        isModeratorTier
    }

    var canDeleteEvent: Bool {
        isOwner
    }

    var canDeleteOrganization: Bool {
        isOwner
    }

    var canManageUsers: Bool {
        isOwner
    }

    var canModerateContent: Bool {
        isModeratorTier
    }

    var canBlockUsers: Bool {
        isAdminTier
    }

    var canAssignModerator: Bool {
        isAdminTier
    }

    var canAssignAdmin: Bool {
        isOwner
    }

    var canAccessOwnerTools: Bool {
        isOwner
    }

    var canCreateContent: Bool {
        canCreateNews || canCreateEvent || canCreateOrganization
    }

    var canEditContent: Bool {
        canEditNews || canEditEvent || canEditOrganization
    }

    var canManageModerators: Bool {
        canAssignModerator
    }

    static func canModerate(section: AppSection, user: AppUser) -> Bool {
        switch user.globalRole {
        case .owner, .topAdmin:
            return true
        case .appModerator:
            if user.moderatorSections.isEmpty, user.role == .moderator {
                return true
            }
            return user.moderatorSections.contains(section)
        case .user:
            return false
        }
    }

    static func moderatedSections(for user: AppUser) -> Set<AppSection> {
        let allSections = Set([AppSection.news, .events, .organizations, .comments])

        switch user.globalRole {
        case .owner, .topAdmin:
            return allSections
        case .appModerator:
            if user.moderatorSections.isEmpty, user.role == .moderator {
                return allSections
            }
            return Set(user.moderatorSections)
        case .user:
            return []
        }
    }

    static func canManageCommunity(organizationId: String, user: AppUser) -> Bool {
        switch user.globalRole {
        case .owner, .topAdmin:
            return true
        case .appModerator, .user:
            return user.communityMemberships.contains {
                $0.organizationId == organizationId && $0.role != .member
            }
        }
    }

    static func manageableOrganizationIDs(user: AppUser?) -> Set<String> {
        guard let user else { return [] }

        switch user.globalRole {
        case .owner, .topAdmin:
            return []
        case .appModerator, .user:
            return Set(
                user.communityMemberships
                    .filter { $0.role != .member }
                    .map(\.organizationId)
            )
        }
    }

    static func canAccessOrganizationManagement(user: AppUser?) -> Bool {
        guard let user else { return false }

        switch user.globalRole {
        case .owner, .topAdmin:
            return true
        case .appModerator, .user:
            return !manageableOrganizationIDs(user: user).isEmpty
        }
    }

    static func canManageAppNews(user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .news, user: user)
    }

    static func canManageAppEvents(user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .events, user: user)
    }

    static func canAccessContentManagement(user: AppUser?) -> Bool {
        canManageAppNews(user: user) || canManageAppEvents(user: user)
    }

    static func canCreateOrganization(user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .organizations, user: user)
    }

    static func canCreateNews(user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .news, user: user)
    }

    static func canCreateNews(for organizationId: String, user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .news, user: user) || canManageCommunity(organizationId: organizationId, user: user)
    }

    static func canEditNews(user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .news, user: user)
    }

    static func canDeleteNews(user: AppUser?) -> Bool {
        guard let user else { return false }

        switch user.globalRole {
        case .owner, .topAdmin:
            return true
        case .appModerator, .user:
            return false
        }
    }

    static func canCreateEvent(user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .events, user: user)
    }

    static func canCreateEvent(for organizationId: String, user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .events, user: user) || canManageCommunity(organizationId: organizationId, user: user)
    }

    static func canEditEvent(user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .events, user: user)
    }

    static func canDeleteEvent(user: AppUser?) -> Bool {
        guard let user else { return false }

        switch user.globalRole {
        case .owner, .topAdmin:
            return true
        case .appModerator, .user:
            return false
        }
    }

    static func canEditOrganization(user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .organizations, user: user)
    }

    static func canEditOrganization(organizationId: String, user: AppUser?) -> Bool {
        guard let user else { return false }
        return canModerate(section: .organizations, user: user) || canManageCommunity(organizationId: organizationId, user: user)
    }

    static func canDeleteOrganization(user: AppUser?) -> Bool {
        guard let user else { return false }

        switch user.globalRole {
        case .owner, .topAdmin:
            return true
        case .appModerator, .user:
            return false
        }
    }

    static func canAssignGlobalRoles(user: AppUser) -> Bool {
        user.globalRole == .owner
    }

    static func canPermanentlyBan(user: AppUser) -> Bool {
        user.globalRole == .owner
    }

    static func canTemporarilyBan(user: AppUser) -> Bool {
        user.globalRole == .owner || user.globalRole == .topAdmin
    }

    static func canAccessAdminTools(user: AppUser?) -> Bool {
        guard let user else { return false }
        return user.globalRole == .owner || user.globalRole == .topAdmin
    }

    static func canAccessModerationTools(user: AppUser?) -> Bool {
        guard let user else { return false }

        return canModerate(section: .news, user: user)
            || canModerate(section: .events, user: user)
            || canModerate(section: .organizations, user: user)
    }

    private var isModeratorTier: Bool {
        role == .moderator || role == .admin || role == .owner
    }

    private var isAdminTier: Bool {
        role == .admin || role == .owner
    }

    private var isOwner: Bool {
        role == .owner
    }
}
