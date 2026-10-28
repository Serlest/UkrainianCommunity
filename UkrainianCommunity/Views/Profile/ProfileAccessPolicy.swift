import Foundation

/// Changes only when the principal or authority changes, never on presence/profile refresh.
struct ProfileAccessIdentity: Hashable {
    let userID: String?
    let role: String?
    let accountStatus: String?
    let blockState: String?

    init(user: AppUser?) {
        userID = user?.id
        role = user?.globalRole.authorizationRole.rawValue
        accountStatus = user?.accountStatus.rawValue
        blockState = user?.blockState.rawValue
    }
}

/// One entry-point policy for menu links, pushed destinations and notification deep links.
/// Organization-specific controls additionally require the actual Organization's permissions.
struct ProfileAccessPolicy {
    let user: AppUser?

    var canUsePersonalFeatures: Bool { PermissionService.isUsableAccount(user: user) }
    var canContactSupport: Bool { canUsePersonalFeatures && !PermissionService.isAppOwner(user: user) }

    func allows(_ route: ProfileNavigationRoute) -> Bool {
        switch route {
        case .legal:
            return true
        case .profileSettings, .accountSecurity, .dsaStatement:
            return user != nil
        case .announcementManagement, .directoryEditors, .featuredBannerManagement, .seasonalManagement,
             .contentPlanning, .contentPlanningNews, .contentPlanningEvent,
             .legalDocumentManagement, .legalEvidence, .ownerAnalytics, .bannerAnalytics, .donationSettings:
            return PermissionService.isAppOwner(user: user)
        case .organizationRequests, .organizationRequestReview:
            return PermissionService.canManageOrganizationRequests(user: user)
        case .moderationMaterial:
            return canUsePersonalFeatures
        case .moderationTools:
            return PermissionService.canAccessModerationTools(user: user)
        case .userManagement:
            return PermissionService.canManageUsers(user: user)
        case .feedbackInbox, .feedbackDetail:
            return PermissionService.canManageFeedback(user: user)
        case .systemLogDetail:
            return PermissionService.isAppOwner(user: user)
        case .systemLogs(let mode):
            switch mode {
            case .owner: return PermissionService.isAppOwner(user: user)
            case .appAdmin: return PermissionService.isAppAdmin(user: user)
            }
        case .myFeedback(let userID), .myFeedbackDetail(let userID, _, _):
            return user != nil && user?.globalRole.authorizationRole != .owner && userID == user?.id
        case .feedbackComposer, .announcementFeedback, .supportProject:
            return canContactSupport
        case .organizationManagement:
            // Includes registration of an organization and one's own pending requests.
            return PermissionService.canCreateOrganization(user: user)
        case .blockedUsers, .blockedOrganizations:
            return PermissionService.canAccessBlockedUsersSettings(user: user)
        case .registrations, .savedContent, .followedOrganizations, .recentViews, .activityHistory,
             .notifications, .announcementHistory:
            return canUsePersonalFeatures
        }
    }
}
