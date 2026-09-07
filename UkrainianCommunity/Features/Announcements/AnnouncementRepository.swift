import Foundation
import FirebaseFunctions

@MainActor
protocol AnnouncementRepository {
    func call(_ endpoint: String, _ request: AnnouncementRequest) async throws -> AnnouncementResponse
    func users(cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?)
}
@MainActor
struct CloudAnnouncementRepository: AnnouncementRepository {
    func call(_ endpoint: String, _ request: AnnouncementRequest) async throws -> AnnouncementResponse {
        let callable: Callable<AnnouncementRequest, AnnouncementResponse> = Functions.functions(region: "europe-west3").httpsCallable(endpoint)
        return try await callable.call(request)
    }
    func users(cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?) {
        struct Response: Decodable { let items: [AnnouncementUser]; let cursor: String? }
        let callable: Callable<AnnouncementRequest, Response> = Functions.functions(region: "europe-west3").httpsCallable("manageAnnouncements")
        let result = try await callable.call(AnnouncementRequest(operation: "users", cursor: cursor))
        return (result.items, result.cursor)
    }
}
@MainActor
final class MockAnnouncementRepository: AnnouncementRepository {
    var items: [UserAnnouncement] = []
    init() {
        if ProcessInfo.processInfo.environment["UITestAnnouncements"] == "1" {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("announcements.receipt.guest.ui-announcement.") { UserDefaults.standard.removeObject(forKey: key) }
            var value = UserAnnouncement(); value.id = "ui-announcement"; value.status = "published"; value.mode = "acknowledge"
            value.title = AnnouncementText(uk: "Перевірка оновлення", de: "Update prüfen")
            value.body = AnnouncementText(uk: "Перевірте нову функцію та напишіть нам через звернення.", de: "Bitte prüfen Sie die neue Funktion und senden Sie uns eine Rückmeldung.")
            value.startsAt -= 1000; items = [value]
        }
    }
    func call(_ endpoint: String, _ request: AnnouncementRequest) async throws -> AnnouncementResponse {
        if request.operation == "save", var item = request.draft {
            item.revision += 1
            items.removeAll { $0.id == item.id }; items.append(item)
            return AnnouncementResponse(item: item)
        }
        if request.operation == "publish", let i = items.firstIndex(where: { $0.id == request.id }) { items[i].status = "published" }
        if request.operation == "cancel", let i = items.firstIndex(where: { $0.id == request.id }) { items[i].status = "cancelled" }
        if request.operation == "translate" { return AnnouncementResponse(title: request.title, body: request.body) }
        if request.operation == "preview" { return AnnouncementResponse(accounts: 1) }
        return AnnouncementResponse(items: items, serverNow: Date().timeIntervalSince1970 * 1000)
    }
    func users(cursor: String?) async throws -> (items: [AnnouncementUser], cursor: String?) { ([], nil) }
}
