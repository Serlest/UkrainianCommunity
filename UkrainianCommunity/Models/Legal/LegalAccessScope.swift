import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// Profile refreshes do not change authority; re-authentication to the same UID does.
struct LegalAccessScope: Hashable {
    let identity: ProfileAccessIdentity
    let authorizationRevision: Int
    let authenticated: Bool
    let allowsOwner: Bool

    @MainActor init(_ auth: AuthState) {
        identity = ProfileAccessIdentity(user: auth.user)
        authorizationRevision = auth.authorizationRevision
        authenticated = auth.isAuthenticated
        allowsOwner = auth.isAuthenticated && PermissionService.isAppOwner(user: auth.user)
    }
}

struct LegalQueryScope: Hashable {
    let access: LegalAccessScope
    let query: String
    let acknowledgements: String
    @MainActor init(_ auth: AuthState, query: String) {
        access = LegalAccessScope(auth); self.query = query
        acknowledgements = [auth.user?.acceptedTermsVersion ?? "", auth.user?.acceptedPrivacyVersion ?? ""].joined(separator: "|")
    }
}

enum LegalReadFailure: Equatable {
    case session, denied, missing, network, service, other
    var withdrawsPrivateData: Bool { self == .session || self == .denied || self == .missing }
    init(_ error: Error) {
        if let app = error as? AppError {
            switch app {
            case .permissionDenied: self = .denied
            case .notFound: self = .missing
            case .network: self = .network
            default: self = .other
            }
            return
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { self = .network; return }
        guard [FunctionsErrorDomain, "FirebaseFunctions", FirestoreErrorDomain].contains(ns.domain) else { self = .other; return }
        switch ns.code {
        case 16: self = .session
        case 7: self = .denied
        case 5: self = .missing
        case 4, 8, 10, 14: self = .service
        default: self = .other
        }
    }
}
