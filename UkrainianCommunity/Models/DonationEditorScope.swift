import Foundation

struct DonationEditorScope: Hashable {
    let identity: ProfileAccessIdentity
    let authorizationRevision: Int
    let allowsOwner: Bool

    @MainActor init(_ auth: AuthState) {
        identity = ProfileAccessIdentity(user: auth.user)
        authorizationRevision = auth.authorizationRevision
        allowsOwner = auth.isAuthenticated && PermissionService.isAppOwner(user: auth.user)
    }
}

struct DonationEditorCommand {
    let config: DonationConfig
    let scope: DonationEditorScope
}
