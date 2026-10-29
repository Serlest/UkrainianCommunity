import Combine
import FirebaseFunctions
import FirebaseSharedSwift
import Foundation

nonisolated struct DirectoryRecentCursor: Codable, Hashable, Sendable {
    let seconds: Int
    let nanoseconds: Int
    let id: String
}

nonisolated struct DirectoryRecentAddition: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case topic, section }
    let id: String
    let kind: Kind
    let categoryID: String
    let topicID: String
    let sectionID: String?
    let federalState: String?
    let publishedAt: String
    let revision: Int
    let title: DirectoryText
    let topicTitle: DirectoryText
    let categoryTitle: DirectoryText

    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: publishedAt) ?? ISO8601DateFormatter().date(from: publishedAt)
    }

    @MainActor
    func isAvailable(in topic: DirectoryManagedTopic) -> Bool {
        guard topic.id == topicID, !topic.isHidden else { return false }
        guard kind == .section else { return true }
        guard let sectionID else { return false }
        let sections = federalState.map { topic.regionalSections[$0] ?? [] } ?? topic.sections
        return sections.contains { $0.id == sectionID && !$0.isHidden }
    }
}

nonisolated struct DirectoryRecentPage: Codable, Sendable {
    let items: [DirectoryRecentAddition]
    let nextCursor: DirectoryRecentCursor?
    let hasMore: Bool
}

@MainActor
final class DirectoryRecentAdditionsStore: ObservableObject {
    typealias Loader = (DirectoryRecentCursor?) async throws -> DirectoryRecentPage
    @Published private(set) var items: [DirectoryRecentAddition] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published private(set) var hasMore = false
    static let previewLimit = 3
    var previewItems: [DirectoryRecentAddition] { Array(items.prefix(Self.previewLimit)) }
    var hasMoreThanPreview: Bool { items.count > Self.previewLimit || hasMore }

    private var cursor: DirectoryRecentCursor?
    @Published private(set) var hasLoaded = false
    private var failedReset = true
    private let loader: Loader

    init(loader: Loader? = nil) {
#if DEBUG
        if loader == nil, ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestDirectoryRecentEmpty"] == "1" {
            self.loader = { _ in .init(items: [], nextCursor: nil, hasMore: false) }
            return
        }
        if loader == nil, ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestDirectoryRecentPreview"] == "1" {
            self.loader = { _ in
                .init(items: (1...5).map { index in
                    .init(id: "preview-\(index)", kind: .topic, categoryID: "registration",
                          topicID: "housing-types", sectionID: nil, federalState: nil,
                          publishedAt: "2026-10-17T12:00:00.000Z", revision: 1,
                          title: .init(ukrainian: index == 1 ? "Як зареєструвати місце проживання після переїзду в іншу федеральну землю" : "Матеріал \(index)",
                                       german: index == 1 ? "Den Wohnsitz nach einem Umzug in ein anderes Bundesland anmelden" : "Beitrag \(index)"),
                          topicTitle: .init(ukrainian: "Житло", german: "Wohnen"),
                          categoryTitle: .init(ukrainian: "Реєстрація", german: "Registrierung"))
                }, nextCursor: nil, hasMore: false)
            }
            return
        }
#endif
        self.loader = loader ?? { cursor in
            let payload: [String: Any] = ["limit": 20, "cursor": try cursor.map {
                try FirebaseDataEncoder().encode($0)
            } ?? NSNull()]
            let result = try await Functions.functions(region: "europe-west3")
                .httpsCallable("getDirectoryRecentAdditions").call(payload)
            return try FirebaseDataDecoder().decode(DirectoryRecentPage.self, from: result.data)
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load(reset: true)
    }

    func retry() async { await load(reset: failedReset) }

    func load(reset: Bool) async {
        guard !isLoading, reset || hasMore else { return }
        isLoading = true
        failed = false
        defer { isLoading = false }
        do {
            let requestedCursor = reset ? nil : cursor
            let page = try await RefreshRequest.run { [loader] in try await loader(requestedCursor) }
            try Task.checkCancellation()
            var seen = Set<String>()
            items = ((reset ? [] : items) + page.items).filter { seen.insert($0.id).inserted }
            // A broken/non-advancing cursor must not create an endless load-more loop.
            hasMore = page.hasMore && page.nextCursor != nil && (reset || page.nextCursor != cursor)
            cursor = page.nextCursor
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            failedReset = reset
            failed = true
        }
    }
}
