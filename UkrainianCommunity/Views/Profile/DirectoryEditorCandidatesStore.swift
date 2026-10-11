import Combine
import FirebaseFirestore

/// User lookup for the directory grant screen. It avoids loading organization
/// roles and security metadata needed by the broader user-management screen.
@MainActor
final class DirectoryEditorCandidatesStore: ObservableObject {
    @Published private(set) var users: [AppUser] = []
    @Published private(set) var searchResults: [AppUser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isSearching = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var searchFailed = false
    @Published private(set) var loadFailed = false

    private let pageSize = 40
    private let reads = UserManagementReads.live
    private var lastDocument: QueryDocumentSnapshot?
    private var searchGeneration = 0

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let page = try await reads.users(pageSize)
            guard !Task.isCancelled else { return }
            users = page.users
            lastDocument = page.cursor
            canLoadMore = page.hasMore
        } catch {
            loadFailed = true
        }
    }

    func loadMore() async {
        guard !isLoadingMore, canLoadMore, let lastDocument else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let snapshot = try await Firestore.firestore().collection("users")
                .order(by: "createdAt", descending: true)
                .start(afterDocument: lastDocument)
                .limit(to: pageSize)
                .getDocuments(source: .server)
            guard !Task.isCancelled else { return }
            let known = Set(users.map(\.id))
            users.append(contentsOf: snapshot.documents
                .map(UserManagementViewModel.makeUser(from:))
                .filter { !known.contains($0.id) })
            self.lastDocument = snapshot.documents.last
            canLoadMore = snapshot.documents.count == pageSize
        } catch {
            loadFailed = true
        }
    }

    func search(_ query: String) async {
        searchGeneration &+= 1
        let generation = searchGeneration
        isSearching = true
        searchFailed = false
        defer { if generation == searchGeneration { isSearching = false } }
        do {
            let result = try await reads.search(query)
            guard generation == searchGeneration, !Task.isCancelled else { return }
            searchResults = result.users
        } catch {
            guard generation == searchGeneration, !Task.isCancelled else { return }
            searchResults = []
            searchFailed = true
        }
    }

    func clearSearch() {
        searchGeneration &+= 1
        isSearching = false
        searchResults = []
        searchFailed = false
    }
}
