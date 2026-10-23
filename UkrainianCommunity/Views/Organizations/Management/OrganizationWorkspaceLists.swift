import Combine
import SwiftUI

@MainActor final class OrganizationWorkspaceListModel: ObservableObject {
    @Published private(set) var items: [OrganizationWorkspaceContent] = []
    @Published private(set) var users: [OrganizationWorkspaceUser] = []
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = false
    private let read: (OrganizationWorkspaceRequest) async throws -> OrganizationWorkspaceResponse
    init(read: ((OrganizationWorkspaceRequest) async throws -> OrganizationWorkspaceResponse)? = nil) {
        self.read = read ?? { try await CloudFunctionsClient.shared.call(.manageOrganizationWorkspace, request: $0) }
    }
    private var cursor: String?
    private var generation = UUID()
    func reset() { generation = UUID(); items = []; users = []; counts = [:]; cursor = nil; hasMore = false; loading = false; error = nil }
    func load(_ request: OrganizationWorkspaceRequest, more: Bool = false) async {
        if more { guard hasMore, !loading else { return } }
        else { generation = UUID(); cursor = nil; hasMore = false; items = []; users = [] }
        let expected = generation; loading = true; error = nil
        defer { if generation == expected { loading = false } }
        do {
            var request = request; request.cursor = more ? cursor : nil
            let result: OrganizationWorkspaceResponse
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                if request.action == "content", let id = request.organizationId {
                    let all: [OrganizationWorkspaceContent]
                    if request.contentType == "news" {
                        all = try await MockNewsRepository().fetchOrganizationNews(organizationID: id, limit: 10000)
                            .map { .init(id: $0.id, title: $0.localizedTitle, status: $0.moderationStatus, reason: "") }
                    } else {
                        all = try await MockEventRepository().fetchOrganizationEvents(organizationID: id, limit: 10000)
                            .map { .init(id: $0.id, title: $0.localizedTitle, status: $0.moderationStatus, reason: "") }
                    }
                    result = .init(counts: Dictionary(grouping: all, by: { $0.status.rawValue }).mapValues(\.count), items: all.filter { request.status == nil || $0.status.rawValue == request.status })
                } else { result = .init(users: []) }
            } else { result = try await read(request) }
            guard generation == expected, !Task.isCancelled else { return }
            var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }); (result.items ?? []).forEach { byID[$0.id] = $0 }
            items = byID.values.sorted { $0.id < $1.id }
            var people = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) }); (result.users ?? []).forEach { people[$0.id] = $0 }
            users = people.values.sorted { $0.id < $1.id }; counts = result.counts ?? [:]; cursor = result.cursor; hasMore = cursor != nil
        } catch { if generation == expected, !Task.isCancelled { self.error = ContentModerationCopy.error(error) } }
    }
}

struct OrganizationWorkspaceContentList: View {
    @EnvironmentObject private var authState: AuthState
    let organization: Organization
    let contentType: String
    @StateObject private var model = OrganizationWorkspaceListModel()
    @State private var status: String = "all"
    @State private var selected: OrganizationWorkspaceContent?
    @State private var creating = false
    private var title: String { contentType == "news" ? AppStrings.News.title : AppStrings.Events.title }
    private var request: OrganizationWorkspaceRequest { .init(action: "content", principalId: authState.user?.id ?? "", organizationId: organization.id, contentType: contentType, status: status == "all" ? nil : status, language: LocalizationStore.language.rawValue) }
    var body: some View {
        ProfileDestinationLayout(title: title, introSubtitle: OrganizationWorkspaceCopy.contentHelper) {
            PrimaryActionButton(title: contentType == "news" ? AppStrings.Profile.createOrganizationNews : AppStrings.Profile.createOrganizationEvent,
                                systemImage: "plus") { creating = true }
                .accessibilityIdentifier("organization.content.create")
            Picker(AppStrings.Common.status, selection: $status) {
                Text(OrganizationWorkspaceCopy.all).tag("all")
                ForEach([ModerationStatus.draft, .pendingReview, .needsRevision, .approved, .rejected, .archived], id: \.rawValue) { value in
                    Text("\(value.title) · \(model.counts[value.rawValue] ?? 0)").tag(value.rawValue)
                }
            }.pickerStyle(.menu).tint(AppTheme.accentPrimaryForeground).accessibilityIdentifier("organization.content.status")
            if let error = model.error {
                InlineMessageCard(style: .error, message: error)
                Button(AppStrings.Action.retry) { Task { await model.load(request) } }
            }
            if model.loading && model.items.isEmpty { LoadingStateCard(title: title) }
            if !model.loading && model.error == nil && model.items.isEmpty {
                UnifiedEmptyStateCard(systemImage: "doc.text", title: title, message: OrganizationWorkspaceCopy.noMatches)
            }
            LazyVStack(spacing: 12) {
                ForEach(model.items) { item in
                    Button { selected = item } label: {
                        AppEditorSectionCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title).font(.headline).foregroundStyle(AppTheme.textPrimary)
                                Text(item.status.title).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accentPrimaryForeground)
                                if !item.reason.isEmpty { Text(item.reason).font(.footnote).foregroundStyle(AppTheme.textSecondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("organization.content.open.\(item.id)")
                }
            }
            if model.hasMore { PrimaryActionButton(title: AppStrings.Search.loadMoreContent, isEnabled: !model.loading, isLoading: model.loading, systemImage: "arrow.down") { Task { await model.load(request, more: true) } } }
        }
        .task(id: "\(authState.user?.id ?? "")-\(status)") { await model.load(request) }
        .appRefreshable { await model.load(request) }
        .onReceive(NotificationCenter.default.publisher(for: contentType == "news" ? .newsChanged : .eventsChanged)) { _ in Task { await model.load(request) } }
        .onChange(of: authState.user?.id) { _, _ in model.reset(); selected = nil; creating = false }
        .sheet(item: $selected, onDismiss: { Task { await model.load(request) } }) { item in
            ContentModerationDetail(contentType: contentType, contentID: item.id, allowsPublishedEditing: true)
        }
        .sheet(isPresented: $creating, onDismiss: { Task { await model.load(request) } }) {
            NavigationStack {
                if contentType == "news" {
                    NewsEditorView(repository: FirestoreNewsRepository(), organizationId: organization.id, organizationName: organization.name,
                        organizationImageURL: organization.imageURL, organizationFederalState: organization.federalState)
                } else {
                    EventEditorView(repository: FirestoreEventRepository(), organizationId: organization.id, organizationName: organization.name,
                        organizationImageURL: organization.imageURL, organizationFederalState: organization.federalState)
                }
            }
        }
    }
}

struct OrganizationWorkspaceSubscribers: View {
    @EnvironmentObject private var authState: AuthState
    let organization: Organization
    @StateObject private var model = OrganizationWorkspaceListModel()
    @State private var search = ""
    private var request: OrganizationWorkspaceRequest { .init(action: "subscribers", principalId: authState.user?.id ?? "", organizationId: organization.id, search: search) }
    var body: some View {
        ProfileDestinationLayout(title: OrganizationWorkspaceCopy.subscribers, introSubtitle: OrganizationWorkspaceCopy.subscribersHelper) {
            AppSearchField(placeholder: AppStrings.Profile.organizationTeamSearchPlaceholder, text: $search)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12))
            if let error = model.error { InlineMessageCard(style: .error, message: error); Button(AppStrings.Action.retry) { Task { await model.load(request) } } }
            if model.loading && model.users.isEmpty { LoadingStateCard(title: OrganizationWorkspaceCopy.subscribers) }
            if !model.loading && model.error == nil && model.users.isEmpty { Text(OrganizationWorkspaceCopy.noMatches).foregroundStyle(AppTheme.textSecondary) }
            LazyVStack(spacing: 12) {
                ForEach(model.users) { person in
                    AppEditorSectionCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(person.displayName.isEmpty ? AppStrings.Common.communityMemberFallback : person.displayName).font(.headline)
                            if !person.city.isEmpty { Text(person.city).font(.caption).foregroundStyle(AppTheme.textSecondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if model.hasMore { PrimaryActionButton(title: AppStrings.Search.loadMoreContent, isEnabled: !model.loading, isLoading: model.loading, systemImage: "arrow.down") { Task { await model.load(request, more: true) } } }
        }
        .task(id: "\(authState.user?.id ?? "")-\(search)") {
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)); guard !Task.isCancelled else { return } }
            await model.load(request)
        }
        .appRefreshable { await model.load(request) }
        .onChange(of: authState.user?.id) { _, _ in model.reset() }
    }
}
