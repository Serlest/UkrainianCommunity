import SwiftUI
import Combine

@MainActor
final class AnnouncementRecipientSearch: ObservableObject {
    @Published private(set) var items: [AnnouncementUser] = []
    @Published private(set) var cursor: String?
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    @Published private(set) var failedMore = false
    private var generation = 0
    private var query = ""
    let repository: any AnnouncementRepository
    init(repository: any AnnouncementRepository) { self.repository = repository }
    private func readPage(query: String, after: String?) async throws -> (items: [AnnouncementUser], cursor: String?) {
        try await RefreshRequest.run { [repository] in
            var requested = after
            var seen = Set<String>()
            if let after { seen.insert(after) }
            for index in 0..<4 {
                try Task.checkCancellation()
                let page = try await repository.users(query: query, cursor: requested)
                if let next = page.cursor, !seen.insert(next).inserted { throw AnnouncementCommandError.missingResponse }
                if !page.items.isEmpty || page.cursor == nil || index == 3 { return page }
                requested = page.cursor
            }
            throw AnnouncementCommandError.missingResponse
        }
    }
    func search(_ text: String) async {
        generation += 1; let version = generation
        query = text; items = []; cursor = nil; error = nil; loading = true
        failedMore = false
        defer { if generation == version { loading = false } }
        do {
            try await Task.sleep(for: .milliseconds(300))
            let page = try await readPage(query: text, after: nil)
            guard generation == version, !Task.isCancelled else { return }
            items = page.items; cursor = page.cursor
        } catch { if generation == version, !Task.isCancelled { self.error = AnnouncementErrorPresentation.message(error) } }
    }
    func more() async {
        guard !loading, let cursor else { return }
        let version = generation; loading = true
        defer { if generation == version { loading = false } }
        do {
            let page = try await readPage(query: query, after: cursor)
            guard generation == version, !Task.isCancelled else { return }
            var seen = Set(items.map(\.id))
            items += page.items.filter { seen.insert($0.id).inserted }; self.cursor = page.cursor; error = nil
            failedMore = false
        } catch { if generation == version, !Task.isCancelled { failedMore = true; self.error = AnnouncementErrorPresentation.message(error) } }
    }
    func retry() async { if failedMore { await more() } else { await search(query) } }
}

struct AnnouncementUserPicker: View {
    let repository: any AnnouncementRepository
    @Binding private var destination: [String]
    @State private var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search: AnnouncementRecipientSearch
    @State private var query = ""
    @State private var known: [String: AnnouncementUser] = [:]
    @State private var resolutionError: String?
    init(repository: any AnnouncementRepository, selected: Binding<[String]>) {
        self.repository = repository; _destination = selected; _selected = State(initialValue: selected.wrappedValue)
        _search = StateObject(wrappedValue: AnnouncementRecipientSearch(repository: repository))
    }
    var body: some View {
        EditorScreenShell(title: AnnouncementStrings.people, closeStyle: .cancel, trailingContent: {
            Button(AnnouncementManagementText.value("done")) { destination = selected; dismiss() }
                .accessibilityIdentifier("announcements.peopleDone")
        }, bottomAction: { EmptyView() }) {
            AppSearchField(placeholder: AnnouncementManagementText.value("search"), text: $query,
                fieldID: "announcements.recipientSearch", isSearching: search.loading)
            Text("\(AnnouncementManagementText.value("selected")): \(selected.count)/100").font(.headline).accessibilityIdentifier("announcements.selectionCount")
            Text(AnnouncementManagementText.value("limit")).font(.caption).foregroundStyle(AppTheme.textSecondary)
            if !selected.isEmpty {
                AnnouncementSection(AnnouncementManagementText.value("selected")) {
                    ForEach(selected, id: \.self) { id in
                        Toggle(isOn: binding(id)) {
                            if let user = known[id] { AnnouncementUserLabel(user: user) }
                            else { Text(NotificationAuditCopy.loadingRecipient).font(.caption) }
                        }
                    }
                    if let resolutionError { InlineMessageCard(style: .error, message: resolutionError) }
                }
            }
            if !search.failedMore { retryState }
            if search.loading { ProgressView() }
            if search.items.isEmpty && search.cursor == nil && !search.loading && search.error == nil { Text(AnnouncementManagementText.value("noResults")) }
            ForEach(search.items.filter { !selected.contains($0.id) }) { user in
                Toggle(isOn: binding(user.id)) { AnnouncementUserLabel(user: user) }
                    .disabled(selected.count >= 100 || user.available == false)
                    .accessibilityIdentifier("announcements.recipient.\(user.id)")
            }
            if search.failedMore { retryState }
            if search.cursor != nil { Button(AnnouncementStrings.loadMore) { Task { await search.more() } }.disabled(search.loading) }
        }
        .task(id: query) { await search.search(query) }
        .onChange(of: search.items.map(\.id)) { _, _ in for user in search.items { known[user.id] = user } }
        .task {
            guard !selected.isEmpty else { return }
            do {
                let response = try await repository.read("manageAnnouncements", AnnouncementRequest(userIds: selected, operation: "resolveUsers"))
                guard !Task.isCancelled else { return }
                for user in response.users ?? [] { known[user.id] = user }
            } catch { if !Task.isCancelled { resolutionError = AnnouncementErrorPresentation.message(error) } }
        }
    }
    @ViewBuilder private var retryState: some View {
        if let error = search.error {
            InlineMessageCard(style: .error, message: error)
            Button(AnnouncementStrings.retry) { Task { await search.retry() } }
                .disabled(search.loading).accessibilityIdentifier("announcements.recipientRetry")
        }
    }
    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { on in
            selected.removeAll { $0 == id }; if on && selected.count < 100 { selected.append(id) }
        })
    }
}
