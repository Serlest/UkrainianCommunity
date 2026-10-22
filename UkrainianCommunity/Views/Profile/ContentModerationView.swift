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

@MainActor
final class ContentModerationModel: ObservableObject {
    @Published private(set) var items: [ContentReviewItem] = []
    @Published private(set) var history: [ContentReviewHistoryEntry] = []
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = false
    private var cursor: ContentModerationCursor?
    private var generation = 0
    private let client: ContentModerationClient
    init(client: ContentModerationClient? = nil) { self.client = client ?? .current }

    func load(type: String, historyMode: Bool, reset: Bool) async {
        if !reset && (isLoading || !hasMore) { return }
        if reset { generation += 1; cursor = nil; items = []; history = []; hasMore = false; error = nil }
        let expected = generation
        isLoading = true
        defer { if generation == expected { isLoading = false } }
        do {
            let response = try await client.read(.init(action: historyMode ? "history" : "list", contentType: type, limit: 30, cursor: cursor))
            guard generation == expected, !Task.isCancelled else { return }
            let itemIDs = Set(items.map(\.id)); let historyIDs = Set(history.map(\.id))
            items += (response.items ?? []).filter { !itemIDs.contains($0.id) }
            history += (response.history ?? []).filter { !historyIDs.contains($0.id) }
            if let counts = response.counts { self.counts = counts }
            cursor = response.cursor; hasMore = cursor != nil; error = nil
        } catch { if generation == expected && !Task.isCancelled { self.error = ContentModerationCopy.error(error) } }
    }
}

struct ContentModerationView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var model = ContentModerationModel()
    @State private var contentType = "news"
    @State private var showsHistory = false
    @State private var search = ""
    @State private var selected: ContentReviewItem?
    private var canAccess: Bool { authState.user.map { PermissionService.canModerate(section: .news, user: $0) } ?? false }
    private var visible: [ContentReviewItem] {
        model.items.filter { LocalSearchMatcher.matches(query: search, values: [$0.displayText.title, $0.displayText.summary, $0.organizationName, $0.authorName]) }
    }
    var body: some View {
        AdminScreenShell(title: AppStrings.Profile.ownerModeration, subtitle: ContentModerationCopy.subtitle, tabBarHidden: false) {
            if canAccess {
                Picker(AppStrings.OrganizationReview.section, selection: $showsHistory) {
                    Text(AppStrings.OrganizationReview.pending).tag(false)
                    Text(AppStrings.OrganizationReview.history).tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("content.moderation.mode")
                if !showsHistory {
                    Picker(AppStrings.Moderation.filterAll, selection: $contentType) {
                        Text("\(AppStrings.Moderation.typeNews): \(model.counts["news"] ?? 0)").tag("news")
                        Text("\(AppStrings.Moderation.typeEvent): \(model.counts["event"] ?? 0)").tag("event")
                    }.pickerStyle(.segmented).accessibilityIdentifier("content.moderation.type")
                    TextField(AppStrings.Moderation.searchPlaceholder, text: $search)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        .accessibilityIdentifier("content.moderation.search")
                    if model.hasMore && !search.isEmpty { Text(ContentModerationCopy.loadedSearch).font(.footnote).foregroundStyle(AppTheme.textSecondary) }
                }
                if let error = model.error {
                    InlineMessageCard(style: .error, message: error)
                    Button(AppStrings.Moderation.retry) { Task { await reload() } }
                }
                if model.isLoading && model.items.isEmpty && model.history.isEmpty {
                    LoadingStateCard(title: AppStrings.Profile.ownerModeration)
                } else if showsHistory {
                    historyContent
                } else if visible.isEmpty {
                    UnifiedEmptyStateCard(systemImage: "checkmark.shield", title: AppStrings.Profile.ownerModeration,
                        message: search.isEmpty ? AppStrings.Moderation.empty : AppStrings.Moderation.filteredEmptyMessage)
                } else {
                    LazyVStack(spacing: AppTheme.feedRowSpacing) {
                        ForEach(visible) { item in
                            Button { selected = item } label: { ContentReviewSummary(item: item) }
                                .buttonStyle(.plain).accessibilityIdentifier("content.moderation.open.\(item.id)")
                        }
                    }
                }
                if model.hasMore {
                    PrimaryActionButton(title: AppStrings.OrganizationReview.loadMore, isEnabled: !model.isLoading,
                        isLoading: model.isLoading, systemImage: "arrow.down") {
                        Task { await model.load(type: contentType, historyMode: showsHistory, reset: false) }
                    }.accessibilityIdentifier("content.moderation.more")
                }
            } else { InlineMessageCard(style: .error, message: AppStrings.Moderation.loadPermissionError) }
            Color.clear.frame(height: 96)
        }
        .task(id: "\(contentType)-\(showsHistory)-\(authState.user?.id ?? "")-\(canAccess)") { if canAccess { await reload() } }
        .onChange(of: canAccess) { _, allowed in if !allowed { selected = nil } }
        .appRefreshable { await reload() }
        .sheet(item: $selected, onDismiss: { Task { await reload() } }) { item in
            ContentModerationDetail(contentType: item.contentType, contentID: item.id)
        }
    }
    private func reload() async { guard canAccess else { return }; await model.load(type: contentType, historyMode: showsHistory, reset: true) }
    @ViewBuilder private var historyContent: some View {
        Text(ContentModerationCopy.historyRetention).font(.footnote).foregroundStyle(AppTheme.textSecondary)
        if model.history.isEmpty && !model.isLoading && model.error == nil {
            UnifiedEmptyStateCard(systemImage: "clock.arrow.circlepath", title: AppStrings.OrganizationReview.history, message: ContentModerationCopy.historyEmpty)
        }
        LazyVStack(spacing: AppTheme.feedRowSpacing) {
            ForEach(model.history) { entry in
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.title.isEmpty ? (entry.contentType == "news" ? AppStrings.Moderation.typeNews : AppStrings.Moderation.typeEvent) : entry.title).font(.headline)
                        Text(entry.status.title).foregroundStyle(AppTheme.accentPrimaryForeground)
                        if !entry.reason.isEmpty { Text(entry.reason).textSelection(.enabled) }
                        if !entry.organizationName.isEmpty { Text(entry.organizationName).font(.subheadline) }
                        if !entry.reviewerName.isEmpty { Text(entry.reviewerName).font(.caption) }
                        Text(LocalizationStore.dateString(from: Date(timeIntervalSince1970: entry.createdAt / 1000), timeStyle: .short)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
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
    private var operations: [String: String] = [:]
    private let client: ContentModerationClient
    init(client: ContentModerationClient? = nil) { self.client = client ?? .current }
    func load(type: String, id: String) async {
        guard !processing else { return }
        loading = true; defer { loading = false }
        do {
            let result = try await client.read(.init(action: "preview", contentType: type, contentId: id))
            guard let item = result.item, item.id == id, item.contentType == type else { throw AppError.validationFailed }
            self.item = item; error = nil
        } catch { self.item = nil; self.error = ContentModerationCopy.error(error) }
    }
    func decide(_ status: ModerationStatus, reason: String, principal: String) async {
        guard let item, item.canReview, !processing, !completed, !principal.isEmpty else { return }
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

struct ContentModerationDetail: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    let contentType: String
    let contentID: String
    @StateObject private var model = ContentReviewDetailModel()
    @State private var language: PublishedContentLanguage = LocalizationStore.language == .german ? .german : .ukrainian
    @State private var decision: ModerationStatus?
    @State private var reason = ""
    @State private var confirms = false
    @State private var editingNews: NewsPost?
    @State private var editingEvent: Event?
    @State private var editLoading = false
    @State private var editError: String?
    private var canDecide: Bool { model.item?.canReview == true && (authState.user.map { PermissionService.canModerate(section: .news, user: $0) } ?? false) }
    private var valid: Bool { decision != nil && reason.utf16.count <= 2000 && (decision == .approved || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    if model.loading { LoadingStateCard(title: ContentModerationCopy.openMaterial) }
                    if let error = model.error {
                        InlineMessageCard(style: .error, message: error)
                        Button(AppStrings.Moderation.retry) { Task { await model.load(type: contentType, id: contentID) } }.disabled(model.processing)
                    }
                    if let item = model.item {
                        Picker(AppStrings.OrganizationReview.section, selection: $language) {
                            ForEach(PublishedContentLanguage.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("content.review.language")
                        ContentMaterialPreview(item: item, language: language)
                        if !item.reason.isEmpty { InlineMessageCard(style: .info, message: item.reason) }
                        if let editError { InlineMessageCard(style: .error, message: editError) }
                        if item.canEdit == true && [.needsRevision, .rejected].contains(item.status) {
                            Text(ContentModerationCopy.editHelper).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                            PrimaryActionButton(title: ContentModerationCopy.editMaterial, isEnabled: !editLoading,
                                isLoading: editLoading, systemImage: "square.and.pencil") { Task { await openEditor(item) } }
                                .accessibilityIdentifier("content.review.edit")
                        }
                        if canDecide { decisionContent }
                    }
                }.padding(AppTheme.pageHorizontal).appCenteredContent()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackgroundView())
            .navigationTitle(ContentModerationCopy.openMaterial).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.Common.done) { dismiss() }.tint(AppTheme.accentPrimaryForeground).disabled(model.processing)
            } }
            .safeAreaInset(edge: .bottom) {
                if canDecide {
                    PrimaryActionButton(title: AppStrings.OrganizationReview.confirmDecision, isEnabled: valid && !model.processing,
                        isLoading: model.processing, systemImage: "checkmark.shield") { confirms = true }
                        .accessibilityIdentifier("content.review.confirm")
                        .padding(AppTheme.pageHorizontal).appCenteredContent().background(.regularMaterial)
                }
            }
            .alert(AppStrings.OrganizationReview.confirmDecision, isPresented: $confirms) {
                Button(decision?.title ?? AppStrings.OrganizationReview.confirmDecision, role: decision == .rejected ? .destructive : nil) {
                    guard canDecide, let decision, let principal = authState.user?.id else { return }
                    Task { await model.decide(decision, reason: reason, principal: principal) }
                }.accessibilityIdentifier("content.review.execute")
                Button(AppStrings.Common.cancel, role: .cancel) {}
            } message: { Text(ContentModerationCopy.confirmHelper) }
            .tint(AppTheme.accentPrimaryForeground)
            .interactiveDismissDisabled(model.processing)
            .task { await model.load(type: contentType, id: contentID) }
            .sheet(item: $editingNews, onDismiss: { Task { await model.load(type: contentType, id: contentID) } }) { news in
                NavigationStack { NewsEditorView(repository: FirestoreNewsRepository(), news: news) }
            }
            .sheet(item: $editingEvent, onDismiss: { Task { await model.load(type: contentType, id: contentID) } }) { event in
                NavigationStack { EventEditorView(repository: FirestoreEventRepository(), event: event) }
            }
            .onChange(of: model.completed) { _, completed in if completed { dismiss() } }
            .onChange(of: authState.user?.id) { _, _ in dismiss() }
        }
    }
    private func openEditor(_ item: ContentReviewItem) async {
        guard !editLoading, item.canEdit == true else { return }
        editLoading = true; defer { editLoading = false }
        do {
            if item.contentType == "news" { editingNews = try await FirestoreNewsRepository().fetchNews(id: item.id) }
            else { editingEvent = try await FirestoreEventRepository().fetchEvent(id: item.id) }
            editError = nil
        } catch { editError = ContentModerationCopy.error(error) }
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
                    }.buttonStyle(.plain).disabled(model.processing)
                        .accessibilityIdentifier("content.review.choice.\(status.rawValue)")
                }
                if decision != nil && decision != .approved {
                    Text(ContentModerationCopy.reasonHelper).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    TextField(AppStrings.Moderation.revisionMessage, text: $reason, axis: .vertical)
                        .lineLimit(3...8).textFieldStyle(.roundedBorder).disabled(model.processing)
                        .accessibilityIdentifier("content.review.reason")
                    Text("\(reason.utf16.count) / 2000").font(.caption)
                        .foregroundStyle(reason.utf16.count > 2000 ? AppTheme.accentDestructiveForeground : AppTheme.textSecondary)
                }
            }
        }
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
                if !item.city.isEmpty { Label([item.city, item.venue, item.address].filter { !$0.isEmpty }.joined(separator: ", "), systemImage: "mappin") }
                if let start = item.startDate { Text(LocalizationStore.dateString(from: Date(timeIntervalSince1970: start / 1000), timeStyle: .short)) }
                if let end = item.endDate { Text(LocalizationStore.dateString(from: Date(timeIntervalSince1970: end / 1000), timeStyle: .short)) }
                if let url = URL(string: item.imageURL), url.scheme == "https" {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() }
                        else if phase.error != nil { Label(ContentModerationCopy.imageUnavailable, systemImage: "photo.badge.exclamationmark") }
                        else { ProgressView() }
                    }.frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                }
                Text(item.text(language).summary).font(.headline).textSelection(.enabled)
                Text(item.text(language).body).textSelection(.enabled)
                if let url = URL(string: item.sourceURL), url.scheme == "https", url.host != nil {
                    Link(item.sourceName.isEmpty ? ContentModerationCopy.source : item.sourceName, destination: url)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum ContentModerationCopy {
    static var editMaterial: String { text("moderation.content.edit", "Виправити матеріал") }
    static var editHelper: String { text("moderation.content.edit_helper", "Після збереження виправлений матеріал буде повторно надіслано на перевірку.") }
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
    static func error(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: ns.code) {
            switch code {
            case .aborted, .failedPrecondition, .alreadyExists: return changed
            case .permissionDenied, .unauthenticated: return AppStrings.Moderation.actionPermissionError
            case .unavailable, .deadlineExceeded, .cancelled: return AppStrings.Moderation.actionNetworkError
            case .notFound: return AppStrings.Moderation.organizationRequestUnavailable
            default: break
            }
        }
        switch FirebaseReadErrorMapper.map(error) {
        case .network: return AppStrings.Moderation.actionNetworkError
        case .permissionDenied: return AppStrings.Moderation.actionPermissionError
        case .validationFailed: return changed
        case .notFound: return AppStrings.Moderation.organizationRequestUnavailable
        case .unknown: return AppStrings.Moderation.actionUnknownError
        }
    }
}
