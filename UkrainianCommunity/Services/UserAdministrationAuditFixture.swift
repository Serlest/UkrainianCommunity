import Foundation
import FirebaseFirestore

@MainActor enum UserAdministrationAuditFixture {
    static func makeIfRequested() -> UserManagementReads? {
#if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.environment["UITestUserAdministrationAudit"] == "1" else { return nil }
        let state = State()
        return UserManagementReads(users: { _ in .init(users: [], cursor: nil, hasMore: false) },
            user: { id in
                try await state.delay()
                if state.mode == "deleted" { return nil }
                if state.mode == "detail-error", state.fail("detail") { throw AppError.network }
                return state.users.first { $0.id == id }
            }, organizations: { state.organizations }, securityMetadata: { id in
                .init(response: .init(targetUserId: id, emailVerified: true, authDisabled: false,
                    creationTime: nil, lastSignInTime: "2026-10-20T08:30:00.000Z", providerIds: ["password", "apple.com", "google.com"]))
            }, presence: { id in
                let now = Date().timeIntervalSince1970 * 1000
                return .init(response: .init(targetUserId: id, lastSeenAt: now - 900_000,
                    onlineUntil: state.mode == "offline" ? nil : now + 180_000, serverTime: now), requestStartedAt: .now)
            }, auditHistory: { _, cursor in
                if state.mode == "history-error", state.fail("history") { throw AppError.network }
                if state.mode == "history-page-error", cursor != nil, state.fail("history-page") { throw AppError.network }
                let start = cursor.map { Int($0.id) ?? 0 } ?? 0
                let end = min(start + 20, 45)
                let items = (start..<end).map { index in
                    ManagedUserAuditItem(id: "audit-\(index)", actionType: index.isMultiple(of: 2) ? "userWarned" : "userSuspensionExpired",
                        reason: "Перевірено повідомлення користувача / Nutzerhinweis geprüft · \(index)", performedBy: "Serlest",
                        previousValue: ["accountStatus": "active"], newValue: ["accountStatus": "warned"], createdAt: .now.addingTimeInterval(-Double(index * 60)))
                }
                return .init(items: items, cursor: end < 45 ? .init(seconds: 1, nanoseconds: 0, id: String(end)) : nil, hasMore: end < 45)
            }, directory: { actor, query, cursor in
                try await state.delay()
                if query.search == "error" || state.mode == "directory-error" && state.fail("directory") { throw AppError.network }
                let matches = state.filtered(query)
                let start = cursor.flatMap(Int.init) ?? 0, end = min(start + 40, matches.count)
                return .init(users: Array(matches[start..<end]), organizations: state.organizations,
                    total: matches.count, cursor: end < matches.count ? String(end) : nil)
            }, organizationPage: { actor, search, cursor in
                try await state.delay()
                let matches = state.organizations.filter {
                    ($0.ownerId == actor || actor == "owner-1") && LocalSearchMatcher.matches(query: search, values: [$0.name, $0.city, $0.id])
                }
                let start = cursor.flatMap(Int.init) ?? 0, end = min(start + 30, matches.count)
                return .init(organizations: Array(matches[start..<end]), cursor: end < matches.count ? String(end) : nil)
            }, memberships: { _, userID in state.organizations.filter { $0.role(for: userID) != nil } },
            totalCount: { state.users.count })
#else
        return nil
#endif
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor private final class State {
    let mode = ProcessInfo.processInfo.environment["UITestUserAdministrationState"] ?? "normal"
    private var failures = Set<String>()
    func fail(_ key: String) -> Bool { failures.insert(key).inserted }
    func delay() async throws {
        if mode == "slow" { try await Task.sleep(for: .seconds(3)) }
    }
    let users: [AppUser]
    let organizations: [ManagedOrganization]
    init() {
        var values: [AppUser] = []
        let special = [("audit-member", "active", "user"), ("audit-warned", "warned", "user"),
                       ("audit-suspended", "suspendedUntil", "user"), ("audit-banned", "bannedPermanent", "user"),
                       ("audit-deactivated", "deactivated", "user"), ("audit-app-admin", "active", "admin"),
                       ("owner-1", "active", "owner"), ("admin-1", "active", "admin")]
        for (i, entry) in special.enumerated() {
            values.append(UserManagementViewModel.makeUser(id: entry.0, data: [
                "displayName": entry.0 == "audit-member" ? "Олена Марія Коваль — координаторка громади та підтримки новоприбулих українців" : entry.0,
                "email": "community.coordinator.with.a.long.address@example.test", "globalRole": entry.2,
                "accountStatus": entry.1, "blockState": entry.1, "selectedFederalState": "tirol", "city": "Innsbruck",
                "createdAt": Timestamp(date: Date().addingTimeInterval(-Double(i * 3600)))
            ]))
        }
        for i in 0..<137 {
            values.append(UserManagementViewModel.makeUser(id: "audit-extra-\(i)", data: ["displayName": "Користувач / Nutzer \(i)",
                "email": "user\(i)@example.test", "globalRole": "user", "accountStatus": "active", "city": "Wien",
                "selectedFederalState": i.isMultiple(of: 2) ? "wien" : "tirol", "createdAt": Timestamp(date: Date().addingTimeInterval(-Double((i+10)*3600)))]))
        }
        users = values
        organizations = (0..<35).map { i in .init(id: "audit-org-\(i)", name: "Українська організація підтримки та розвитку громади / Organisation \(i)",
            city: "Innsbruck", logoURL: nil, ownerId: i == 1 ? "admin-1" : "owner-1", adminIds: i < 2 ? ["audit-member"] : [], moderatorIds: [], accessRevision: "1:0", moderationStatus: .approved) }
    }
    func filtered(_ query: UserDirectoryQuery) -> [AppUser] {
        users.filter { user in
            let state = user.managedAccountState
            let statusMatches: Bool = switch query.filter {
            case "all": true
            case "active": state == .active
            case "warned": state == .warned
            case "suspended": state == .suspendedUntil || state == .blocked
            case "banned": state == .bannedPermanent
            case "deactivated": state == .deactivated
            case "organizationOwners": organizations.contains { $0.ownerId == user.id }
            case "organizationAdmins": organizations.contains { $0.adminIds.contains(user.id) && $0.ownerId != user.id }
            case "organizationModerators": organizations.contains { $0.moderatorIds.contains(user.id) && !$0.adminIds.contains(user.id) && $0.ownerId != user.id }
            default: false
            }
            return statusMatches && (query.region == nil || query.region == user.selectedFederalState?.rawValue)
                && LocalSearchMatcher.matches(query: query.search, values: [user.id, user.displayName, user.email])
        }.sorted { a, b in
            switch query.sort {
            case "nameAscending": a.preferredDisplayName < b.preferredDisplayName
            case "nameDescending": a.preferredDisplayName > b.preferredDisplayName
            case "oldest": a.createdAt == b.createdAt ? a.id < b.id : a.createdAt < b.createdAt
            default: a.createdAt == b.createdAt ? a.id < b.id : a.createdAt > b.createdAt
            }
        }
    }
}
#endif
