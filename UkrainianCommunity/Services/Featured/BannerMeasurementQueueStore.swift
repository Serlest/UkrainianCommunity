import Foundation

struct BannerMeasurementQueuedEvent: Codable {
    let id: String
    let bannerID: String
    let section: String
    let kind: String
    let occurredAtMilliseconds: Int64
    let consentID: String
    var displayRegion: String? = nil

    init(_ measurement: FeaturedBannerMeasurement, consentID: String) {
        id = measurement.id.uuidString.lowercased()
        bannerID = measurement.bannerID
        section = measurement.section.rawValue
        kind = measurement.kind.rawValue
        occurredAtMilliseconds = Int64(measurement.occurredAt.timeIntervalSince1970 * 1_000)
        self.consentID = consentID
        displayRegion = measurement.displayRegion
    }

    var payload: [String: Any] {
        var result: [String: Any] = ["id": id, "bannerID": bannerID, "section": section, "kind": kind,
         "occurredAtMilliseconds": occurredAtMilliseconds, "consentID": consentID]
        if let displayRegion { result["displayRegion"] = displayRegion }
        return result
    }
}

/// Small, account-bound outbox. The server receipt makes retrying one ID safe.
@MainActor
final class BannerMeasurementQueueStore {
    private static let queueKey = "bannerMeasurementQueue.v1"
    private static let ownerKey = "bannerMeasurementQueueOwner.v1"
    private static let maximumCount = 500
    private static let maximumAge: TimeInterval = 48 * 60 * 60

    private let defaults: UserDefaults
    private var principalID: String?
    private var events: [BannerMeasurementQueuedEvent] = []

    init(defaults: UserDefaults, principalID: String?, loadExisting: Bool = true) {
        self.defaults = defaults
        self.principalID = principalID
        if loadExisting { load() }
    }

    var first: BannerMeasurementQueuedEvent? { events.first }

    func append(_ event: BannerMeasurementQueuedEvent) {
        prune()
        guard principalID != nil, events.count < Self.maximumCount else { return }
        events.append(event)
        persist()
    }

    func removeFirst() {
        guard !events.isEmpty else { return }
        events.removeFirst()
        persist()
    }

    func removeAll() {
        events.removeAll()
        persist()
    }

    func switchPrincipal(to principalID: String?) {
        guard self.principalID != principalID else { return }
        events.removeAll()
        self.principalID = principalID
        persist()
    }

    func prune() {
        let cutoff = Int64(Date().addingTimeInterval(-Self.maximumAge).timeIntervalSince1970 * 1_000)
        events.removeAll { $0.occurredAtMilliseconds < cutoff }
        if events.count > Self.maximumCount { events = Array(events.suffix(Self.maximumCount)) }
        persist()
    }

    private func load() {
        guard let principalID,
              defaults.string(forKey: Self.ownerKey) == principalID,
              let data = defaults.data(forKey: Self.queueKey),
              let decoded = try? JSONDecoder().decode([BannerMeasurementQueuedEvent].self, from: data) else {
            persist()
            return
        }
        events = decoded
        prune()
    }

    private func persist() {
        guard let principalID, !events.isEmpty,
              let data = try? JSONEncoder().encode(events) else {
            defaults.removeObject(forKey: Self.queueKey)
            defaults.removeObject(forKey: Self.ownerKey)
            return
        }
        defaults.set(data, forKey: Self.queueKey)
        defaults.set(principalID, forKey: Self.ownerKey)
    }
}
