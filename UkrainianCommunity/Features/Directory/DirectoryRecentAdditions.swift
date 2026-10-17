import Combine
import FirebaseFunctions
import FirebaseSharedSwift
import Foundation

struct DirectoryRecentCursor: Codable, Hashable {
    let seconds: Int
    let nanoseconds: Int
    let id: String
}

struct DirectoryRecentAddition: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case topic, section }
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

    func isAvailable(in topic: DirectoryManagedTopic) -> Bool {
        guard topic.id == topicID, !topic.isHidden else { return false }
        guard kind == .section else { return true }
        guard let sectionID else { return false }
        let sections = federalState.map { topic.regionalSections[$0] ?? [] } ?? topic.sections
        return sections.contains { $0.id == sectionID && !$0.isHidden }
    }
}

struct DirectoryRecentPage: Codable {
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
    private var cursor: DirectoryRecentCursor?
    private var loaded = false
    private var failedReset = true
    private let loader: Loader

    init(loader: Loader? = nil) {
#if DEBUG
        if loader == nil, ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestDirectoryRecentEmpty"] == "1" {
            self.loader = { _ in .init(items: [], nextCursor: nil, hasMore: false) }
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
        guard !loaded else { return }
        await load(reset: true)
    }

    func retry() async { await load(reset: failedReset) }

    func load(reset: Bool) async {
        guard !isLoading, reset || hasMore else { return }
        isLoading = true
        failed = false
        defer { isLoading = false }
        do {
            let page = try await loader(reset ? nil : cursor)
            try Task.checkCancellation()
            var seen = Set<String>()
            items = ((reset ? [] : items) + page.items).filter { seen.insert($0.id).inserted }
            // A broken/non-advancing cursor must not create an endless load-more loop.
            hasMore = page.hasMore && page.nextCursor != nil && (reset || page.nextCursor != cursor)
            cursor = page.nextCursor
            loaded = true
        } catch is CancellationError {
        } catch {
            failedReset = reset
            failed = true
        }
    }
}
