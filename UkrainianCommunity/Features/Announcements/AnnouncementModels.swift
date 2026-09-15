import Foundation

nonisolated struct AnnouncementText: Codable, Equatable, Hashable, Sendable {
    var uk = ""
    var de = ""
    @MainActor func localized(_ language: AppLanguage = .stored) -> String { language == .ukrainian ? uk : de }
}
nonisolated struct UserAnnouncement: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id = UUID().uuidString
    var schemaVersion = 1
    var revision = 0
    var title = AnnouncementText()
    var body = AnnouncementText()
    var groups = ["registered"]
    var userIds: [String] = []
    var regions: [String] = []
    var targetPlatforms = ["ios"]
    var mode = "once"
    var feedback = false
    var push = false
    var startsAt = (Date().timeIntervalSince1970 * 1000).rounded()
    var expiresAt = (Date().addingTimeInterval(7 * 86400).timeIntervalSince1970 * 1000).rounded()
    var status = "draft"
    var presentedAt: Double?
    var acknowledgedAt: Double?

    enum CodingKeys: String, CodingKey { case id, schemaVersion, revision, title, body, groups, userIds, regions, targetPlatforms, mode, feedback, push, startsAt, expiresAt, status, presentedAt, acknowledgedAt }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        revision = try c.decode(Int.self, forKey: .revision)
        title = try c.decode(AnnouncementText.self, forKey: .title)
        body = try c.decode(AnnouncementText.self, forKey: .body)
        mode = try c.decode(String.self, forKey: .mode)
        feedback = try c.decode(Bool.self, forKey: .feedback)
        startsAt = try c.decode(Double.self, forKey: .startsAt)
        expiresAt = try c.decode(Double.self, forKey: .expiresAt)
        groups = try c.decodeIfPresent([String].self, forKey: .groups) ?? []
        userIds = try c.decodeIfPresent([String].self, forKey: .userIds) ?? []
        regions = try c.decodeIfPresent([String].self, forKey: .regions) ?? []
        targetPlatforms = try c.decodeIfPresent([String].self, forKey: .targetPlatforms) ?? ["ios"]
        push = try c.decodeIfPresent(Bool.self, forKey: .push) ?? false
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "published"
        presentedAt = try c.decodeIfPresent(Double.self, forKey: .presentedAt)
        acknowledgedAt = try c.decodeIfPresent(Double.self, forKey: .acknowledgedAt)
    }
    func active(at milliseconds: Double) -> Bool {
        schemaVersion == 1 && ["once", "acknowledge"].contains(mode) && status == "published" && startsAt <= milliseconds && expiresAt > milliseconds
    }
    var canPublish: Bool {
        [title.uk, title.de, body.uk, body.de].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        && title.uk.count <= 160 && title.de.count <= 160 && body.uk.count <= 6000 && body.de.count <= 6000
        && (!groups.isEmpty || !userIds.isEmpty) && expiresAt > max(startsAt, (Date().timeIntervalSince1970 * 1000).rounded())
    }
}
struct AnnouncementUser: Codable, Identifiable { let id: String; let name: String; let region: String? }
nonisolated struct AnnouncementRequest: Encodable {
    var operation: String?
    var platform = "ios"
    var capability = 1
    var id: String?
    var revision: Int?
    var draft: UserAnnouncement?
    var cursor: String?
    var event: String?
    var language: String?
    var source: String?
    var title: String?
    var body: String?
    var secret: String?
    var fid: String?
    var challenge: String?
}
struct AnnouncementResponse: Decodable {
    var items: [UserAnnouncement]?
    var item: UserAnnouncement?
    var cursor: String?
    var serverNow: Double?
    var accounts: Int?
    var title: String?
    var body: String?
    var presented: Int?
    var acknowledged: Int?
    var action: Int?
    var pushState: String?
    var pushSuccess: Int?
    var pushFailure: Int?
    var guestPresented: Int?
    var guestAcknowledged: Int?
}

struct AnnouncementPresentationPolicy {
    private(set) var seenThisSession: Set<String> = []
    private var backgroundAt: Date?
    mutating func background(at date: Date) { backgroundAt = date }
    mutating func foreground(at date: Date) {
        if let backgroundAt, date.timeIntervalSince(backgroundAt) >= 1800 { seenThisSession = [] }
        backgroundAt = nil
    }
    mutating func shown(_ id: String) { seenThisSession.insert(id) }
    func eligible(_ item: UserAnnouncement, now: Double, locallyPresented: Bool, locallyAcknowledged: Bool) -> Bool {
        item.active(at: now) && !seenThisSession.contains(item.id) &&
        (item.mode == "once" ? item.presentedAt == nil && !locallyPresented : item.acknowledgedAt == nil && !locallyAcknowledged)
    }
}
