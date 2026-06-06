import Foundation

struct PermissionService {
    let role: UserRole

    // UserRole is a legacy app-role source kept for migration-only paths.
    // New authorization must use AppUser.globalRole.authorizationRole plus organization roles.

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
        false
    }

    var canCreateOrganization: Bool {
        isOwner
    }

    var canEditEvent: Bool {
        isOwner
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
        isOwner
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

    static func isUsableAccount(user: AppUser?) -> Bool {
        guard let user else { return false }
        return (user.accountStatus == .active || user.accountStatus == .warned)
            && (user.blockState == .active || user.blockState == .warned)
    }

    private static func hasUsableAccount(_ user: AppUser?) -> Bool {
        isUsableAccount(user: user)
    }

    private static func isOwner(_ user: AppUser?) -> Bool {
        isAppOwner(user: user)
    }

    static func isAppOwner(user: AppUser?) -> Bool {
        hasUsableAccount(user) && user?.globalRole.authorizationRole == .owner
    }

    static func isAppAdmin(user: AppUser?) -> Bool {
        hasUsableAccount(user) && user?.globalRole.authorizationRole == .admin
    }

    static func isAppModerator(user: AppUser?) -> Bool {
        hasUsableAccount(user) && user?.globalRole.authorizationRole == .moderator
    }

    static func isGuideEditor(user: AppUser?) -> Bool {
        canManageGuide(user: user)
    }

    private static func isGuideManager(_ user: AppUser?) -> Bool {
        guard let user, hasUsableAccount(user) else { return false }
        return user.globalRole.authorizationRole == .owner || user.canManageGuide
    }

    // Owner surfaces are named here so views and view models can ask for intent
    // without checking globalRole directly. Owner organization override does not
    // mutate organization.ownerId, adminIds, or moderatorIds.
    static func hasOwnerRoleForDisplay(user: AppUser?) -> Bool {
        user?.globalRole.authorizationRole == .owner
    }

    static func canAccessOwnerDashboard(user: AppUser?) -> Bool {
        isOwner(user)
    }

    static func canManageFeaturedBanners(user: AppUser?) -> Bool {
        isOwner(user)
    }

    static func canDeleteFeaturedBanners(user: AppUser?) -> Bool {
        canManageFeaturedBanners(user: user)
    }

    static func canManageUsers(user: AppUser?) -> Bool {
        isOwner(user) || isAppAdmin(user: user)
    }

    static func canAssignAppAdmin(user: AppUser?) -> Bool {
        isOwner(user)
    }

    static func canAssignAppModerator(user: AppUser?) -> Bool {
        isOwner(user) || isAppAdmin(user: user)
    }

    static func canAssignGuideEditor(user: AppUser?) -> Bool {
        isOwner(user) || isAppAdmin(user: user)
    }

    static func canManageUserTarget(actor: AppUser?, target: AppUser?) -> Bool {
        guard let actor, let target else { return false }
        guard canManageUsers(user: actor) else { return false }
        guard actor.id != target.id else { return false }
        return target.globalRole.authorizationRole != .owner
    }

    static func canManageFeedback(user: AppUser?) -> Bool {
        isOwner(user) || isAppAdmin(user: user) || isAppModerator(user: user)
    }

    static func canManageReports(user: AppUser?) -> Bool {
        isOwner(user) || isAppAdmin(user: user) || isAppModerator(user: user)
    }

    static func canManageModeration(user: AppUser?) -> Bool {
        canAccessModerationTools(user: user)
    }

    static func canManageOrganizations(user: AppUser?) -> Bool {
        isOwner(user)
    }

    static func canManageOrganizationRequests(user: AppUser?) -> Bool {
        isOwner(user) || isAppAdmin(user: user)
    }

    static func canUseOwnerOrganizationOverride(user: AppUser?) -> Bool {
        isOwner(user)
    }

    static func canUseOrganizationOverride(user: AppUser?) -> Bool {
        canUseOwnerOrganizationOverride(user: user)
    }

    static func canManageAnyOrganization(user: AppUser?) -> Bool {
        canUseOwnerOrganizationOverride(user: user)
    }

    static func canManageAnyOrganizationContent(user: AppUser?) -> Bool {
        canUseOwnerOrganizationOverride(user: user)
    }

    static func canManageAnyOrganizationMedia(user: AppUser?) -> Bool {
        canUseOwnerOrganizationOverride(user: user)
    }

    // Cloud Functions remain the authority for applying role changes and ownership transfers.
    static func canInitiateOrganizationRoleWorkflow(user: AppUser?) -> Bool {
        canUseOwnerOrganizationOverride(user: user)
    }

    static func canInitiateOwnershipTransferWorkflow(user: AppUser?) -> Bool {
        canUseOwnerOrganizationOverride(user: user)
    }

    static func canModerate(section: AppSection, user: AppUser) -> Bool {
        // Legacy topAdmin, appModerator, and moderatorSections are decoded for
        // migration safety only; active moderation comes from GlobalRole.
        guard hasUsableAccount(user) else { return false }
        switch user.globalRole.authorizationRole {
        case .owner, .admin, .moderator:
            return true
        case .user, .topAdmin, .appModerator:
            return false
        }
    }

    static func moderatedSections(for user: AppUser) -> Set<AppSection> {
        canModerate(section: .news, user: user)
            ? Set([AppSection.news, .events, .organizations, .comments])
            : []
    }

    static func organizationRole(for organization: Organization, user: AppUser?) -> CommunityRole? {
        guard !organization.isSystemOrganization else { return nil }
        guard let user, hasUsableAccount(user) else { return nil }

        if organization.ownerId == user.id {
            return .communityOwner
        }
        if organization.adminIds.contains(user.id) {
            return .communityAdmin
        }
        if organization.moderatorIds.contains(user.id) {
            return .communityModerator
        }
        return nil
    }

    // ID-only checks cannot prove organization-scoped access without loading the Organization.
    // Use Organization overloads for org-scoped permissions.
    @available(*, unavailable, message: "Load the Organization and use organizationRole(for:user:) instead.")
    static func organizationRole(for organizationId: String, user: AppUser?) -> CommunityRole? {
        nil
    }

    static func isOrganizationOwner(_ organization: Organization, user: AppUser?) -> Bool {
        organizationRole(for: organization, user: user) == .communityOwner
    }

    @available(*, unavailable, message: "Load the Organization and use isOrganizationOwner(_:user:) instead.")
    static func isOrganizationOwner(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func isOrganizationAdmin(_ organization: Organization, user: AppUser?) -> Bool {
        organizationRole(for: organization, user: user) == .communityAdmin
    }

    @available(*, unavailable, message: "Load the Organization and use isOrganizationAdmin(_:user:) instead.")
    static func isOrganizationAdmin(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func isOrganizationModerator(_ organization: Organization, user: AppUser?) -> Bool {
        organizationRole(for: organization, user: user) == .communityModerator
    }

    @available(*, unavailable, message: "Load the Organization and use isOrganizationModerator(_:user:) instead.")
    static func isOrganizationModerator(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func canEditOrganizationInfo(_ organization: Organization, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }

        if organization.isSystemOrganization {
            return Self.isOwner(user)
        }

        switch user.globalRole.authorizationRole {
        case .owner:
            return true
        case .admin, .moderator, .user, .topAdmin, .appModerator:
            if organization.submittedByUserId == user.id
                && (organization.moderationStatus == .pendingReview || organization.moderationStatus == .needsRevision) {
                return true
            }
            return isOrganizationOwner(organization, user: user)
                || isOrganizationAdmin(organization, user: user)
        }
    }

    @available(*, unavailable, message: "Load the Organization and use canEditOrganizationInfo(_:user:) instead.")
    static func canEditOrganizationInfo(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func canCreateOrganizationEvent(_ organization: Organization, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }

        if organization.isSystemOrganization {
            return Self.isOwner(user)
        }

        switch user.globalRole.authorizationRole {
        case .owner:
            return true
        case .admin, .moderator, .user, .topAdmin, .appModerator:
            return isOrganizationOwner(organization, user: user)
                || isOrganizationAdmin(organization, user: user)
                || isOrganizationModerator(organization, user: user)
        }
    }

    @available(*, unavailable, message: "Load the Organization and use canCreateOrganizationEvent(_:user:) instead.")
    static func canCreateOrganizationEvent(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func canEditOrganizationEvent(_ organization: Organization, user: AppUser?) -> Bool {
        canCreateOrganizationEvent(organization, user: user)
    }

    @available(*, unavailable, message: "Load the Organization and use canEditOrganizationEvent(_:user:) instead.")
    static func canEditOrganizationEvent(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func canCreateOrganizationNews(_ organization: Organization, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }

        if organization.isSystemOrganization {
            return Self.isOwner(user)
        }

        switch user.globalRole.authorizationRole {
        case .owner:
            return true
        case .admin, .moderator, .user, .topAdmin, .appModerator:
            return isOrganizationOwner(organization, user: user)
                || isOrganizationAdmin(organization, user: user)
                || isOrganizationModerator(organization, user: user)
        }
    }

    @available(*, unavailable, message: "Load the Organization and use canCreateOrganizationNews(_:user:) instead.")
    static func canCreateOrganizationNews(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func canEditOrganizationNews(_ organization: Organization, user: AppUser?) -> Bool {
        canCreateOrganizationNews(organization, user: user)
    }

    @available(*, unavailable, message: "Load the Organization and use canEditOrganizationNews(_:user:) instead.")
    static func canEditOrganizationNews(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func canManageOrganizationRoles(_ organization: Organization, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }
        guard !organization.isSystemOrganization else { return false }

        switch user.globalRole.authorizationRole {
        case .owner:
            return true
        case .admin, .moderator, .user, .topAdmin, .appModerator:
            return isOrganizationOwner(organization, user: user)
        }
    }

    @available(*, unavailable, message: "Load the Organization and use canManageOrganizationRoles(_:user:) instead.")
    static func canManageOrganizationRoles(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    @available(*, unavailable, message: "Load the Organization and use a Cloud Function-backed ownership workflow permission.")
    static func canTransferOrganizationOwnership(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    @available(*, unavailable, message: "Load the Organization and use canManageOrganizationRoles(_:user:) for archive eligibility.")
    static func canArchiveOwnOrganization(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func canModerateOrganizationContent(_ organization: Organization, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }

        if organization.isSystemOrganization {
            return Self.isOwner(user)
        }

        switch user.globalRole.authorizationRole {
        case .owner:
            return true
        case .admin, .moderator, .user, .topAdmin, .appModerator:
            return isOrganizationOwner(organization, user: user)
                || isOrganizationAdmin(organization, user: user)
                || isOrganizationModerator(organization, user: user)
        }
    }

    @available(*, unavailable, message: "Load the Organization and use canModerateOrganizationContent(_:user:) instead.")
    static func canModerateOrganizationContent(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    @available(*, unavailable, message: "Load the Organization and use canModerateOrganizationContent(_:user:) for report review.")
    static func canReviewOrganizationReports(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    @available(*, unavailable, message: "Load the Organization and use canModerateOrganizationContent(_:user:) for comment moderation.")
    static func canModerateOrganizationComments(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    @available(*, unavailable, message: "Load the Organization and use canAccessManagedOrganization(_:user:) or canModerateOrganizationContent(_:user:).")
    static func canManageCommunity(organizationId: String, user: AppUser) -> Bool {
        false
    }

    static func canAccessManagedOrganization(_ organization: Organization, user: AppUser?) -> Bool {
        canModerateOrganizationContent(organization, user: user)
    }

    static func manageableOrganizations(from organizations: [Organization], user: AppUser?) -> [Organization] {
        guard let user else { return [] }
        guard hasUsableAccount(user) else { return [] }

        let eligibleOrganizations = organizations.filter { !$0.isSystemOrganization }
        switch user.globalRole.authorizationRole {
        case .owner:
            return eligibleOrganizations
        case .admin, .moderator, .user, .topAdmin, .appModerator:
            return eligibleOrganizations.filter { canAccessManagedOrganization($0, user: user) }
        }
    }

    @available(*, unavailable, message: "Load organizations and use manageableOrganizations(from:user:) instead.")
    static func manageableOrganizationIDs(user: AppUser?) -> Set<String> {
        []
    }

    static func canAccessOrganizationManagement(user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }
        return Self.isOwner(user)
    }

    static func canManageAppNews(user: AppUser?) -> Bool {
        false
    }

    static func canManageAppEvents(user: AppUser?) -> Bool {
        false
    }

    static func canAccessContentManagement(user: AppUser?) -> Bool {
        canManageAppNews(user: user) || canManageAppEvents(user: user)
    }

    static func canCreateOrganization(user: AppUser?) -> Bool {
        guard let user else { return false }
        return hasUsableAccount(user)
    }

    static func canManageGuide(user: AppUser?) -> Bool {
        isGuideManager(user)
    }

    static func canApproveGuideArticle(user: AppUser?) -> Bool {
        Self.isOwner(user)
    }

    static func canCreateNews(user: AppUser?) -> Bool {
        false
    }

    static func canCreatePlatformNews(user: AppUser?) -> Bool {
        false
    }

    @available(*, unavailable, message: "Load the Organization and use canCreateOrganizationNews(_:user:) instead.")
    static func canCreateNews(for organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func canEditNews(user: AppUser?) -> Bool {
        false
    }

    static func canModerateNews(_ news: NewsPost, user: AppUser?) -> Bool {
        guard let user else { return false }
        if news.source.organizationId != nil {
            return Self.isOwner(user)
        }
        return Self.isOwner(user)
    }

    static func canDeleteNews(user: AppUser?) -> Bool {
        guard let user else { return false }

        switch user.globalRole.authorizationRole {
        case .owner:
            return true
        case .admin, .moderator, .user, .topAdmin, .appModerator:
            return false
        }
    }

    static func canDeleteNews(_ news: NewsPost, user: AppUser?) -> Bool {
        guard let user else { return false }
        if news.source.organizationId != nil {
            return Self.isOwner(user)
        }
        return canDeleteNews(user: user)
    }

    static func canCreateEvent(user: AppUser?) -> Bool {
        false
    }

    @available(*, unavailable, message: "Load the Organization and use canCreateOrganizationEvent(_:user:) instead.")
    static func canCreateEvent(for organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func canEditEvent(user: AppUser?) -> Bool {
        Self.isOwner(user)
    }

    static func canEditEvent(_ event: Event, user: AppUser?) -> Bool {
        guard let user else { return false }
        if event.source.organizationId != nil {
            return Self.isOwner(user)
        }
        return false
    }

    static func canDeleteEvent(user: AppUser?) -> Bool {
        guard let user else { return false }

        switch user.globalRole.authorizationRole {
        case .owner:
            return true
        case .admin, .moderator, .user, .topAdmin, .appModerator:
            return false
        }
    }

    static func canDeleteEvent(_ event: Event, user: AppUser?) -> Bool {
        guard let user else { return false }
        if event.source.organizationId != nil {
            return Self.isOwner(user)
        }
        return false
    }

    static func canModerateEvent(_ event: Event, user: AppUser?) -> Bool {
        guard let user else { return false }
        if event.source.organizationId != nil {
            return Self.isOwner(user)
        }
        return false
    }

    static func canEditOrganization(user: AppUser?) -> Bool {
        Self.isOwner(user)
    }

    static func canEditOrganization(_ organization: Organization, user: AppUser?) -> Bool {
        canEditOrganizationInfo(organization, user: user)
    }

    @available(*, unavailable, message: "Load the Organization and use canEditOrganization(_:user:) instead.")
    static func canEditOrganization(organizationId: String, user: AppUser?) -> Bool {
        false
    }

    static func canDeleteOrganization(_ organization: Organization, user: AppUser?) -> Bool {
        !organization.isSystemOrganization && canDeleteOrganization(user: user)
    }

    static func canDeleteOrganization(user: AppUser?) -> Bool {
        guard let user else { return false }

        switch user.globalRole.authorizationRole {
        case .owner:
            return true
        case .admin, .moderator, .user, .topAdmin, .appModerator:
            return false
        }
    }

    static func canAssignGlobalRoles(user: AppUser) -> Bool {
        isOwner(user) || isAppAdmin(user: user)
    }

    static func canPermanentlyBan(user: AppUser) -> Bool {
        isOwner(user) || isAppAdmin(user: user)
    }

    static func canTemporarilyBan(user: AppUser) -> Bool {
        isOwner(user) || isAppAdmin(user: user)
    }

    static func canAccessAdminTools(user: AppUser?) -> Bool {
        Self.isOwner(user) || isAppAdmin(user: user)
    }

    static func canAccessModerationTools(user: AppUser?) -> Bool {
        Self.isOwner(user) || isAppAdmin(user: user) || isAppModerator(user: user)
    }

    private var isModeratorTier: Bool {
        role == .owner
    }

    private var isAdminTier: Bool {
        role == .owner
    }

    private var isOwner: Bool {
        role == .owner
    }
}
