import Foundation

struct PermissionService {
    let role: UserRole

    // TODO: UserRole is a legacy app-role source kept for migration-only paths.
    // App-level authorization should use AppUser.globalRole after all users are migrated.

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
        isOwner
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

    private static func isOwner(_ user: AppUser?) -> Bool {
        hasUsableAccount(user) && user?.globalRole.effectiveRole == .owner
    }

    private static func hasUsableAccount(_ user: AppUser?) -> Bool {
        guard let user else { return false }
        return !user.blockState.isRestricted && user.accountStatus != .deactivated
    }

    private static func isGuideManager(_ user: AppUser?) -> Bool {
        guard let user else { return false }
        return isOwner(user) || user.canManageGuide
    }

    static func canModerate(section: AppSection, user: AppUser) -> Bool {
        // App-level moderators and moderatorSections are legacy-only and no longer grant access.
        return user.globalRole.effectiveRole == .owner
    }

    static func moderatedSections(for user: AppUser) -> Set<AppSection> {
        user.globalRole.effectiveRole == .owner
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
    // Use Organization overloads for org-scoped permissions; id-only paths are owner-only.
    static func organizationRole(for organizationId: String, user: AppUser?) -> CommunityRole? {
        nil
    }

    static func isOrganizationOwner(_ organization: Organization, user: AppUser?) -> Bool {
        organizationRole(for: organization, user: user) == .communityOwner
    }

    static func isOrganizationOwner(organizationId: String, user: AppUser?) -> Bool {
        organizationRole(for: organizationId, user: user) == .communityOwner
    }

    static func isOrganizationAdmin(_ organization: Organization, user: AppUser?) -> Bool {
        organizationRole(for: organization, user: user) == .communityAdmin
    }

    static func isOrganizationAdmin(organizationId: String, user: AppUser?) -> Bool {
        organizationRole(for: organizationId, user: user) == .communityAdmin
    }

    static func isOrganizationModerator(_ organization: Organization, user: AppUser?) -> Bool {
        organizationRole(for: organization, user: user) == .communityModerator
    }

    static func isOrganizationModerator(organizationId: String, user: AppUser?) -> Bool {
        organizationRole(for: organizationId, user: user) == .communityModerator
    }

    static func canEditOrganizationInfo(_ organization: Organization, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }

        if organization.isSystemOrganization {
            return Self.isOwner(user)
        }

        switch user.globalRole.effectiveRole {
        case .owner:
            return true
        case .user, .topAdmin, .appModerator:
            return isOrganizationOwner(organization, user: user)
                || isOrganizationAdmin(organization, user: user)
        }
    }

    static func canEditOrganizationInfo(organizationId: String, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }
        return Self.isOwner(user)
    }

    static func canCreateOrganizationEvent(_ organization: Organization, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }

        if organization.isSystemOrganization {
            return Self.isOwner(user)
        }

        switch user.globalRole.effectiveRole {
        case .owner:
            return true
        case .user, .topAdmin, .appModerator:
            return isOrganizationOwner(organization, user: user)
                || isOrganizationAdmin(organization, user: user)
                || isOrganizationModerator(organization, user: user)
        }
    }

    static func canCreateOrganizationEvent(organizationId: String, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }
        return Self.isOwner(user)
    }

    static func canEditOrganizationEvent(_ organization: Organization, user: AppUser?) -> Bool {
        canCreateOrganizationEvent(organization, user: user)
    }

    static func canEditOrganizationEvent(organizationId: String, user: AppUser?) -> Bool {
        canCreateOrganizationEvent(organizationId: organizationId, user: user)
    }

    static func canCreateOrganizationNews(_ organization: Organization, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }

        if organization.isSystemOrganization {
            return Self.isOwner(user)
        }

        switch user.globalRole.effectiveRole {
        case .owner:
            return true
        case .user, .topAdmin, .appModerator:
            return isOrganizationOwner(organization, user: user)
                || isOrganizationAdmin(organization, user: user)
                || isOrganizationModerator(organization, user: user)
        }
    }

    static func canCreateOrganizationNews(organizationId: String, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }
        return Self.isOwner(user)
    }

    static func canEditOrganizationNews(_ organization: Organization, user: AppUser?) -> Bool {
        canCreateOrganizationNews(organization, user: user)
    }

    static func canEditOrganizationNews(organizationId: String, user: AppUser?) -> Bool {
        canCreateOrganizationNews(organizationId: organizationId, user: user)
    }

    static func canManageOrganizationRoles(_ organization: Organization, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }
        guard !organization.isSystemOrganization else { return false }

        switch user.globalRole.effectiveRole {
        case .owner:
            return true
        case .user, .topAdmin, .appModerator:
            return isOrganizationOwner(organization, user: user)
        }
    }

    static func canManageOrganizationRoles(organizationId: String, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }
        guard organizationId != Organization.systemOrganizationID else { return false }
        return Self.isOwner(user)
    }

    static func canTransferOrganizationOwnership(organizationId: String, user: AppUser?) -> Bool {
        guard let user else { return false }
        return hasUsableAccount(user) && user.globalRole.effectiveRole == .owner
    }

    static func canArchiveOwnOrganization(organizationId: String, user: AppUser?) -> Bool {
        canManageOrganizationRoles(organizationId: organizationId, user: user)
    }

    static func canModerateOrganizationContent(_ organization: Organization, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }

        if organization.isSystemOrganization {
            return Self.isOwner(user)
        }

        switch user.globalRole.effectiveRole {
        case .owner:
            return true
        case .user, .topAdmin, .appModerator:
            return isOrganizationOwner(organization, user: user)
                || isOrganizationAdmin(organization, user: user)
                || isOrganizationModerator(organization, user: user)
        }
    }

    static func canModerateOrganizationContent(organizationId: String, user: AppUser?) -> Bool {
        guard let user else { return false }
        guard hasUsableAccount(user) else { return false }
        return Self.isOwner(user)
    }

    static func canReviewOrganizationReports(organizationId: String, user: AppUser?) -> Bool {
        canModerateOrganizationContent(organizationId: organizationId, user: user)
    }

    static func canModerateOrganizationComments(organizationId: String, user: AppUser?) -> Bool {
        canModerateOrganizationContent(organizationId: organizationId, user: user)
    }

    static func canManageCommunity(organizationId: String, user: AppUser) -> Bool {
        canModerateOrganizationContent(organizationId: organizationId, user: user)
    }

    static func canAccessManagedOrganization(_ organization: Organization, user: AppUser?) -> Bool {
        canModerateOrganizationContent(organization, user: user)
    }

    static func manageableOrganizations(from organizations: [Organization], user: AppUser?) -> [Organization] {
        guard let user else { return [] }
        guard hasUsableAccount(user) else { return [] }

        let eligibleOrganizations = organizations.filter { !$0.isSystemOrganization }
        switch user.globalRole.effectiveRole {
        case .owner:
            return eligibleOrganizations
        case .user, .topAdmin, .appModerator:
            return eligibleOrganizations.filter { canAccessManagedOrganization($0, user: user) }
        }
    }

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
        guard let user else { return false }
        return Self.isOwner(user)
    }

    static func canAccessContentManagement(user: AppUser?) -> Bool {
        canManageAppNews(user: user) || canManageAppEvents(user: user)
    }

    static func canCreateOrganization(user: AppUser?) -> Bool {
        guard let user else { return false }
        return user.globalRole.effectiveRole == .owner
    }

    static func canManageGuide(user: AppUser?) -> Bool {
        isGuideManager(user)
    }

    static func canCreateNews(user: AppUser?) -> Bool {
        false
    }

    static func canCreatePlatformNews(user: AppUser?) -> Bool {
        false
    }

    static func canCreateNews(for organizationId: String, user: AppUser?) -> Bool {
        canCreateOrganizationNews(organizationId: organizationId, user: user)
    }

    static func canEditNews(user: AppUser?) -> Bool {
        false
    }

    static func canModerateNews(_ news: NewsPost, user: AppUser?) -> Bool {
        guard let user else { return false }
        if let organizationId = news.source.organizationId {
            return canModerateOrganizationContent(organizationId: organizationId, user: user)
        }
        return Self.isOwner(user)
    }

    static func canDeleteNews(user: AppUser?) -> Bool {
        guard let user else { return false }

        switch user.globalRole.effectiveRole {
        case .owner:
            return true
        case .user, .topAdmin, .appModerator:
            return false
        }
    }

    static func canDeleteNews(_ news: NewsPost, user: AppUser?) -> Bool {
        guard let user else { return false }
        if let organizationId = news.source.organizationId {
            return Self.isOwner(user)
                || isOrganizationOwner(organizationId: organizationId, user: user)
        }
        return canDeleteNews(user: user)
    }

    static func canCreateEvent(user: AppUser?) -> Bool {
        false
    }

    static func canCreateEvent(for organizationId: String, user: AppUser?) -> Bool {
        canCreateEvent(user: user)
            || canCreateOrganizationEvent(organizationId: organizationId, user: user)
    }

    static func canEditEvent(user: AppUser?) -> Bool {
        Self.isOwner(user)
    }

    static func canEditEvent(_ event: Event, user: AppUser?) -> Bool {
        guard let user else { return false }
        if let organizationId = event.source.organizationId {
            return Self.isOwner(user)
                || canEditOrganizationEvent(organizationId: organizationId, user: user)
        }
        return canEditEvent(user: user)
    }

    static func canDeleteEvent(user: AppUser?) -> Bool {
        guard let user else { return false }

        switch user.globalRole.effectiveRole {
        case .owner:
            return true
        case .user, .topAdmin, .appModerator:
            return false
        }
    }

    static func canDeleteEvent(_ event: Event, user: AppUser?) -> Bool {
        guard let user else { return false }
        if let organizationId = event.source.organizationId {
            return Self.isOwner(user)
                || isOrganizationOwner(organizationId: organizationId, user: user)
        }
        return canDeleteEvent(user: user)
    }

    static func canModerateEvent(_ event: Event, user: AppUser?) -> Bool {
        guard let user else { return false }
        if let organizationId = event.source.organizationId {
            return canModerateOrganizationContent(organizationId: organizationId, user: user)
        }
        return Self.isOwner(user)
    }

    static func canEditOrganization(user: AppUser?) -> Bool {
        Self.isOwner(user)
    }

    static func canEditOrganization(_ organization: Organization, user: AppUser?) -> Bool {
        canEditOrganizationInfo(organization, user: user)
    }

    static func canEditOrganization(organizationId: String, user: AppUser?) -> Bool {
        canEditOrganizationInfo(organizationId: organizationId, user: user)
    }

    static func canDeleteOrganization(_ organization: Organization, user: AppUser?) -> Bool {
        !organization.isSystemOrganization && canDeleteOrganization(user: user)
    }

    static func canDeleteOrganization(user: AppUser?) -> Bool {
        guard let user else { return false }

        switch user.globalRole.effectiveRole {
        case .owner:
            return true
        case .user, .topAdmin, .appModerator:
            return false
        }
    }

    static func canAssignGlobalRoles(user: AppUser) -> Bool {
        user.globalRole.effectiveRole == .owner
    }

    static func canPermanentlyBan(user: AppUser) -> Bool {
        user.globalRole.effectiveRole == .owner
    }

    static func canManageHomeBanner(user: AppUser?) -> Bool {
        Self.isOwner(user)
    }

    static func canTemporarilyBan(user: AppUser) -> Bool {
        user.globalRole.effectiveRole == .owner
    }

    static func canAccessAdminTools(user: AppUser?) -> Bool {
        Self.isOwner(user)
    }

    static func canAccessModerationTools(user: AppUser?) -> Bool {
        Self.isOwner(user)
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
