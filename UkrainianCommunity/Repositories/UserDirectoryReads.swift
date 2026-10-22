import FirebaseFunctions
import Foundation

nonisolated struct UserDirectoryQuery: Codable, Equatable {
    var search = ""
    var region: String? = nil
    var filter = "all"
    var sort = "newest"
}
struct UserDirectoryPage {
    let users: [AppUser]
    let organizations: [ManagedOrganization]
    let total: Int
    let cursor: String?
}
struct UserOrganizationChoicePage { let organizations: [ManagedOrganization]; let cursor: String? }
nonisolated private struct UserDirectoryRequest: Encodable {
    let action: String
    let principalId: String
    var query: String? = nil
    var region: String? = nil
    var filter: String? = nil
    var sort: String? = nil
    var cursor: String? = nil
    var userId: String? = nil
}
private struct UserDirectoryResponse: Decodable {
    var userIds: [String]? = nil
    var totalMatches: Int? = nil
    var cursor: String? = nil
    var organizations: [ManagedOrganization]? = nil
}
@MainActor enum UserDirectoryAPI {
    private static func call(_ request: UserDirectoryRequest) async throws -> UserDirectoryResponse {
        var callable: Callable<UserDirectoryRequest, UserDirectoryResponse> = Functions.functions(region: "europe-west3").httpsCallable("manageUserDirectory")
        callable.timeoutInterval = 30
        return try await callable.call(request)
    }
    static func page(actor: String, query: UserDirectoryQuery, cursor: String?) async throws -> UserDirectoryPage {
        let response = try await call(UserDirectoryRequest(action: "list", principalId: actor, query: query.search, region: query.region, filter: query.filter, sort: query.sort, cursor: cursor))
        return UserDirectoryPage(users: try await UserManagementReads.fetchUsers(ids: response.userIds ?? []), organizations: response.organizations ?? [], total: response.totalMatches ?? 0, cursor: response.cursor)
    }
    static func organizations(actor: String, search: String, cursor: String?) async throws -> UserOrganizationChoicePage {
        let response = try await call(UserDirectoryRequest(action: "organizations", principalId: actor, query: search, cursor: cursor))
        return UserOrganizationChoicePage(organizations: response.organizations ?? [], cursor: response.cursor)
    }
    static func memberships(actor: String, user: String) async throws -> [ManagedOrganization] {
        try await call(UserDirectoryRequest(action: "memberships", principalId: actor, userId: user)).organizations ?? []
    }
}

@MainActor struct AdminUserMutationJournal {
    struct Entry { let review: AdminMutationReview; let until: Date }
    private var entries: [String: Entry] = [:]
    mutating func request(actor: String, target: AppUser, action: String, reason: String, days: Int = 0, now: Date = .now) -> Entry? {
        guard let revision = target.managementRevision else { return nil }
        let key = [actor, target.id, revision, action, reason.trimmingCharacters(in: .whitespacesAndNewlines), String(days)].joined(separator: "\u{0}")
        if let entry = entries[key] { return entry }
        if entries.count >= 100 { entries.removeAll() }
        let value = Entry(review: AdminMutationReview(operationId: UUID().uuidString, principalId: actor, expectedRevision: revision), until: now.addingTimeInterval(TimeInterval(max(1, days) * 86400)))
        entries[key] = value
        return value
    }
}

enum UserDirectoryCopy {
    static var changed: String { LocalizationStore.language == .german ? "Das Konto oder die Berechtigung wurde geändert. Die Daten wurden aktualisiert. Prüfen Sie sie und bestätigen Sie erneut." : "Акаунт або права змінилися. Дані оновлено. Перевірте їх і підтвердьте дію ще раз." }
}
