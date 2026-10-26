import Foundation

/// Private analytics live only in memory, for one usable owner session.
/// Reads shared by overview/detail destinations coalesce; failed reads never cache.
@MainActor
final class SessionOwnerAnalyticsRepository: OwnerAnalyticsRepository {
    private enum Value {
        case count(Int), banner(BannerMeasurementReport), overview(OwnerAnalyticsSnapshot)
        case content(AnalyticsContentDetailSnapshot), organization(AnalyticsOrganizationDetailSnapshot)
    }
    private struct Entry { let value: Value; let date: Date }
    private struct Flight { let id: UUID; let task: Task<Value, Error> }
    private let underlying: OwnerAnalyticsRepository
    private let now: () -> Date
    private let ttl: TimeInterval
    private let access: (() -> (AppUser?, AuthSessionState))?
    private var entries: [String: Entry] = [:]
    private var flights: [String: Flight] = [:]
    private var identity: ProfileAccessIdentity?
    private var state: AuthSessionState?
    private var allowed = false
    private var generation = UUID()

    init(underlying: OwnerAnalyticsRepository, ttl: TimeInterval = 60, now: @escaping () -> Date = Date.init,
         access: (() -> (AppUser?, AuthSessionState))? = nil) {
        self.underlying = underlying; self.ttl = ttl; self.now = now; self.access = access
    }

    func updateAccess(user: AppUser?, state: AuthSessionState) {
        let next = ProfileAccessIdentity(user: user)
        let permits = state == .authenticated && PermissionService.isAppOwner(user: user)
        if identity != next || self.state != state || allowed != permits {
            invalidateCachedReads()
            identity = next; self.state = state; allowed = permits
        }
    }

    func invalidateCachedReads() {
        generation = UUID()
        flights.values.forEach { $0.task.cancel() }
        flights.removeAll(); entries.removeAll()
    }

    private func synchronizeAccess() {
        if let access { let (user, state) = access(); updateAccess(user: user, state: state) }
    }

    private func read(_ key: String, utc: Bool = false, load: @escaping () async throws -> Value) async throws -> Value {
        synchronizeAccess()
        guard allowed else { throw AppError.permissionDenied }
        let clock = now()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: utc ? "UTC" : "Europe/Vienna")!
        if let entry = entries[key], clock >= entry.date,
           clock.timeIntervalSince(entry.date) < ttl,
           calendar.isDate(clock, inSameDayAs: entry.date) { return entry.value }
        let epoch = generation
        let flight: Flight
        if let existing = flights[key] { flight = existing }
        else {
            let id = UUID()
            let task = Task { @MainActor in
                defer { if self.flights[key]?.id == id { self.flights[key] = nil } }
                let result = try await load()
                self.synchronizeAccess()
                try Task.checkCancellation()
                guard self.allowed, self.generation == epoch else { throw CancellationError() }
                if self.entries.count >= 48,
                   let oldest = self.entries.min(by: { $0.value.date < $1.value.date }) { self.entries[oldest.key] = nil }
                self.entries[key] = Entry(value: result, date: self.now())
                return result
            }
            flight = Flight(id: id, task: task)
            flights[key] = flight
        }
        let result = try await flight.task.value
        synchronizeAccess()
        try Task.checkCancellation()
        guard allowed, generation == epoch else { throw CancellationError() }
        return result
    }

    var currentAccountCountLoadedAt: Date? { entries["count"]?.date }

    func fetchCurrentAccountCount() async throws -> Int {
        guard case let .count(value) = try await read("count", load: { .count(try await self.underlying.fetchCurrentAccountCount()) }) else { throw AppError.unknown }
        return value
    }
    func fetchBannerOverview(period: AnalyticsPeriod) async throws -> BannerMeasurementReport {
        guard case let .banner(value) = try await read("banner|\(period.rawValue)", utc: true, load: { .banner(try await self.underlying.fetchBannerOverview(period: period)) }) else { throw AppError.unknown }
        return value
    }
    func fetchSnapshot(period: AnalyticsPeriod) async throws -> OwnerAnalyticsSnapshot {
        guard case let .overview(value) = try await read("overview|\(period.rawValue)", load: { .overview(try await self.underlying.fetchSnapshot(period: period)) }) else { throw AppError.unknown }
        return value
    }
    func fetchContentDetail(period: AnalyticsPeriod, contentID: String, contentType: AnalyticsContentType) async throws -> AnalyticsContentDetailSnapshot {
        guard case let .content(value) = try await read("content|\(period.rawValue)|\(contentType.rawValue)|\(contentID)", load: { .content(try await self.underlying.fetchContentDetail(period: period, contentID: contentID, contentType: contentType)) }) else { throw AppError.unknown }
        return value
    }
    func fetchOrganizationDetail(period: AnalyticsPeriod, organizationID: String) async throws -> AnalyticsOrganizationDetailSnapshot {
        guard case let .organization(value) = try await read("organization|\(period.rawValue)|\(organizationID)", load: { .organization(try await self.underlying.fetchOrganizationDetail(period: period, organizationID: organizationID)) }) else { throw AppError.unknown }
        return value
    }
}
