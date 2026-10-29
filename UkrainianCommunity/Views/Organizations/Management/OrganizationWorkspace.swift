import Combine
import Foundation
import FirebaseFunctions
import SwiftUI

nonisolated struct OrganizationWorkspaceRequest: Codable, Equatable {
    let action: String
    let principalId: String
    var organizationId: String? = nil
    var cursor: String? = nil
    var search: String? = nil
    var region: String? = nil
    var contentType: String? = nil
    var status: String? = nil
    var transfer: Bool? = nil
    var language: String? = nil
}
nonisolated struct OrganizationWorkspaceContent: Codable, Identifiable {
    let id: String
    let title: String
    let status: ModerationStatus
    let reason: String
}
nonisolated struct OrganizationWorkspaceUser: Codable, Identifiable {
    let id: String
    let displayName: String
    let city: String
    let federalState: String?
    let avatarURL: String?
}
nonisolated struct OrganizationWorkspaceResponse: Codable {
    var ids: [String]? = nil
    var cursor: String? = nil
    var counts: [String: Int]? = nil
    var items: [OrganizationWorkspaceContent]? = nil
    var users: [OrganizationWorkspaceUser]? = nil
}
struct ManagedOrganizationQuery: Equatable {
    let actor: AppUser
    var search = ""
    var organizationID: String? = nil
    var region: AustrianFederalState? = nil
    static func == (lhs: Self, rhs: Self) -> Bool { ProfileAccessIdentity(user: lhs.actor) == ProfileAccessIdentity(user: rhs.actor) && lhs.search == rhs.search && lhs.region == rhs.region && lhs.organizationID == rhs.organizationID }
}
struct ManagedOrganizationPage { let items: [Organization]; let cursor: String? }

@MainActor final class OrganizationManagementListModel: ObservableObject {
    @Published private(set) var organizations: [Organization] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var hasMore = false
    private var cursor: String?
    private var generation = UUID()
    private var query: ManagedOrganizationQuery?
    @Published private(set) var hasLoaded = false
    private let fetch: (ManagedOrganizationQuery, String?) async throws -> ManagedOrganizationPage
    init(repository: OrganizationRepository, fetch: ((ManagedOrganizationQuery, String?) async throws -> ManagedOrganizationPage)? = nil) {
        self.fetch = fetch ?? { try await repository.fetchManagedOrganizationPage(query: $0, after: $1) }
    }
    func reset() { generation = UUID(); query = nil; organizations = []; cursor = nil; hasMore = false; isLoading = false; error = nil; hasLoaded = false }
    func loadIfNeeded(actor: AppUser?, search: String, region: AustrianFederalState?, organizationID: String? = nil) async {
        guard let actor, PermissionService.isUsableAccount(user: actor) else { reset(); return }
        let next = ManagedOrganizationQuery(actor: actor, search: search, organizationID: organizationID, region: region)
        guard next != query || (!hasLoaded && !isLoading) else { return }
        await load(actor: actor, search: search, region: region, organizationID: organizationID)
    }
    func load(actor: AppUser?, search: String, region: AustrianFederalState?, more: Bool = false, organizationID: String? = nil) async {
        guard let actor, PermissionService.isUsableAccount(user: actor) else { reset(); return }
        let next = ManagedOrganizationQuery(actor: actor, search: search, organizationID: organizationID, region: region)
        if more { guard next == query, hasMore, !isLoading else { return } }
        else {
            if next == query && isLoading { return }
            generation = UUID(); cursor = nil; hasMore = false
            if next != query { organizations = []; hasLoaded = false }; query = next
        }
        let expected = generation; isLoading = true; error = nil
        defer { if generation == expected { isLoading = false } }
        do {
            let requestedCursor = more ? cursor : nil
            let page = try await RefreshRequest.run { [fetch] in try await fetch(next, requestedCursor) }
            guard generation == expected, !Task.isCancelled else { return }
            var byID = Dictionary(uniqueKeysWithValues: (more ? organizations : []).map { ($0.id, $0) })
            page.items.forEach { byID[$0.id] = $0 }
            organizations = byID.values.sorted { $0.id < $1.id }; cursor = page.cursor; hasMore = page.cursor != nil; hasLoaded = true
        } catch { if generation == expected, !Task.isCancelled { self.error = (error as? AppError) ?? FirebaseReadErrorMapper.map(error) } }
    }
}

enum OrganizationWorkspaceCopy {
    private static func value(_ uk: String, _ de: String) -> String { LocalizationStore.language == .german ? de : uk }
    static var editSubtitle: String { value("Оновіть дані організації та збережіть зміни.", "Angaben der Organisation aktualisieren und Änderungen sichern.") }
    static var discardTitle: String { value("Відхилити зміни?", "Änderungen verwerfen?") }
    static var discardMessage: String { value("Зміни в організації ще не збережено.", "Die Änderungen an der Organisation sind noch nicht gespeichert.") }
    static var search: String { value("Пошук за назвою або містом", "Name oder Ort suchen") }
    static var allRegions: String { value("Усі землі", "Alle Bundesländer") }
    static var platformOwner: String { value("Власник застосунку", "App-Inhaber") }
    static var createSubtitle: String { value("Додайте організацію та заповніть її профіль.", "Organisation hinzufügen und ihr Profil ausfüllen.") }
    static var allStatuses: String { value("Матеріали в усіх статусах", "Beiträge in allen Status") }
    static var subscribers: String { value("Підписники", "Abonnenten") }
    static var subscribersHelper: String { value("Підписники відображаються окремо від команди організації.", "Abonnenten werden getrennt vom Organisationsteam angezeigt.") }
    static var teamHelper: String { value("Власник, адміністратори та модератори організації.", "Inhaber, Administratoren und Moderatoren der Organisation.") }
    static var contentHelper: String { value("Переглядайте та редагуйте матеріали організації за статусом.", "Beiträge der Organisation nach Status ansehen und bearbeiten.") }
    static var all: String { value("Усі", "Alle") }
    static var candidateHelper: String { value("Знайдіть користувача, якому потрібно надати доступ.", "Suchen Sie die Person, der Sie Zugriff geben möchten.") }
    static var conflict: String { value("Дані або роль змінилися. Оновіть організацію та підтвердьте дію ще раз.", "Daten oder Rolle wurden geändert. Organisation aktualisieren und erneut bestätigen.") }
    static var noMatches: String { value("Нічого не знайдено. Змініть пошук або фільтр.", "Keine Treffer. Suche oder Filter ändern.") }
}
