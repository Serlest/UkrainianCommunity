import SwiftUI
import Combine
import FirebaseFunctions

nonisolated struct PublicationControlItem: Decodable, Sendable, Identifiable {
    let id: String
    let kind: String
    let contentId: String
    let titleUK: String
    let titleDE: String
    let region: String
    let firstPublicAt: Double?
    let sourceState: String
    let timingSource: String
    var title: String { LocalizationStore.language == .german ? titleDE : titleUK }
}
nonisolated struct PublicationControlIssue: Decodable, Sendable { let code: String; let detail: String }
nonisolated struct PublicationControlSchedule: Decodable, Sendable {
    let hours: [Int]; let minutes: [Int]; let timeZone: String; let graceMinutes: Int
}
nonisolated struct PublicationControlRun: Decodable, Sendable, Identifiable {
    let id: String
    let kind: String
    let region: String
    let runId: String
    let status: String
    let endedAt: Double?
    let timestampBasis: String
    let published: Int?
    let candidates: Int?
    let rejected: Int?
    let sourcesExpected: Int?
    let sourcesChecked: Int?
    let issues: [PublicationControlIssue]
    let issueCount: Int
    let publicationOnly: Bool
    var lastCompleteAt: Double? = nil
    var scheduledAt: Double? = nil
    var schedule: PublicationControlSchedule? = nil
}
nonisolated struct PublicationControlRegion: Decodable, Sendable, Identifiable {
    let region: String
    let news: Int
    let events: Int
    var id: String { region }
}
nonisolated struct PublicationControlSyncIssue: Decodable, Sendable { let kind: String?; let region: String?; let detail: String? }
nonisolated struct PublicationControlOverview: Decodable, Sendable {
    let day: String
    let serverTime: Double
    let news: Int
    let events: Int
    let regions: [PublicationControlRegion]
    let sources: [PublicationControlRun]
    let syncedAt: Double?
    var syncErrors: Int? = nil
    var legacyTimeCount: Int? = nil
    var lastAttemptAt: Double? = nil
    var lastSuccessfulCheckAt: Double? = nil
    var lastImportedAt: Double? = nil
    var lastReportAt: Double? = nil
    var syncIssues: [PublicationControlSyncIssue]? = nil
}
nonisolated struct PublicationControlItemsPage: Decodable, Sendable { let items: [PublicationControlItem]; let cursor: String?; let total: Int }
nonisolated struct PublicationControlRunsPage: Decodable, Sendable { let runs: [PublicationControlRun]; let cursor: String? }
nonisolated private struct PublicationControlRequest: Encodable {
    let action: String
    let principalId: String
    var day: String? = nil
    var region: String? = nil
    var kind: String? = nil
    var cursor: String? = nil
}
@MainActor struct PublicationControlAPI {
    var overview: (String, String) async throws -> PublicationControlOverview
    var items: (String, String, String?, String?) async throws -> PublicationControlItemsPage
    var runs: (String, String?, String?) async throws -> PublicationControlRunsPage
    private static func call<T: Decodable & Sendable>(_ request: PublicationControlRequest, as: T.Type) async throws -> T {
        var callable: Callable<PublicationControlRequest, T> = Functions.functions(region: "europe-west3").httpsCallable("getPublicationControl")
        callable.timeoutInterval = 30
        return try await callable.call(request)
    }
    static let live = Self(overview: { actor, day in try await call(.init(action: "overview", principalId: actor, day: day), as: PublicationControlOverview.self) },
        items: { actor, day, region, cursor in try await call(.init(action: "items", principalId: actor, day: day, region: region, cursor: cursor), as: PublicationControlItemsPage.self) },
        runs: { actor, region, cursor in try await call(.init(action: "runs", principalId: actor, region: region, cursor: cursor), as: PublicationControlRunsPage.self) })
}
@MainActor final class PublicationControlStore: ObservableObject {
    @Published private(set) var overview: PublicationControlOverview?
    private(set) var receivedAt = Date.now
    @Published private(set) var items: [PublicationControlItem] = []
    @Published private(set) var runs: [PublicationControlRun] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingItems = false
    @Published private(set) var loadingRuns = false
    @Published private(set) var itemCursor: String?
    @Published private(set) var runCursor: String?
    @Published private(set) var error: String?
    @Published private(set) var itemsError: String?
    @Published private(set) var runsError: String?
    private let api: PublicationControlAPI
    private var generation = UUID()
    private var itemGeneration = UUID(), runGeneration = UUID()
    private var actor: String?, day = "", region: String?, runRegion: String?
    @Published private(set) var hasLoadedItems = false
    @Published private(set) var hasLoadedRuns = false
    private var itemRetry: (cursor: String?, append: Bool)?
    private var runRetry: (cursor: String?, append: Bool)?
    private var loadedAt: Date?
    init(api: PublicationControlAPI? = nil) { self.api = api ?? .live }
    func reset() {
        generation = UUID(); itemGeneration = UUID(); runGeneration = UUID(); actor = nil
        overview = nil; items = []; runs = []; itemCursor = nil; runCursor = nil
        loading = false; loadingItems = false; loadingRuns = false; error = nil; itemsError = nil; runsError = nil
        hasLoadedItems = false; hasLoadedRuns = false; itemRetry = nil; runRetry = nil; loadedAt = nil
    }
    func load(actor: String, day: String, force: Bool = true) async {
        if self.actor != actor || self.day != day { reset() }
        guard !loading else { return }
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return }
        self.actor = actor; self.day = day
        let token = generation
        loading = true; error = nil
        itemGeneration = UUID(); runGeneration = UUID(); loadingItems = false; loadingRuns = false
        hasLoadedItems = false; hasLoadedRuns = false; itemRetry = nil; runRetry = nil
        defer { if generation == token { loading = false } }
        do {
            let response = try await RefreshRequest.run { [api] in try await api.overview(actor, day) }
            guard generation == token, !Task.isCancelled else { return }
            receivedAt = .now; loadedAt = .now; overview = response
            // Refresh invalidates the page caches, but a failed refresh never destroys confirmed rows.
            hasLoadedItems = false; hasLoadedRuns = false
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            if !handleAccessFailure(error) { self.error = PublicationControlText.loadFailed }
        }
    }
    /// Access rejection invalidates every retained page, including concurrent reads.
    private func handleAccessFailure(_ error: Error) -> Bool {
        let failure = error as NSError
        guard failure.domain == FunctionsErrorDomain,
              [FunctionsErrorCode.unauthenticated.rawValue, FunctionsErrorCode.permissionDenied.rawValue,
               FunctionsErrorCode.failedPrecondition.rawValue].contains(failure.code) else { return false }
        reset()
        if failure.code == FunctionsErrorCode.permissionDenied.rawValue {
            self.error = PublicationControlText.value("Немає доступу до цього розділу.", "Kein Zugriff auf diesen Bereich.")
        } else {
            self.error = PublicationControlText.value("Поверніться до профілю та виконайте необхідні підтвердження входу й умов.", "Kehren Sie zum Profil zurück und vervollständigen Sie die erforderlichen Anmelde- und Nutzungsbestätigungen.")
        }
        return true
    }
    func reportNow(at date: Date = .now) -> Double {
        guard let overview else { return date.timeIntervalSince1970 * 1000 }
        return overview.serverTime + max(0, date.timeIntervalSince(receivedAt)) * 1000
    }
    func loadItems(region: String?, more: Bool = false) async {
        guard actor != nil else { return }
        if self.region != region {
            itemGeneration = UUID(); loadingItems = false; self.region = region
            items = []; itemCursor = nil; hasLoadedItems = false; itemsError = nil; itemRetry = nil
        }
        guard !loadingItems else { return }
        if !more, let retry = itemRetry { await readItems(cursor: retry.cursor, append: retry.append); return }
        guard more ? itemCursor != nil : !hasLoadedItems else { return }
        await readItems(cursor: more ? itemCursor : nil, append: more)
    }
    private func readItems(cursor: String?, append: Bool) async {
        guard let actor else { return }
        let token = generation, pageToken = itemGeneration, selectedRegion = region
        loadingItems = true; itemsError = nil
        defer { if generation == token, itemGeneration == pageToken { loadingItems = false } }
        do {
            let response = try await RefreshRequest.run { [api, day] in try await api.items(actor, day, selectedRegion, cursor) }
            guard generation == token, itemGeneration == pageToken, !Task.isCancelled else { return }
            var rows = append ? items : []
            for row in response.items where !rows.contains(where: { $0.id == row.id }) { rows.append(row) }
            items = rows; itemCursor = response.cursor; hasLoadedItems = true; itemRetry = nil
        } catch {
            guard generation == token, itemGeneration == pageToken, !Task.isCancelled else { return }
            if handleAccessFailure(error) { return }
            let changed = (error as NSError).domain == FunctionsErrorDomain && (error as NSError).code == FunctionsErrorCode.aborted.rawValue
            itemRetry = changed ? (nil, false) : (cursor, append)
            itemsError = changed ? PublicationControlText.listChanged : PublicationControlText.loadFailed
        }
    }
    func loadRuns(region: String? = nil, more: Bool = false) async {
        guard actor != nil else { return }
        if runRegion != region {
            runGeneration = UUID(); loadingRuns = false; runRegion = region
            runs = []; runCursor = nil; hasLoadedRuns = false; runsError = nil; runRetry = nil
        }
        guard !loadingRuns else { return }
        if !more, let retry = runRetry { await readRuns(cursor: retry.cursor, append: retry.append); return }
        guard more ? runCursor != nil : !hasLoadedRuns else { return }
        await readRuns(cursor: more ? runCursor : nil, append: more)
    }
    private func readRuns(cursor: String?, append: Bool) async {
        guard let actor else { return }
        let token = generation, pageToken = runGeneration, selectedRegion = runRegion
        loadingRuns = true; runsError = nil
        defer { if generation == token, runGeneration == pageToken { loadingRuns = false } }
        do {
            let response = try await RefreshRequest.run { [api] in try await api.runs(actor, selectedRegion, cursor) }
            guard generation == token, runGeneration == pageToken, !Task.isCancelled else { return }
            var rows = append ? runs : []
            for row in response.runs where !rows.contains(where: { $0.id == row.id }) { rows.append(row) }
            runs = rows; runCursor = response.cursor; hasLoadedRuns = true; runRetry = nil
        } catch {
            guard generation == token, runGeneration == pageToken, !Task.isCancelled else { return }
            if handleAccessFailure(error) { return }
            let changed = (error as NSError).domain == FunctionsErrorDomain && (error as NSError).code == FunctionsErrorCode.aborted.rawValue
            runRetry = changed ? (nil, false) : (cursor, append)
            runsError = changed ? PublicationControlText.listChanged : PublicationControlText.loadFailed
        }
    }
}
