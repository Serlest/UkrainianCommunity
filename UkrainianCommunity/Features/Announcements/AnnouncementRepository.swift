import Foundation
import FirebaseFunctions
import FirebaseAuth

@MainActor
protocol AnnouncementRepository {
    func call(_ endpoint: String, _ request: AnnouncementRequest) async throws -> AnnouncementResponse
    func users(cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?)
    func users(query: String, cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?)
}
extension AnnouncementRepository {
    func users(query: String, cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?) {
        let page = try await users(cursor: cursor)
        return (page.items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || ($0.email?.localizedCaseInsensitiveContains(query) ?? false) }, page.cursor)
    }
}
@MainActor
struct CloudAnnouncementRepository: AnnouncementRepository {
    func call(_ endpoint: String, _ request: AnnouncementRequest) async throws -> AnnouncementResponse {
        let actorID = Auth.auth().currentUser?.uid
        var request = request
        request.principalId = actorID
        let callable: Callable<AnnouncementRequest, AnnouncementResponse> = Functions.functions(region: "europe-west3").httpsCallable(endpoint)
        let response = try await callable.call(request)
        try Task.checkCancellation()
        guard Auth.auth().currentUser?.uid == actorID else { throw CancellationError() }
        return response
    }
    func users(cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?) {
        try await users(query: "", cursor: cursor)
    }
    func users(query: String, cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?) {
        struct Response: Decodable { let items: [AnnouncementUser]; let cursor: String? }
        let callable: Callable<AnnouncementRequest, Response> = Functions.functions(region: "europe-west3").httpsCallable("manageAnnouncements")
        let actorID = Auth.auth().currentUser?.uid
        let result = try await callable.call(AnnouncementRequest(principalId: actorID, query: query, searchVersion: 2, operation: "users", cursor: cursor))
        try Task.checkCancellation()
        guard Auth.auth().currentUser?.uid == actorID else { throw CancellationError() }
        return (result.items, result.cursor)
    }
}
@MainActor
final class MockAnnouncementRepository: AnnouncementRepository {
    var items: [UserAnnouncement] = []
    private var failedOwnerPage = false
    private var lostSaveResponse = false
    private var injectedConflict = false
    private func auditFixture(_ key: String) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-ui-testing") && ProcessInfo.processInfo.environment[key] == "1"
        #else
        false
        #endif
    }
    init() {
        if auditFixture("UITestAnnouncementPages") || auditFixture("UITestAnnouncementConflict") {
            items = (0..<(auditFixture("UITestAnnouncementPages") ? 3 : 1)).map { index in
                var item = UserAnnouncement(); item.id = "page-\(index)"
                item.title = .init(uk: "Перевірка \(index)", de: "Prüfung \(index)")
                item.body = .init(uk: "Контрольний текст", de: "Kontrolltext")
                return item
            }
        }
        if ProcessInfo.processInfo.environment["UITestAnnouncements"] == "1" {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("announcements.receipt.user-1.ui-announcement.") { UserDefaults.standard.removeObject(forKey: key) }
            var value = UserAnnouncement(); value.id = "ui-announcement"; value.status = "published"; value.mode = "acknowledge"
            value.feedback = auditFixture("UITestAnnouncementFeedback")
            value.title = AnnouncementText(uk: "Перевірка оновлення", de: "Update prüfen")
            value.body = AnnouncementText(uk: "Перевірте нову функцію та напишіть нам через звернення.", de: "Bitte prüfen Sie die neue Funktion und senden Sie uns eine Rückmeldung.")
            value.startsAt -= 1000; items = [value]
        }
    }
    func call(_ endpoint: String, _ request: AnnouncementRequest) async throws -> AnnouncementResponse {
        if request.operation == "list", auditFixture("UITestAnnouncementPages") {
            if request.cursor != nil && !failedOwnerPage { failedOwnerPage = true; throw AppError.network }
            let page = request.cursor == nil ? Array(items.prefix(2)) : Array(items.dropFirst(2))
            return AnnouncementResponse(items: page, cursor: request.cursor == nil ? "next" : nil)
        }
        if request.operation == "get" {
            guard let value = items.first(where: { $0.id == request.id }) else { throw AppError.notFound }
            return AnnouncementResponse(item: value)
        }
        if request.operation == "resolveUsers" { return AnnouncementResponse(users: (request.userIds ?? []).map { AnnouncementUser(id: $0, name: "Olena Levytska", region: "wien", email: "olena@example.test", available: true) }) }
        if request.operation == "save", var item = request.draft {
            item.revision += 1
            if auditFixture("UITestAnnouncementConflict") && !injectedConflict {
                injectedConflict = true
                var updated = item
                updated.title = .init(uk: "Збережено на сервері", de: "Auf Server gespeichert")
                items.removeAll { $0.id == item.id }; items.append(updated)
                throw AppError.network
            }
            items.removeAll { $0.id == item.id }; items.append(item)
            if auditFixture("UITestAnnouncementSaveResponseLoss") && !lostSaveResponse {
                lostSaveResponse = true; throw AppError.network
            }
            return AnnouncementResponse(item: item)
        }
        if request.operation == "publish", let i = items.firstIndex(where: { $0.id == request.id }) { items[i].status = "published" }
        if request.operation == "cancel", let i = items.firstIndex(where: { $0.id == request.id }) { items[i].status = "cancelled" }
        if request.operation == "translate" { return AnnouncementResponse(title: request.title, body: request.body) }
        if request.operation == "preview" { return AnnouncementResponse(accounts: 1) }
        return AnnouncementResponse(items: items, serverNow: Date().timeIntervalSince1970 * 1000)
    }
    func users(cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?) { ([AnnouncementUser(id: "recipient-fixture", name: "Olena Levytska", region: "wien", email: "olena@example.test", available: true)], nil) }
}
