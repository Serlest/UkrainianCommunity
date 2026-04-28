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
