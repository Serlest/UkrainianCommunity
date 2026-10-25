import Combine
import FirebaseAuth
import FirebaseFunctions
import SwiftUI

nonisolated struct ContentModerationCursor: Codable, Equatable {
    let seconds: Int64
    let nanoseconds: Int32
    let id: String
}
nonisolated struct ContentReviewText: Codable, Equatable {
    let title: String
    let summary: String
    let body: String
}
nonisolated struct ContentReviewItem: Codable, Identifiable, Equatable {
    let id: String
    let contentType: String
    let revision: String
    let status: ModerationStatus
    let title: String
    let translations: [String: ContentReviewText]
    let organizationId: String
    let organizationName: String
    let authorName: String
    let createdAt: Double
    let imageURL: String
    let sourceName: String
    let sourceURL: String
    let region: String
    let venue: String
    let city: String
    let address: String
    let startDate: Double?
    let endDate: Double?
    let reason: String
    let canReview: Bool
    var canEdit: Bool? = nil
    var publication: ContentReviewPublication? = nil

    func text(_ language: PublishedContentLanguage) -> ContentReviewText {
        translations[language.rawValue] ?? .init(title: title, summary: "", body: "")
    }
    var displayText: ContentReviewText { text(LocalizationStore.language == .german ? .german : .ukrainian) }
}
nonisolated struct ContentReviewHistoryEntry: Codable, Identifiable, Equatable {
    let id: String
    let contentId: String
    let contentType: String
    let title: String
    let status: ModerationStatus
    let reason: String
    let reviewerName: String
    let organizationName: String
    let createdAt: Double
}
nonisolated struct ContentModerationQuery: Codable {
    let action: String
    var contentType: String? = nil
    var contentId: String? = nil
    var limit: Int? = nil
    var cursor: ContentModerationCursor? = nil
    var expectedRevision: String? = nil
    var includeCounts: Bool? = nil
}
nonisolated struct ContentModerationResult: Codable {
    var items: [ContentReviewItem]? = nil
    var history: [ContentReviewHistoryEntry]? = nil
    var item: ContentReviewItem? = nil
    var counts: [String: Int]? = nil
    var cursor: ContentModerationCursor? = nil
}

struct ContentModerationClient {
    var read: (ContentModerationQuery) async throws -> ContentModerationResult
    var decide: (ContentReviewItem, ModerationStatus, String, String, String) async throws -> Void
    static var live: Self {
        .init(read: { try await CloudFunctionsClient.shared.call(.manageContentModeration, request: $0) },
              decide: { item, status, reason, operation, principal in
            let response: ContentModerationFunctionResponse = try await CloudFunctionsClient.shared.call(.reviewContentModeration,
                request: ContentModerationFunctionRequest(contentType: item.contentType, contentId: item.id,
                    decision: status.rawValue, operationId: operation, expectedRevision: item.revision, reason: reason, principalId: principal))
            guard response.contentId == item.id, response.contentType == item.contentType,
                  response.moderationStatus == status.rawValue, response.operationId == operation else { throw AppError.validationFailed }
        })
    }
    static var current: Self {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return ContentModerationFixture.shared.client }
#endif
        return .live
    }
}

private struct ContentModerationLoadScope: Hashable {
    let type: String
    let history: Bool
    let access: ProfileAccessIdentity?
}

@MainActor
final class ContentModerationModel: ObservableObject {
    @Published private(set) var items: [ContentReviewItem] = []
    @Published private(set) var history: [ContentReviewHistoryEntry] = []
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var failedLoadWasMore = false
    private var cursor: ContentModerationCursor?
    private var generation = 0
    private var scope: ContentModerationLoadScope?
    private var loadingFirstPage = false
    private let client: ContentModerationClient
    init(client: ContentModerationClient? = nil) { self.client = client ?? .current }

    func matches(type: String, historyMode: Bool, access: ProfileAccessIdentity?) -> Bool {
        scope == ContentModerationLoadScope(type: type, history: historyMode, access: access)
    }
    func reset() {
        generation += 1; scope = nil; cursor = nil; items = []; history = []; counts = [:]
        hasMore = false; hasLoaded = false; isLoading = false; error = nil; failedLoadWasMore = false
    }

    func load(type: String, historyMode: Bool, reset: Bool, access: ProfileAccessIdentity? = nil) async {
        let requested = ContentModerationLoadScope(type: type, history: historyMode, access: access)
        if isLoading && scope == requested && (loadingFirstPage || !reset) { return }
        if !reset && (scope != requested || !hasMore) { return }
        if scope != requested {
            self.reset(); scope = requested
        }
        if reset { generation += 1 }
        let expected = generation
        let requestedCursor = reset ? nil : cursor
        isLoading = true; loadingFirstPage = reset; error = nil
        defer { if generation == expected { isLoading = false; loadingFirstPage = false } }
        do {
            let response = try await client.read(.init(action: historyMode ? "history" : "list", contentType: type, limit: 30, cursor: requestedCursor, includeCounts: requestedCursor == nil))
            guard generation == expected, scope == requested, !Task.isCancelled else { return }
            if reset { items = []; history = [] }
            var itemIDs = Set(items.map(\.id)); var historyIDs = Set(history.map(\.id))
            items += (response.items ?? []).filter { itemIDs.insert($0.id).inserted }
            history += (response.history ?? []).filter { historyIDs.insert($0.id).inserted }
            if let counts = response.counts { self.counts = counts }
            cursor = response.cursor; hasMore = cursor != nil; error = nil; hasLoaded = true; failedLoadWasMore = false
        } catch {
            if generation == expected && !Task.isCancelled {
                self.error = ContentModerationCopy.error(error, reading: true); failedLoadWasMore = !reset
            }
        }
    }
}

private struct ModerationPickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.pickerStyle(.menu).frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget, alignment: .leading)
                .padding(.horizontal, 12)
                .background(AppTheme.surfaceControl, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius))
        } else { content.pickerStyle(.segmented) }
    }
}

private struct ContentModerationSelection: Identifiable {
    let id: String
    let contentType: String
    var revision: String? = nil
}

struct ContentModerationView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var model = ContentModerationModel()
    @State private var contentType = "news"
    @State private var showsHistory = false
    @State private var search = ""
    @State private var selected: ContentModerationSelection?
    @State private var refreshAfterPreview = false
    private var canAccess: Bool { authState.user.map { PermissionService.canModerate(section: .news, user: $0) } ?? false }
    private var access: ProfileAccessIdentity { ProfileAccessIdentity(user: authState.user) }
    private func count(_ type: String) -> String {
        guard matchesQuery else { return "—" }
        return model.counts[type].map(String.init) ?? "—"
    }
    private var matchesQuery: Bool { model.matches(type: contentType, historyMode: showsHistory, access: access) }
    private var visible: [ContentReviewItem] {
        guard matchesQuery else { return [] }
        return model.items.filter { LocalSearchMatcher.matches(query: search, values: [$0.displayText.title, $0.displayText.summary, $0.organizationName, $0.authorName]) }
    }
    var body: some View {
        AdminScreenShell(title: AppStrings.Profile.ownerModeration, subtitle: ContentModerationCopy.subtitle, tabBarHidden: false) {
            if canAccess {
                Picker(AppStrings.OrganizationReview.section, selection: $showsHistory) {
                    Text(AppStrings.OrganizationReview.pending).tag(false)
                    Text(AppStrings.OrganizationReview.history).tag(true)
                }.modifier(ModerationPickerStyle()).accessibilityIdentifier("content.moderation.mode")
                if !showsHistory {
                    Picker(AppStrings.Moderation.filterAll, selection: $contentType) {
                        Text("\(AppStrings.Moderation.typeNews): \(count("news"))").tag("news")
                        Text("\(AppStrings.Moderation.typeEvent): \(count("event"))").tag("event")
                    }.modifier(ModerationPickerStyle()).accessibilityIdentifier("content.moderation.type")
                    AppSearchField(placeholder: AppStrings.Moderation.searchPlaceholder, text: $search,
                                   fieldID: "content.moderation.search")
                    if model.hasMore && !search.isEmpty { Text(ContentModerationCopy.loadedSearch).font(.footnote).foregroundStyle(AppTheme.textSecondary) }
                }
                if let error = model.error, matchesQuery {
                    InlineMessageCard(style: .error, message: error)
                    Button(AppStrings.Moderation.retry) { Task { await model.load(type: contentType, historyMode: showsHistory, reset: !model.failedLoadWasMore, access: access) } }
                        .disabled(model.isLoading).accessibilityIdentifier("content.moderation.retry")
                }
                if !matchesQuery || (!model.hasLoaded && model.error == nil) {
                    LoadingStateCard(title: AppStrings.Profile.ownerModeration).accessibilityIdentifier("content.moderation.loading")
                } else if showsHistory {
                    historyContent
                } else if visible.isEmpty && model.hasLoaded && model.error == nil {
                    UnifiedEmptyStateCard(systemImage: "checkmark.shield", title: AppStrings.Profile.ownerModeration,
                        message: search.isEmpty ? AppStrings.Moderation.empty : AppStrings.Moderation.filteredEmptyMessage)
                        .accessibilityIdentifier("content.moderation.empty")
                } else {
                    LazyVStack(spacing: AppTheme.feedRowSpacing) {
                        ForEach(visible) { item in
                            Button { selected = .init(id: item.id, contentType: item.contentType, revision: item.revision) } label: { ContentReviewSummary(item: item) }
                                .buttonStyle(.plain).accessibilityIdentifier("content.moderation.open.\(item.id)")
                        }
                    }
                }
                if matchesQuery && model.hasMore {
                    PrimaryActionButton(title: AppStrings.OrganizationReview.loadMore, isEnabled: !model.isLoading,
                        isLoading: model.isLoading, systemImage: "arrow.down") {
                        Task { await model.load(type: contentType, historyMode: showsHistory, reset: false, access: access) }
                    }.accessibilityIdentifier("content.moderation.more")
                }
            } else { InlineMessageCard(style: .error, message: AppStrings.Moderation.loadPermissionError) }
            Color.clear.frame(height: 96)
        }
        .task(id: ContentModerationLoadScope(type: contentType, history: showsHistory, access: access)) {
            if canAccess { await reload() } else { model.reset() }
        }
        .onChange(of: access) { _, _ in selected = nil }
        .appRefreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .moderationStatusDidChange)) { _ in refreshAfterPreview = true }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged)) { _ in refreshAfterPreview = true }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged)) { _ in refreshAfterPreview = true }
        .sheet(item: $selected, onDismiss: {
            if refreshAfterPreview { refreshAfterPreview = false; Task { await reload() } }
        }) { item in
            ContentModerationDetail(contentType: item.contentType, contentID: item.id, initialRevision: item.revision,
                                    onMaterialChanged: { refreshAfterPreview = true })
                .id(item.contentType + ":" + item.id)
        }
    }
    private func reload() async { guard canAccess else { return }; await model.load(type: contentType, historyMode: showsHistory, reset: true, access: access) }
    @ViewBuilder private var historyContent: some View {
        Text(ContentModerationCopy.historyRetention).font(.footnote).foregroundStyle(AppTheme.textSecondary)
        if model.history.isEmpty && !model.isLoading && model.error == nil {
            UnifiedEmptyStateCard(systemImage: "clock.arrow.circlepath", title: AppStrings.OrganizationReview.history, message: ContentModerationCopy.historyEmpty)
        }
        LazyVStack(spacing: AppTheme.feedRowSpacing) {
            ForEach(model.history) { entry in
                Button { selected = .init(id: entry.contentId, contentType: entry.contentType) } label: {
                  AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(entry.contentType == "event" ? AppStrings.Moderation.typeEvent : AppStrings.Moderation.typeNews,
                              systemImage: entry.contentType == "event" ? "calendar" : "newspaper")
                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                        Text(entry.title.isEmpty ? (entry.contentType == "news" ? AppStrings.Moderation.typeNews : AppStrings.Moderation.typeEvent) : entry.title).font(.headline)
                        Text(entry.status.title).foregroundStyle(AppTheme.accentPrimaryForeground)
                        if !entry.reason.isEmpty { Text(entry.reason).textSelection(.enabled) }
                        if !entry.organizationName.isEmpty { Text(entry.organizationName).font(.subheadline) }
                        if !entry.reviewerName.isEmpty { Text(entry.reviewerName).font(.caption) }
                        Text(LocalizationStore.dateString(from: Date(timeIntervalSince1970: entry.createdAt / 1000), timeStyle: .short)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                        Label(ContentModerationCopy.openMaterial, systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline).foregroundStyle(AppTheme.accentPrimaryForeground)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                  }
                }.buttonStyle(.plain)
                    .disabled(!["news", "event"].contains(entry.contentType) || entry.contentId.isEmpty)
                    .accessibilityIdentifier("content.moderation.history.open.\(entry.id)")
            }
        }
    }
}

private struct ContentReviewSummary: View {
    let item: ContentReviewItem
    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.displayText.title).font(.headline)
                Text(item.displayText.summary).font(.subheadline).foregroundStyle(AppTheme.textSecondary).lineLimit(3)
                if !item.organizationName.isEmpty { Label(item.organizationName, systemImage: "building.2").font(.subheadline) }
                if !item.authorName.isEmpty { Label(item.authorName, systemImage: "person").font(.caption) }
                Text(LocalizationStore.dateString(from: Date(timeIntervalSince1970: item.createdAt / 1000))).font(.caption).foregroundStyle(AppTheme.textSecondary)
                Label(ContentModerationCopy.openMaterial, systemImage: "doc.text.magnifyingglass").foregroundStyle(AppTheme.accentPrimaryForeground)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
final class ContentReviewDetailModel: ObservableObject {
    @Published private(set) var item: ContentReviewItem?
    @Published private(set) var loading = false
    @Published private(set) var processing = false
    @Published private(set) var error: String?
    @Published private(set) var completed = false
    @Published private(set) var isUnavailable = false
    private var operations: [String: String] = [:]
    private var generation = 0
    private var loadedPrincipal: String?
    private let client: ContentModerationClient
    init(client: ContentModerationClient? = nil) { self.client = client ?? .current }
    func load(type: String, id: String, principal: String? = nil) async {
        guard !processing else { return }
        generation += 1; let expected = generation
        let changedContext = loadedPrincipal != principal || item?.id != id || item?.contentType != type
        loadedPrincipal = principal
        if changedContext { item = nil; operations = [:]; completed = false }
        loading = true; error = nil; isUnavailable = false
        defer { if generation == expected { loading = false } }
        do {
            let result = try await client.read(.init(action: "preview", contentType: type, contentId: id))
            guard generation == expected, !Task.isCancelled else { return }
            guard let item = result.item, item.id == id, item.contentType == type else { throw AppError.validationFailed }
            self.item = item; error = nil
        } catch {
            guard generation == expected, !Task.isCancelled else { return }
            let ns = error as NSError
            isUnavailable = FirebaseReadErrorMapper.map(error) == .notFound
                || ns.domain == FunctionsErrorDomain && ns.code == FunctionsErrorCode.notFound.rawValue
            self.item = nil; self.error = ContentModerationCopy.error(error, reading: true)
        }
    }
    func decide(_ status: ModerationStatus, reason: String, principal: String, reviewedItem: ContentReviewItem? = nil) async {
        guard let item, item.canReview, !loading, !processing, !completed, !principal.isEmpty,
              loadedPrincipal == nil || loadedPrincipal == principal else { return }
        if let reviewedItem, reviewedItem.id != item.id || reviewedItem.revision != item.revision || reviewedItem.contentType != item.contentType {
            error = ContentModerationCopy.changed; return
        }
        let reason = status == .approved ? "" : reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.utf16.count <= 2000, status == .approved || !reason.isEmpty else { return }
        processing = true; defer { processing = false }
        let key = "\(item.revision):\(status.rawValue):\(reason)"
        let operation = operations[key] ?? UUID().uuidString; operations[key] = operation
        do {
            try await client.decide(item, status, reason, operation, principal)
            error = nil; completed = true
            NotificationCenter.default.post(name: .moderationStatusDidChange, object: nil)
        } catch { self.error = ContentModerationCopy.error(error) }
    }
}

private struct ContentReviewDecisionConfirmation {
    let item: ContentReviewItem
    let status: ModerationStatus
    let reason: String
    let access: ProfileAccessIdentity
}

struct ContentModerationDetail: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let contentType: String
    let contentID: String
    var allowsPublishedEditing = false
    var embedsInNavigationStack = true
    var initialRevision: String? = nil
    var onMaterialChanged: () -> Void = {}
    @StateObject private var model = ContentReviewDetailModel()
    @State private var language: PublishedContentLanguage = LocalizationStore.language == .german ? .german : .ukrainian
    @State private var decision: ModerationStatus?
    @State private var reason = ""
    @State private var confirmation: ContentReviewDecisionConfirmation?
    @State private var editingNews: NewsPost?
    @State private var editingEvent: Event?
    @State private var editLoading = false
    @State private var editError: String?
    private var canDecide: Bool { !model.loading && model.item?.canReview == true && (authState.user.map { PermissionService.canModerate(section: .news, user: $0) } ?? false) }
    private var valid: Bool { decision != nil && reason.utf16.count <= 2000 && (decision == .approved || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    @ViewBuilder var body: some View {
        if embedsInNavigationStack { NavigationStack { reviewContent } }
        else { reviewContent }
    }
    private var reviewContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    if model.loading || (model.item == nil && model.error == nil) { LoadingStateCard(title: ContentModerationCopy.openMaterial) }
                    if let error = model.error {
                        InlineMessageCard(style: .error, message: error)
                        if !model.isUnavailable {
                            Button(AppStrings.Moderation.retry) { Task { await model.load(type: contentType, id: contentID, principal: authState.user?.id) } }
                                .disabled(model.processing).accessibilityIdentifier("content.review.retry")
                        }
                    }
                    if let item = model.item {
                        Picker(AppStrings.OrganizationReview.section, selection: $language) {
                            ForEach(PublishedContentLanguage.allCases) { Text($0.title).tag($0) }
                        }.modifier(ModerationPickerStyle()).accessibilityIdentifier("content.review.language")
                        ContentMaterialPreview(item: item, language: language)
                        ContentModerationPublicationDetails(item: item)
                        if !item.reason.isEmpty { InlineMessageCard(style: .info, message: item.reason) }
                        if let editError { InlineMessageCard(style: .error, message: editError) }
                        if item.canEdit == true && ([.needsRevision, .rejected].contains(item.status) || allowsPublishedEditing && item.status != .archived) {
                            Text(ContentModerationCopy.editHelper).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                            PrimaryActionButton(title: ContentModerationCopy.editMaterial, isEnabled: !editLoading && !model.loading && !model.processing,
                                isLoading: editLoading, systemImage: "square.and.pencil") { Task { await openEditor(item) } }
                                .accessibilityIdentifier("content.review.edit")
                        }
                        if canDecide {
                            decisionContent
                            if dynamicTypeSize.isAccessibilitySize { decisionAction }
                        }
                    }
                }.padding(AppTheme.pageHorizontal).appCenteredContent().contentShape(Rectangle())
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackgroundView())
            .navigationTitle(ContentModerationCopy.openMaterial).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).navigationBarBackButtonHidden(true)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.Common.done) { dismiss() }.tint(AppTheme.accentPrimaryForeground).disabled(model.processing)
                    .accessibilityIdentifier("content.review.close")
            } }
            .safeAreaInset(edge: .bottom) {
                if canDecide && !dynamicTypeSize.isAccessibilitySize {
                    decisionAction.padding(AppTheme.pageHorizontal).appCenteredContent().background(.regularMaterial)
                }
            }
            .alert(AppStrings.OrganizationReview.confirmDecision, isPresented: Binding(
                get: { confirmation != nil && !dynamicTypeSize.isAccessibilitySize }, set: { if !$0 { confirmation = nil } }
            ), presenting: confirmation) { confirmed in
                Button(ContentModerationCopy.decision(confirmed.status), role: confirmed.status == .rejected ? .destructive : nil) {
                    execute(confirmed)
                }.accessibilityIdentifier("content.review.execute")
                Button(AppStrings.Common.cancel, role: .cancel) {}
                    .accessibilityIdentifier("content.review.cancelDecision")
            } message: { confirmed in
                Text([confirmed.item.displayText.title, ContentModerationCopy.decision(confirmed.status),
                      confirmed.reason, ContentModerationCopy.confirmHelper].filter { !$0.isEmpty }.joined(separator: "\n\n"))
            }
            .sheet(isPresented: Binding(
                get: { confirmation != nil && dynamicTypeSize.isAccessibilitySize },
                set: { if !$0 { confirmation = nil } }
            )) {
                if let confirmed = confirmation {
                    ContentReviewAccessibleConfirmation(confirmation: confirmed,
                        confirm: { execute(confirmed) }, cancel: { confirmation = nil })
                }
            }
            .tint(AppTheme.accentPrimaryForeground)
            .interactiveDismissDisabled(model.processing)
            .task { await model.load(type: contentType, id: contentID, principal: authState.user?.id) }
            .sheet(item: $editingNews, onDismiss: { Task { await model.load(type: contentType, id: contentID, principal: authState.user?.id) } }) { news in
                NavigationStack { NewsEditorView(repository: FirestoreNewsRepository(), news: news) }
            }
            .sheet(item: $editingEvent, onDismiss: { Task { await model.load(type: contentType, id: contentID, principal: authState.user?.id) } }) { event in
                NavigationStack { EventEditorView(repository: FirestoreEventRepository(), event: event) }
            }
            .onChange(of: model.item?.revision) { _, revision in
                if let initialRevision, let revision, revision != initialRevision { onMaterialChanged() }
            }
            .onChange(of: model.completed) { _, completed in if completed { onMaterialChanged(); dismiss() } }
            .onChange(of: ProfileAccessIdentity(user: authState.user)) { _, _ in confirmation = nil; dismiss() }
    }
    private func execute(_ confirmed: ContentReviewDecisionConfirmation) {
        guard canDecide, confirmed.access == ProfileAccessIdentity(user: authState.user),
              let principal = confirmed.access.userID else { return }
        confirmation = nil
        Task { await model.decide(confirmed.status, reason: confirmed.reason, principal: principal, reviewedItem: confirmed.item) }
    }

    private var decisionAction: some View {
        PrimaryActionButton(title: AppStrings.OrganizationReview.confirmDecision, isEnabled: valid && !model.processing,
            isLoading: model.processing, systemImage: "checkmark.shield") {
            guard let item = model.item, let decision else { return }
            confirmation = .init(item: item, status: decision,
                reason: decision == .approved ? "" : reason.trimmingCharacters(in: .whitespacesAndNewlines),
                access: ProfileAccessIdentity(user: authState.user))
        }.accessibilityIdentifier("content.review.confirm")
    }

    private func openEditor(_ item: ContentReviewItem) async {
        guard !editLoading, item.canEdit == true else { return }
        editLoading = true; defer { editLoading = false }
        let principal = authState.user?.id
        do {
            if item.contentType == "news" {
                let news = try await FirestoreNewsRepository().fetchManagedNews(id: item.id, organizationID: item.organizationId)
                guard !Task.isCancelled, authState.user?.id == principal else { return }
                editingNews = news
            } else {
                let event = try await FirestoreEventRepository().fetchManagedEvent(id: item.id, organizationID: item.organizationId)
                guard !Task.isCancelled, authState.user?.id == principal else { return }
                editingEvent = event
            }
            editError = nil
        } catch {
            guard !Task.isCancelled, authState.user?.id == principal else { return }
            editError = ContentModerationCopy.error(error, reading: true)
        }
    }

    private var decisionContent: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(ContentModerationCopy.decisionTitle).font(.headline)
                ForEach([ModerationStatus.approved, .needsRevision, .rejected], id: \.rawValue) { status in
                    Button { decision = status } label: {
                        HStack {
                            Image(systemName: decision == status ? "checkmark.circle.fill" : "circle")
                            Text(ContentModerationCopy.decision(status)).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }.padding(10).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(status == .rejected ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground)
                            .background(AppTheme.surfaceControl.opacity(0.4), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(model.processing)
                        .accessibilityAddTraits(decision == status ? .isSelected : [])
                        .accessibilityIdentifier("content.review.choice.\(status.rawValue)")
                }
                if decision != nil && decision != .approved {
                    Text(ContentModerationCopy.reasonHelper).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    TextField(ModerationAuditCopy.text("reason_title"), text: $reason, axis: .vertical)
                        .lineLimit(3...8).textFieldStyle(.plain)
                        .padding(12).frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .foregroundStyle(AppTheme.textPrimary)
                        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.inputRadius).strokeBorder(AppTheme.borderSubtle))
                        .disabled(model.processing)
                        .accessibilityLabel(ModerationAuditCopy.text("reason_title"))
                        .accessibilityIdentifier("content.review.reason")
                    Text("\(reason.utf16.count) / 2000").font(.caption)
                        .foregroundStyle(reason.utf16.count > 2000 ? AppTheme.accentDestructiveForeground : AppTheme.textSecondary)
                }
            }
        }
    }
}

private struct ContentReviewAccessibleConfirmation: View {
    let confirmation: ContentReviewDecisionConfirmation
    let confirm: () -> Void
    let cancel: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    Text(AppStrings.OrganizationReview.confirmDecision).font(.title2.bold())
                    AppEditorSectionCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(confirmation.item.displayText.title).font(.headline)
                            Text(ContentModerationCopy.decision(confirmation.status))
                                .foregroundStyle(AppTheme.accentPrimaryForeground)
                            if !confirmation.reason.isEmpty { Text(confirmation.reason).textSelection(.enabled) }
                            Text(ContentModerationCopy.confirmHelper).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    PrimaryActionButton(title: ContentModerationCopy.decision(confirmation.status), systemImage: "checkmark.shield", action: confirm)
                        .accessibilityIdentifier("content.review.execute")
                }.padding(AppTheme.pageHorizontal).appCenteredContent()
            }
            .background(AppBackgroundView())
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.Common.cancel, action: cancel).accessibilityIdentifier("content.review.cancelDecision")
            } }
        }.tint(AppTheme.accentPrimaryForeground).presentationDetents([.large])
    }
}

private struct ContentMaterialPreview: View {
    let item: ContentReviewItem
    let language: PublishedContentLanguage
    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.text(language).title).font(.title2.bold())
                Text(item.status.title).foregroundStyle(AppTheme.accentPrimaryForeground)
                if !item.organizationName.isEmpty { Label(item.organizationName, systemImage: "building.2") }
                if !item.authorName.isEmpty { Label(item.authorName, systemImage: "person") }
                if ![item.city, item.venue, item.address].allSatisfy({ $0.isEmpty }) { Label([item.city, item.venue, item.address].filter { !$0.isEmpty }.joined(separator: ", "), systemImage: "mappin") }
                if let start = item.startDate { dateRow("starts", milliseconds: start) }
                if let end = item.endDate { dateRow("ends", milliseconds: end) }
                if let url = URL(string: item.imageURL), url.scheme == "https" {
                    RemoteImageView(imageURL: url.absoluteString, height: 260, cornerRadius: AppTheme.cardRadius,
                                    source: "moderation_preview", presentationStyle: .fit, showsRetryOnFailure: true)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(item.publication?.mediaMetadata?.alternativeText ?? item.text(language).title)
                }
                Text(item.text(language).summary).font(.headline).textSelection(.enabled)
                Text(item.text(language).body).textSelection(.enabled)
                if !item.sourceName.isEmpty || !item.sourceURL.isEmpty {
                    Text(ContentModerationCopy.source).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    if let url = URL(string: item.sourceURL), url.scheme?.lowercased() == "https", url.host?.isEmpty == false {
                        Link(item.sourceName.isEmpty ? item.sourceURL : item.sourceName, destination: url)
                        Text(item.sourceURL).font(.caption).foregroundStyle(AppTheme.textSecondary).textSelection(.enabled)
                    } else { Text([item.sourceName, item.sourceURL].filter { !$0.isEmpty }.joined(separator: " · ")).textSelection(.enabled) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func dateRow(_ key: String, milliseconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ModerationAuditCopy.text(key)).font(.caption).foregroundStyle(AppTheme.textSecondary)
            Text(LocalizationStore.dateString(from: Date(timeIntervalSince1970: milliseconds / 1000),
                timeStyle: item.publication?.isAllDay == true ? .none : .short))
        }
    }
}

enum ContentModerationCopy {
    static var editMaterial: String { text("moderation.content.edit", "Виправити матеріал") }
    static var editHelper: String { ModerationAuditCopy.editHint }
    private static func text(_ key: String, _ fallback: String) -> String { LocalizationStore.localizedString(key, defaultValue: fallback) }
    static var loadedSearch: String { text("moderation.content.loaded_search", "Пошук серед завантажених матеріалів. Для старіших натисніть «Показати ще».") }
    static var historyEmpty: String { text("moderation.content.history_empty", "Рішень щодо матеріалів поки немає.") }
    static var reasonHelper: String { text("moderation.content.reason_helper", "Поясніть, що потрібно виправити або чому матеріал відхилено. Цей текст отримає автор. До 2000 символів.") }
    static var confirmHelper: String { text("moderation.content.confirm_helper", "Статус матеріалу буде змінено. Автор і відповідальні за організацію отримають повідомлення.") }
    static var decisionTitle: String { text("moderation.content.decision", "Рішення щодо матеріалу") }
    static var subtitle: String { text("moderation.content.subtitle", "Перевіряйте матеріали організацій для публікації на всю Австрію.") }
    static var openMaterial: String { text("moderation.content.open", "Переглянути матеріал") }
    static var source: String { text("moderation.content.source", "Джерело") }
    static var imageUnavailable: String { text("moderation.content.image_unavailable", "Не вдалося завантажити зображення") }
    static var historyRetention: String { text("moderation.content.history_retention", "Рішення за останні 30 днів. Історія також може містити раніші записи.") }
    static var changed: String { text("moderation.content.changed", "Матеріал змінився або вже перевірений. Оновіть його та перевірте ще раз.") }
    static func decision(_ status: ModerationStatus) -> String {
        switch status { case .approved: AppStrings.Moderation.approve
        case .needsRevision: AppStrings.Moderation.requestRevision
        default: AppStrings.Moderation.reject }
    }
    static func error(_ error: Error, reading: Bool = false) -> String {
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: ns.code) {
            switch code {
            case .aborted, .failedPrecondition, .alreadyExists: return changed
            case .permissionDenied, .unauthenticated: return reading ? ModerationAuditCopy.text("load_permission") : AppStrings.Moderation.actionPermissionError
            case .unavailable, .deadlineExceeded, .cancelled: return reading ? ModerationAuditCopy.text("load_network") : AppStrings.Moderation.actionNetworkError
            case .notFound: return ModerationAuditCopy.unavailable
            default: break
            }
        }
        switch FirebaseReadErrorMapper.map(error) {
        case .network: return reading ? ModerationAuditCopy.text("load_network") : AppStrings.Moderation.actionNetworkError
        case .permissionDenied: return reading ? ModerationAuditCopy.text("load_permission") : AppStrings.Moderation.actionPermissionError
        case .validationFailed: return changed
        case .notFound: return ModerationAuditCopy.unavailable
        case .unknown: return reading ? ModerationAuditCopy.text("load_failed") : AppStrings.Moderation.actionUnknownError
        }
    }
}
