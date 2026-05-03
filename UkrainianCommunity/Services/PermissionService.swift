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

    var canEditEvent: Bool {
        isModeratorTier
    }

    var canDeleteEvent: Bool {
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
        canCreateNews || canCreateEvent
    }

    var canEditContent: Bool {
        canEditNews || canEditEvent
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
        let allSections = Set([AppSection.news, .events, .organizations, .marketplace, .comments])

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

    static func canAssignGlobalRoles(user: AppUser) -> Bool {
        user.globalRole == .owner
    }

    static func canPermanentlyBan(user: AppUser) -> Bool {
        user.globalRole == .owner
    }

    static func canTemporarilyBan(user: AppUser) -> Bool {
        user.globalRole == .owner || user.globalRole == .topAdmin
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
