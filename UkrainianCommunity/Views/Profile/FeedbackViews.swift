import SwiftUI

struct DsaStatementView: View {
    @EnvironmentObject private var authState: AuthState
    let statementID: String
    @State private var statement: DsaStatement?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadGeneration = UUID()

    var body: some View {
        PushedScreenShell(
            title: AppStrings.Safety.dsaStatementTitle,
            subtitle: AppStrings.Safety.dsaStatementSubtitle
        ) { EmptyView() } content: {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.sectionSpacing)
                    .accessibilityLabel(AppStrings.Safety.dsaStatementTitle)
                    .accessibilityIdentifier("dsa.statement.loading")
            } else if let errorMessage {
                ErrorStateCard(
                    systemImage: "exclamationmark.shield",
                    title: AppStrings.Safety.dsaStatementUnavailable,
                    message: errorMessage,
                    retryTitle: authState.user == nil ? nil : AppStrings.Action.retry
                ) {
                    Task { await loadStatement() }
                }
                .accessibilityIdentifier("dsa.statement.error")
            } else if let statement {
                statementContent(statement)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: statementID) { await loadStatement() }
        .onChange(of: ProfileAccessIdentity(user: authState.user)) { _, _ in
            statement = nil
            Task { await loadStatement() }
        }
    }

    @ViewBuilder
    private func statementContent(_ statement: DsaStatement) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                LabeledContent(AppStrings.Safety.caseNumberTitle, value: statement.caseNumber)
                LabeledContent(AppStrings.Common.status, value: FeedbackSupportCopy.status(statement.status))
                if !statement.sourceType.isEmpty {
                    LabeledContent(AppStrings.Safety.contentTypeTitle, value: ContentReportTargetType(rawValue: statement.sourceType)?.title ?? statement.sourceType)
                }
                if !statement.sourceID.isEmpty {
                    LabeledContent(AppStrings.Safety.contentIdentifierTitle, value: statement.sourceID)
                }
            }
        }

        if let decision = statement.decision {
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    statementField(AppStrings.Safety.dsaOutcomeTitle, decision.outcome == "removed" ? AppStrings.Safety.dsaOutcomeRemoved : AppStrings.Safety.dsaOutcomeNoAction)
                    statementField(AppStrings.Safety.dsaFactsTitle, decision.factsAndCircumstances)
                    statementField(AppStrings.Safety.legalBasisTitle, decision.legalBasis)
                    statementField(AppStrings.Safety.dsaTermsBasisTitle, decision.termsBasis)
                    statementField(AppStrings.Safety.dsaTerritoryTitle, decision.territorialScope)
                    statementField(AppStrings.Safety.dsaDurationTitle, decision.duration)
                    statementField(AppStrings.Safety.dsaRedressTitle, decision.redressInformation)
                    LabeledContent(AppStrings.Safety.automationTitle, value: decision.automationUsed ? AppStrings.Safety.automationYes : AppStrings.Safety.automationNo)
                }
            }
        }

        if let appeal = statement.appealDecision {
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Text(AppStrings.Safety.dsaAppealTitle)
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                    statementField(AppStrings.Safety.dsaAppealOutcomeTitle, appeal.outcome == "upheld" ? AppStrings.Safety.dsaAppealUpheld : AppStrings.Safety.dsaAppealChanged)
                    statementField(AppStrings.Safety.dsaAppealReasonTitle, appeal.reason)
                }
            }
        }

        Text(AppStrings.Safety.dsaStatementPrivacyNote)
            .font(AppTheme.metadataFont)
            .foregroundStyle(AppTheme.textSecondary)
    }

    @ViewBuilder
    private func statementField(_ title: String, _ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.metadataFont)
                    .foregroundStyle(AppTheme.textSecondary)
                Text(value)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
            }
        }
    }

    @MainActor
    private func loadStatement() async {
        loadGeneration = UUID()
        let expectedGeneration = loadGeneration
        let identity = ProfileAccessIdentity(user: authState.user)
        guard let userID = authState.user?.id else {
            isLoading = false
            errorMessage = AppStrings.Safety.dsaStatementSignInRequired
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            _ = userID
            let response = try await CloudFunctionsClient().getMyDsaStatement(reportID: statementID)
            guard loadGeneration == expectedGeneration, ProfileAccessIdentity(user: authState.user) == identity else { return }
            statement = DsaStatement(response: response)
        } catch {
            guard loadGeneration == expectedGeneration, ProfileAccessIdentity(user: authState.user) == identity else { return }
            errorMessage = AppStrings.Safety.dsaStatementLoadError
        }
        isLoading = false
    }
}

private nonisolated struct DsaStatement {
    nonisolated struct Decision {
        let outcome: String
        let factsAndCircumstances: String
        let legalBasis: String?
        let termsBasis: String?
        let territorialScope: String
        let duration: String
        let redressInformation: String
        let automationUsed: Bool

        init(_ value: DsaStatementFunctionResponse.Decision) {
            outcome = value.outcome
            factsAndCircumstances = value.factsAndCircumstances
            legalBasis = value.legalBasis
            termsBasis = value.termsBasis
            territorialScope = value.territorialScope
            duration = value.duration
            redressInformation = value.redressInformation
            automationUsed = value.automationUsed
        }
    }

    nonisolated struct AppealDecision {
        let outcome: String
        let reason: String

        init(_ value: DsaStatementFunctionResponse.AppealDecision) {
            outcome = value.outcome
            reason = value.reason
        }
    }

    let id: String
    let caseNumber: String
    let status: String
    let sourceType: String
    let sourceID: String
    let decision: Decision?
    let appealDecision: AppealDecision?

    init(response: DsaStatementFunctionResponse) {
        id = response.id
        caseNumber = response.caseNumber
        status = response.status
        sourceType = response.sourceType
        sourceID = response.sourceId
        decision = response.decision.map(Decision.init)
        appealDecision = response.appealDecision.map(AppealDecision.init)
    }
}

private enum MyFeedbackFilter: String, CaseIterable, Identifiable {
    case all
    case open
    case answered
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppStrings.Home.filterAll
        case .open: AppStrings.Feedback.filterOpen
        case .answered: AppStrings.Feedback.filterAnswered
        case .closed: AppStrings.Feedback.filterClosed
        }
    }

    func includes(_ item: FeedbackItem) -> Bool {
        switch self {
        case .all: true
        case .open: [.open, .reviewed, .inProgress].contains(item.status)
        case .answered: item.status.isAnswered
        case .closed: item.status.isClosed
        }
    }
}

struct MyFeedbackView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: MyFeedbackViewModel
    let currentUserID: String
    let initialFeedbackID: String?
    @State private var selectedFeedback: FeedbackItem?
    @State private var handledInitialFeedbackID: String?
    @State private var selectedFilter: MyFeedbackFilter = .all
    @State private var sortOption: AppListSortOption = .newest
    @State private var searchText = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(viewModel: MyFeedbackViewModel, currentUserID: String, initialFeedbackID: String? = nil) {
        self.viewModel = viewModel
        self.currentUserID = currentUserID
        self.initialFeedbackID = initialFeedbackID
    }

    private var filteredItems: [FeedbackItem] {
        return viewModel.items.filter { item in
            selectedFilter.includes(item)
                && LocalSearchMatcher.matches(
                    query: searchText,
                    values: [item.type.title, item.subject, item.message, item.lastMessageText, item.id]
                )
        }.sorted(by: feedbackSort)
    }

    var body: some View {
        PushedScreenShell(
            title: AppStrings.Feedback.myFeedbackTitle,
            subtitle: AppStrings.Feedback.myFeedbackSubtitle
        ) { EmptyView() } content: {
            if !viewModel.items.isEmpty {
                myFeedbackControls
            }
            feedbackContent
        }
        .tint(AppTheme.accentPrimaryForeground)
        .navigationTitle(AppStrings.Feedback.myFeedbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(currentUserID):\(initialFeedbackID ?? "")") {
            await viewModel.loadIfNeeded(userID: currentUserID)
            guard let initialFeedbackID else { return }
            let initialKey = "\(currentUserID):\(initialFeedbackID)"
            guard handledInitialFeedbackID != initialKey else { return }
            if let item = await viewModel.feedback(id: initialFeedbackID, userID: currentUserID) {
                handledInitialFeedbackID = initialKey
                open(item)
            }
        }
        .appRefreshable {
            await viewModel.refresh(userID: currentUserID)
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedFeedback != nil },
            set: { if !$0 { selectedFeedback = nil } }
        )) {
            if let item = selectedFeedback {
                let currentItem = currentFeedbackItem(for: item)
                Group {
                if viewModel.detailStates[item.id]?.isReady == true {
                FeedbackConversationView(
                    item: currentItem,
                    messages: viewModel.messages(for: currentItem),
                    isLoadingMessages: viewModel.loadingMessageFeedbackIDs.contains(currentItem.id),
                    isSending: viewModel.sendingMessageFeedbackIDs.contains(currentItem.id),
                    messageErrorMessage: viewModel.messageErrorsByFeedbackID[currentItem.id].map(feedbackErrorMessage(_:)),
                    hasMoreMessages: viewModel.hasMoreMessages(for: currentItem.id),
                    isLoadingMoreMessages: viewModel.loadingMoreMessageFeedbackIDs.contains(currentItem.id),
                    actionErrorMessage: viewModel.actionError(for: currentItem.id).map(feedbackActionErrorMessage(_:)),
                    allowsClose: false,
                    onLoad: {},
                    onRetryMessages: {
                        Task { await viewModel.loadMessages(for: currentItem) }
                    },
                    onLoadMoreMessages: {
                        Task { await viewModel.loadMoreMessages(for: currentItem) }
                    },
                    onSend: { text in
                        guard let user = authState.user else { return false }
                        let latestItem = currentFeedbackItem(for: currentItem)
                        let sent = await viewModel.sendMessage(text, feedback: latestItem, user: user)
                        if sent, let updatedItem = viewModel.items.first(where: { $0.id == latestItem.id }) {
                            selectedFeedback = updatedItem
                        }
                        return sent
                    },
                    onStop: {
                        viewModel.stopListeningMessages(for: currentItem.id)
                        viewModel.clearActionError()
                    },
                    onClose: nil,
                    onAppeal: { reason in
                        await viewModel.submitDsaAppeal(reason: reason, feedback: currentFeedbackItem(for: currentItem), userID: currentUserID)
                    },
                    usesNavigationStack: false
                )
                .toolbar(.visible, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                } else {
                    FeedbackRecordStateView(state: viewModel.detailStates[item.id],
                        errorMessage: AppStrings.Feedback.loadFailed,
                        onRetry: { Task { await loadSelectedDetail(item) } })
                }
                }
                .task(id: item.id) { await loadSelectedDetail(item) }
            }
        }
    }

    private var myFeedbackControls: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Menu {
                            Picker(AppStrings.Feedback.inboxFilter, selection: $selectedFilter) {
                                myFeedbackFilterOptions
                            }
                        } label: {
                            Label(myFeedbackFilterTitle(selectedFilter), systemImage: "line.3.horizontal.decrease.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: AppTheme.searchControlHeight, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Picker(AppStrings.Feedback.inboxFilter, selection: $selectedFilter) {
                            myFeedbackFilterOptions
                        }
                        .pickerStyle(.segmented)
                    }
                }

                AppHorizontalFilterRow {
                    AppSortMenu(selection: $sortOption, options: [.newest, .oldest])
                }

                AppSearchField(placeholder: AppStrings.Feedback.myFeedbackSearchPlaceholder, text: $searchText, fieldID: "feedback.mine.search")
                if viewModel.hasMore && viewModel.error == nil {
                    Text(FeedbackSupportCopy.loadedScope)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var myFeedbackFilterOptions: some View {
        ForEach(MyFeedbackFilter.allCases) { filter in
            Text(myFeedbackFilterTitle(filter)).tag(filter)
        }
    }

    private func myFeedbackFilterTitle(_ filter: MyFeedbackFilter) -> String {
        "\(filter.title) \(viewModel.items.filter { filter.includes($0) }.count)"
    }

    private func feedbackSort(_ lhs: FeedbackItem, _ rhs: FeedbackItem) -> Bool {
        let lhsDate = lhs.lastMessageAt ?? lhs.updatedAt
        let rhsDate = rhs.lastMessageAt ?? rhs.updatedAt
        switch sortOption {
        case .oldest:
            return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate < rhsDate
        default:
            return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate > rhsDate
        }
    }

    @ViewBuilder
    private var feedbackContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            LoadingStateCard(title: AppStrings.Feedback.myFeedbackTitle).accessibilityIdentifier("feedback.mine.loading")
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Feedback.myFeedbackTitle,
                message: feedbackErrorMessage(error)
            ) {
                PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh(userID: currentUserID) }
                }.accessibilityIdentifier("feedback.mine.retry")
            }
        } else if viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "tray",
                title: AppStrings.Feedback.myFeedbackTitle,
                message: AppStrings.Feedback.myFeedbackEmpty
            )
        } else if filteredItems.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "line.3.horizontal.decrease.circle",
                title: AppStrings.Search.noResultsTitle,
                message: AppStrings.Search.noResultsMessage
            ) {
                if viewModel.hasMore && viewModel.error == nil {
                    PrimaryActionButton(
                        title: AppStrings.Search.loadMoreContent,
                        isEnabled: !viewModel.isLoadingMore,
                        isLoading: viewModel.isLoadingMore,
                        systemImage: "arrow.down.circle"
                    ) { Task { await viewModel.loadMore(userID: currentUserID) } }
                }
            }
        } else {
            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                if let actionError = viewModel.actionError {
                    InlineMessageCard(style: .error, message: feedbackActionErrorMessage(actionError))
                }

                if let error = viewModel.error, !viewModel.failedLoadMore {
                    InlineMessageCard(style: .error, message: feedbackErrorMessage(error))
                    PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                        Task { await viewModel.retry(userID: currentUserID) }
                    }.accessibilityIdentifier("feedback.mine.retry")
                }

                ForEach(filteredItems) { item in
                    Button {
                        open(item)
                    } label: {
                        FeedbackUserRequestCard(item: item)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("feedback.mine.open.\(item.id)")
                }

                if let error = viewModel.error, viewModel.failedLoadMore {
                    InlineMessageCard(style: .error, message: feedbackErrorMessage(error))
                    PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                        Task { await viewModel.retry(userID: currentUserID) }
                    }.accessibilityIdentifier("feedback.mine.retry")
                }

                if viewModel.hasMore && viewModel.error == nil {
                    PrimaryActionButton(
                        title: AppStrings.Search.loadMoreContent,
                        isEnabled: !viewModel.isLoadingMore,
                        isLoading: viewModel.isLoadingMore,
                        systemImage: "arrow.down.circle"
                    ) { Task { await viewModel.loadMore(userID: currentUserID) } }
                }
            }
        }
    }

    private func feedbackErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return AppStrings.Moderation.loadPermissionError
        case .network:
            return FeedbackSupportCopy.loadNetworkError
        case .validationFailed, .notFound, .unknown:
            return AppStrings.Feedback.loadFailed
        }
    }

    private func feedbackActionErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            AppStrings.Feedback.actionPermissionFailed
        case .network:
            AppStrings.Feedback.actionNetworkFailed
        case .validationFailed, .notFound, .unknown:
            AppStrings.Feedback.sendMessageFailed
        }
    }

    private func currentFeedbackItem(for item: FeedbackItem) -> FeedbackItem {
        viewModel.items.first { $0.id == item.id } ?? item
    }

    private func loadSelectedDetail(_ item: FeedbackItem) async {
        guard let fresh = await viewModel.prepareDetail(id: item.id, userID: currentUserID),
              !Task.isCancelled, selectedFeedback?.id == item.id else { return }
        await viewModel.acknowledgeRead(fresh, userID: currentUserID)
        guard !Task.isCancelled, selectedFeedback?.id == item.id else { return }
        await viewModel.loadMessages(for: fresh)
    }

    private func open(_ item: FeedbackItem) {
        viewModel.clearActionError()
        viewModel.invalidateDetail(id: item.id)
        selectedFeedback = item
    }
}

private struct FeedbackUserRequestCard: View {
    let item: FeedbackItem

    private var previewText: String {
        if let lastMessageText = item.lastMessageText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastMessageText.isEmpty {
            return lastMessageText
        }
        return item.message
    }

    private var previewDate: Date {
        item.lastMessageAt ?? item.updatedAt
    }

    private var previewRoleTitle: String? {
        item.lastMessageByRole?.title
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.type.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .overlay(alignment: .topTrailing) {
                            if item.unreadForUser {
                                Circle()
                                    .fill(AppTheme.accentDestructive)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 12, y: -4)
                                    .accessibilityLabel(AppStrings.Feedback.unread)
                            }
                        }

                    Spacer(minLength: 0)

                    FeedbackStatusBadge(status: item.status, userFacing: true)
                }

                if let subject = item.subject, !subject.isEmpty {
                    Text(subject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                Text(previewText)
                    .font(.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let previewRoleTitle {
                    FeedbackMetadataRow(systemImage: "person.crop.circle", title: previewRoleTitle)
                }

                FeedbackMetadataRow(systemImage: "calendar", title: LocalizationStore.dateString(from: previewDate, dateStyle: .medium, timeStyle: .short))
            }
        }
    }
}

private enum FeedbackInboxFilter: String, CaseIterable, Identifiable {
    case open
    case answered
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open:
            AppStrings.Feedback.filterOpen
        case .answered:
            AppStrings.Feedback.filterAnswered
        case .closed:
            AppStrings.Feedback.filterClosed
        }
    }

    func includes(_ item: FeedbackItem) -> Bool {
        switch self {
        case .open:
            [.open, .reviewed, .inProgress].contains(item.status)
        case .answered:
            item.status.isAnswered
        case .closed:
            item.status.isClosed
        }
    }
}

struct FeedbackInboxView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: FeedbackInboxViewModel
    let initialFeedbackID: String?
    @State private var selectedFeedback: FeedbackItem?
    @State private var handledInitialFeedbackID: String?
    @State private var dsaDecisionItem: FeedbackItem?
    @State private var selectedFilter: FeedbackInboxFilter = .open
    @State private var sortOption: AppListSortOption = .newest
    @State private var searchText = ""
    @State private var feedbackPendingDeletion: FeedbackItem?
    @State private var isShowingClearConfirmation = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var filteredItems: [FeedbackItem] {
        viewModel.items.filter { selectedFilter.includes($0) }
    }

    init(
        repository: FeedbackRepository,
        notificationInboxRepository: NotificationInboxRepository? = nil,
        initialFeedbackID: String? = nil
    ) {
        self.initialFeedbackID = initialFeedbackID
        _viewModel = StateObject(wrappedValue: FeedbackInboxViewModel(
            repository: repository,
            notificationInboxRepository: notificationInboxRepository
        ))
    }

    var body: some View {
        AdminScreenShell(
            title: AppStrings.Feedback.inboxTitle,
            subtitle: AppStrings.Feedback.inboxSubtitle,
            tabBarHidden: false
        ) {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                inboxFilterPicker
                AppHorizontalFilterRow {
                    AppSortMenu(selection: $sortOption, options: [.newest, .oldest])
                }
                inboxSearchField
            }
        } metrics: {
            EmptyView()
        } trailingContent: {
            if PermissionService.isAppOwner(user: authState.user), !viewModel.items.isEmpty {
                if viewModel.isClearingInbox {
                    ProgressView().controlSize(.small)
                } else {
                    AppGlassIconButton(
                        systemImage: "trash",
                        accessibilityLabel: AppStrings.Feedback.clearInbox,
                        role: .destructive
                    ) {
                        isShowingClearConfirmation = true
                    }
                    .accessibilityIdentifier("feedbackInbox.clearAll")
                .disabled(!viewModel.updatingFeedbackIDs.isEmpty || !viewModel.deletingFeedbackIDs.isEmpty)
                }
            }
        } content: {
            inboxContent
        }
        .tint(AppTheme.accentPrimaryForeground)
        .navigationTitle(AppStrings.Feedback.inboxTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(authState.user?.id ?? ""):\(initialFeedbackID ?? ""):\(selectedFilter.rawValue):\(searchText):\(sortOption)") {
            guard let actorID = authState.user?.id else { viewModel.reset(); return }
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await viewModel.configure(actorID: actorID, filter: selectedFilter.rawValue, search: searchText, oldest: sortOption == .oldest)
            guard let initialFeedbackID else { return }
            let initialKey = "\(actorID):\(initialFeedbackID)"
            guard handledInitialFeedbackID != initialKey else { return }
            if let item = await viewModel.feedback(id: initialFeedbackID, actorID: actorID) {
                handledInitialFeedbackID = initialKey
                open(item, actorID: actorID)
            }
        }
        .onChange(of: ProfileAccessIdentity(user: authState.user)) { _, _ in
            viewModel.reset(); selectedFeedback = nil; dsaDecisionItem = nil; feedbackPendingDeletion = nil
            isShowingClearConfirmation = false
        }
        .appRefreshable {
            guard let actorID = authState.user?.id else { return }
            await viewModel.refresh(actorID: actorID)
        }
        .confirmationDialog(
            AppStrings.Feedback.clearInboxConfirmationTitle,
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.Feedback.clearInbox, role: .destructive) {
                Task { await viewModel.clearInbox() }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.Feedback.clearInboxConfirmationMessage)
        }
        .confirmationDialog(
            AppStrings.Feedback.deleteOneConfirmationTitle,
            isPresented: Binding(
                get: { feedbackPendingDeletion != nil },
                set: { if !$0 { feedbackPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.Feedback.deleteOne, role: .destructive) {
                guard let item = feedbackPendingDeletion else { return }
                feedbackPendingDeletion = nil
                Task {
                    let deleted = await viewModel.delete(item)
                    if deleted, selectedFeedback?.id == item.id { selectedFeedback = nil }
                }
            }
            Button(AppStrings.Common.cancel, role: .cancel) { feedbackPendingDeletion = nil }
        } message: {
            Text([feedbackPendingDeletion?.userDisplayName, feedbackPendingDeletion?.subject,
                  AppStrings.Feedback.deleteOneConfirmationMessage].compactMap { $0 }.joined(separator: "\n\n"))
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedFeedback != nil },
            set: { if !$0 { selectedFeedback = nil } }
        )) {
            if let item = selectedFeedback {
                let currentItem = currentFeedbackItem(for: item)
                Group {
                if viewModel.detailStates[item.id]?.isReady == true {
                FeedbackDetailView(
                    item: currentItem,
                    messages: viewModel.messages(for: currentItem),
                    isLoadingMessages: viewModel.loadingMessageFeedbackIDs.contains(currentItem.id),
                    isUpdating: viewModel.updatingFeedbackIDs.contains(currentItem.id),
                    messageErrorMessage: viewModel.messageErrorsByFeedbackID[currentItem.id].map(feedbackErrorMessage(_:)),
                    hasMoreMessages: viewModel.hasMoreMessages(for: currentItem.id),
                    isLoadingMoreMessages: viewModel.loadingMoreMessageFeedbackIDs.contains(currentItem.id),
                    actionErrorMessage: viewModel.actionError(for: currentItem.id).map(feedbackActionErrorMessage(_:)),
                    onLoad: {},
                    onRetryMessages: {
                        Task { await viewModel.loadMessages(for: currentItem) }
                    },
                    onLoadMoreMessages: {
                        Task { await viewModel.loadMoreMessages(for: currentItem) }
                    },
                    onSendReply: { reply in
                        guard let owner = authState.user else { return false }
                        let latestItem = currentFeedbackItem(for: currentItem)
                        let sent = await viewModel.sendReply(reply, to: latestItem, owner: owner)
                        if sent, let updatedItem = viewModel.items.first(where: { $0.id == latestItem.id }) {
                            selectedFeedback = updatedItem
                        }
                        return sent
                    },
                    onStop: {
                        viewModel.stopListeningMessages(for: currentItem.id)
                        viewModel.clearActionError()
                    },
                    onClose: closeAction(for: currentItem),
                    usesNavigationStack: false
                )
                .toolbar(.visible, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                } else {
                    FeedbackRecordStateView(state: viewModel.detailStates[item.id],
                        errorMessage: AppStrings.Feedback.loadFailed,
                        onRetry: { Task { await loadSelectedDetail(item) } })
                }
                }
                .task(id: item.id) { await loadSelectedDetail(item) }
            }
        }
        .sheet(item: $dsaDecisionItem) { item in
            if !PermissionService.isAppOwner(user: authState.user) {
                EmptyView().onAppear { dsaDecisionItem = nil }
            } else if item.dsaCase?.status == "appealed" {
                DsaAppealDecisionSheet(item: item) { request in
                    let succeeded = await viewModel.decideDsaAppeal(request, item: item)
                    if succeeded { dsaDecisionItem = nil; selectedFeedback = nil }
                    return succeeded
                }
                .presentationDetents([.large])
            } else {
                DsaDecisionSheet(item: item) { request in
                    let succeeded = await viewModel.decideDsaCase(request, item: item)
                    if succeeded { dsaDecisionItem = nil; selectedFeedback = nil }
                    return succeeded
                }
                .presentationDetents([.large])
            }
        }
    }

    @ViewBuilder
    private var inboxContent: some View {
        if let actionError = viewModel.actionError {
            InlineMessageCard(style: .error, message: feedbackActionErrorMessage(actionError))
                .accessibilityIdentifier("feedbackInbox.actionError")
        }
        if (viewModel.isLoading || !viewModel.hasLoadedQuery && viewModel.error == nil) && viewModel.items.isEmpty {
            LoadingStateCard(title: AppStrings.Feedback.inboxTitle).accessibilityIdentifier("feedbackInbox.loading")
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Feedback.inboxTitle,
                message: feedbackErrorMessage(error)
            ) {
                PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                    guard let actorID = authState.user?.id else { return }
                    Task { await viewModel.refresh(actorID: actorID) }
                }.accessibilityIdentifier("feedbackInbox.retry")
            }
        } else if viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "bubble.left.and.bubble.right",
                title: AppStrings.Feedback.inboxTitle,
                message: AppStrings.Feedback.inboxEmpty
            )
            .accessibilityIdentifier("feedbackInbox.empty")
        } else if filteredItems.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "line.3.horizontal.decrease.circle",
                title: selectedFilter.title,
                message: AppStrings.Feedback.inboxFilterEmpty
            ) {
                if viewModel.hasMore && viewModel.error == nil {
                    PrimaryActionButton(
                        title: AppStrings.Search.loadMoreContent,
                        isEnabled: !viewModel.isLoadingMore,
                        isLoading: viewModel.isLoadingMore,
                        systemImage: "arrow.down.circle"
                    ) {
                        guard let actorID = authState.user?.id else { return }
                        Task { await viewModel.loadMore(actorID: actorID) }
                    }
                }
            }
        } else {
            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                if let error = viewModel.error, !viewModel.failedLoadMore {
                    InlineMessageCard(style: .error, message: feedbackErrorMessage(error))
                    PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                        guard let actorID = authState.user?.id else { return }
                        Task { await viewModel.retry(actorID: actorID) }
                    }.accessibilityIdentifier("feedbackInbox.retry")
                }

                ForEach(filteredItems) { item in
                    VStack(alignment: .trailing, spacing: AppTheme.eventsMetadataSpacing) {
                        Button {
                            guard let actorID = authState.user?.id else { return }
                            open(item, actorID: actorID)
                        } label: {
                            FeedbackInboxRow(item: item)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("feedbackInbox.open.\(item.id)")

                        if PermissionService.canManageFeedback(user: authState.user) {
                            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                            Spacer(minLength: 0)
                            Menu {
                                Button(AppStrings.Feedback.markReviewed, systemImage: "eye") {
                                    Task { await viewModel.setStatus(.reviewed, for: item) }
                                }
                                Button(AppStrings.Feedback.statusInProgress, systemImage: "hammer") {
                                    Task { await viewModel.setStatus(.inProgress, for: item) }
                                }
                                Button(AppStrings.Feedback.statusDone, systemImage: "checkmark.circle") {
                                    Task { await viewModel.setStatus(.done, for: item) }
                                }
                            } label: {
                                AppGlassIconLabel(systemImage: "ellipsis")
                            }
                            .appGlassIconControl()
                            .fixedSize()
                            .accessibilityLabel(AppStrings.Common.status)
                            .accessibilityIdentifier("feedbackInbox.status.\(item.id)")
                            .disabled(viewModel.isClearingInbox || viewModel.updatingFeedbackIDs.contains(item.id) || item.dsaCase != nil)

                            if PermissionService.isAppOwner(user: authState.user) {
                            if viewModel.deletingFeedbackIDs.contains(item.id) {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                            } else if item.dsaCase != nil {
                                Image(systemName: "lock.shield")
                                    .accessibilityLabel(AppStrings.Feedback.retentionProtected)
                            } else {
                                AppGlassIconButton(
                                    systemImage: "trash",
                                    accessibilityLabel: AppStrings.Feedback.deleteOne,
                                    role: .destructive
                                ) {
                                    feedbackPendingDeletion = item
                                }
                                .accessibilityIdentifier("feedbackInbox.delete.\(item.id)")
                                .disabled(viewModel.isClearingInbox || viewModel.updatingFeedbackIDs.contains(item.id))
                            }
                            }
                            }
                        }
                    }
                }

                if let error = viewModel.error, viewModel.failedLoadMore {
                    InlineMessageCard(style: .error, message: feedbackErrorMessage(error))
                    PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                        guard let actorID = authState.user?.id else { return }
                        Task { await viewModel.retry(actorID: actorID) }
                    }.accessibilityIdentifier("feedbackInbox.retry")
                }

                if viewModel.hasMore && viewModel.error == nil {
                    PrimaryActionButton(
                        title: AppStrings.Search.loadMoreContent,
                        isEnabled: !viewModel.isLoadingMore,
                        isLoading: viewModel.isLoadingMore,
                        systemImage: "arrow.down.circle"
                    ) {
                        guard let actorID = authState.user?.id else { return }
                        Task { await viewModel.loadMore(actorID: actorID) }
                    }.accessibilityIdentifier("feedbackInbox.more")
                }
            }
        }
    }

    private func feedbackErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return AppStrings.Moderation.loadPermissionError
        case .network:
            return FeedbackSupportCopy.loadNetworkError
        case .validationFailed, .notFound, .unknown:
            return AppStrings.Feedback.loadFailed
        }
    }

    private func feedbackActionErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            AppStrings.Feedback.actionPermissionFailed
        case .network:
            AppStrings.Feedback.actionNetworkFailed
        case .validationFailed, .notFound, .unknown:
            AppStrings.Feedback.actionFailed
        }
    }

    private var inboxFilterPicker: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    Picker(AppStrings.Feedback.inboxFilter, selection: $selectedFilter) {
                        filterOptions
                    }
                } label: {
                    Label(filterTitle(selectedFilter), systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: AppTheme.searchControlHeight, alignment: .leading)
                }
                .buttonStyle(.bordered)
            } else {
                Picker(AppStrings.Feedback.inboxFilter, selection: $selectedFilter) {
                    filterOptions
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private var filterOptions: some View {
        ForEach(FeedbackInboxFilter.allCases) { filter in
            Text(filterTitle(filter)).tag(filter)
        }
    }

    private func filterTitle(_ filter: FeedbackInboxFilter) -> String {
        viewModel.counts[filter.rawValue].map { "\(filter.title) \($0)" } ?? "\(filter.title) —"
    }

    private func feedbackSort(_ lhs: FeedbackItem, _ rhs: FeedbackItem) -> Bool {
        let lhsDate = lhs.lastMessageAt ?? lhs.updatedAt
        let rhsDate = rhs.lastMessageAt ?? rhs.updatedAt
        switch sortOption {
        case .oldest:
            return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate < rhsDate
        default:
            return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate > rhsDate
        }
    }

    private var inboxSearchField: some View {
        AppSearchField(placeholder: AppStrings.Feedback.searchPlaceholder, text: $searchText, fieldID: "feedbackInbox.search", isSearching: viewModel.isLoading)
    }

    private func currentFeedbackItem(for item: FeedbackItem) -> FeedbackItem {
        viewModel.detailItems[item.id] ?? viewModel.items.first { $0.id == item.id } ?? item
    }

    private func closeAction(for item: FeedbackItem) -> (() -> Void)? {
        if item.dsaCase != nil, !PermissionService.isAppOwner(user: authState.user) { return nil }
        return {
            let latest = currentFeedbackItem(for: item)
            if latest.dsaCase != nil {
                dsaDecisionItem = latest
            } else {
                Task {
                    guard let owner = authState.user else { return }
                    let closed = await viewModel.close(latest, owner: owner)
                    if closed { selectedFeedback = nil }
                }
            }
        }
    }

    private func loadSelectedDetail(_ item: FeedbackItem) async {
        guard let actorID = authState.user?.id,
              let fresh = await viewModel.prepareDetail(id: item.id, actorID: actorID),
              !Task.isCancelled, selectedFeedback?.id == item.id else { return }
        await viewModel.acknowledgeRead(fresh, actorID: actorID)
        guard !Task.isCancelled, selectedFeedback?.id == item.id else { return }
        await viewModel.loadMessages(for: fresh)
    }

    private func open(_ item: FeedbackItem, actorID: String) {
        viewModel.clearActionError()
        viewModel.invalidateDetail(id: item.id)
        selectedFeedback = item
    }
}

private struct FeedbackInboxRow: View {
    let item: FeedbackItem

    private var authorTitle: String {
        if !item.userDisplayName.isEmpty {
            return item.userDisplayName
        }
        if !item.userId.isEmpty {
            return item.userId
        }
        return AppStrings.Profile.unknownUser
    }

    private var previewText: String {
        if let lastMessageText = item.lastMessageText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastMessageText.isEmpty {
            return lastMessageText
        }
        return item.message
    }

    private var previewDate: Date {
        item.lastMessageAt ?? item.updatedAt
    }

    private var previewRoleTitle: String? {
        item.lastMessageByRole?.title
    }

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if item.unreadForOwner {
                            Circle()
                                .fill(AppTheme.accentDestructive)
                                .frame(width: 10, height: 10)
                                .accessibilityLabel(AppStrings.Feedback.unread)
                        }
                    }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.type.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        FeedbackStatusBadge(status: item.status)
                    }

                    if let subject = item.subject, !subject.isEmpty {
                        Text(subject)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                    }

                    Text(previewText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Label(authorTitle, systemImage: "person")
                            .lineLimit(1)
                        Text("•")
                        Text(LocalizationStore.dateString(from: previewDate, dateStyle: .short, timeStyle: .short))
                            .lineLimit(1)
                        if let previewRoleTitle {
                            Text("•")
                            Text(previewRoleTitle)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                }

            }
        }
    }
}

private struct FeedbackDetailView: View {
    let item: FeedbackItem
    let messages: [FeedbackMessage]
    let isLoadingMessages: Bool
    let isUpdating: Bool
    let messageErrorMessage: String?
    let hasMoreMessages: Bool
    let isLoadingMoreMessages: Bool
    let actionErrorMessage: String?
    let onLoad: () -> Void
    let onRetryMessages: () -> Void
    let onLoadMoreMessages: () -> Void
    let onSendReply: (String) async -> Bool
    let onStop: () -> Void
    let onClose: (() -> Void)?
    var usesNavigationStack = true

    var body: some View {
        FeedbackConversationView(
            item: item,
            messages: messages,
            isLoadingMessages: isLoadingMessages,
            isSending: isUpdating,
            messageErrorMessage: messageErrorMessage,
            hasMoreMessages: hasMoreMessages,
            isLoadingMoreMessages: isLoadingMoreMessages,
            actionErrorMessage: actionErrorMessage,
            allowsClose: true,
            onLoad: onLoad,
            onRetryMessages: onRetryMessages,
            onLoadMoreMessages: onLoadMoreMessages,
            onSend: onSendReply,
            onStop: onStop,
            onClose: onClose,
            onAppeal: nil,
            usesNavigationStack: usesNavigationStack
        )
    }
}

private struct FeedbackConversationView: View {
    let item: FeedbackItem
    let messages: [FeedbackMessage]
    let isLoadingMessages: Bool
    let isSending: Bool
    let messageErrorMessage: String?
    let hasMoreMessages: Bool
    let isLoadingMoreMessages: Bool
    let actionErrorMessage: String?
    let allowsClose: Bool
    let onLoad: () -> Void
    let onRetryMessages: () -> Void
    let onLoadMoreMessages: () -> Void
    let onSend: (String) async -> Bool
    let onStop: () -> Void
    let onClose: (() -> Void)?
    let onAppeal: ((String) async -> Bool)?
    var usesNavigationStack = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var replyText = ""
    @State private var validationMessage: String?
    @State private var isShowingCloseConfirmation = false
    @State private var appealText = ""
    @State private var appealValidationMessage: String?

    @ViewBuilder
    var body: some View {
        if usesNavigationStack {
            NavigationStack { conversationContent }
        } else {
            conversationContent
        }
    }

    private var conversationContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            AppEditorSectionCard {
                                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                                    (dynamicTypeSize.isAccessibilitySize ?
                                        AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                                        Text(item.type.title)
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                                        FeedbackStatusBadge(status: item.status, userFacing: !allowsClose)
                                    }

                                    FeedbackMetadataRow(systemImage: "person", title: item.userDisplayName.isEmpty ? AppStrings.Profile.unknownUser : item.userDisplayName)
                                    FeedbackMetadataRow(systemImage: "calendar", title: LocalizationStore.dateString(from: item.createdAt, dateStyle: .medium, timeStyle: .short))
                                }
                            }

                            if let subject = item.subject, !subject.isEmpty {
                                AppEditorSectionCard {
                                    Text(subject)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                            }

                            if let reportContext = item.reportContext {
                                ContentReportContextCard(
                                    context: reportContext,
                                    occurrenceCount: item.occurrenceCount,
                                    isClosed: item.status.isClosed
                                )
                            }

                            if let dsaCase = item.dsaCase {
                                DsaCaseContextCard(dsaCase: dsaCase)
                            }

                            if let messageErrorMessage {
                                InlineMessageCard(style: .error, message: messageErrorMessage)
                                PrimaryActionButton(
                                    title: AppStrings.Moderation.retry,
                                    systemImage: "arrow.clockwise"
                                ) { onRetryMessages() }
                                .accessibilityIdentifier("feedback.messages.retry")
                            }

                            if isLoadingMessages && messages.isEmpty {
                                LoadingStateCard(title: AppStrings.Feedback.messagesTitle)
                            } else if messages.isEmpty {
                                UnifiedEmptyStateCard(
                                    systemImage: "bubble.left",
                                    title: AppStrings.Feedback.messagesTitle,
                                    message: AppStrings.Feedback.noMessages
                                )
                            } else {
                                VStack(spacing: 10) {
                                    if hasMoreMessages {
                                        PrimaryActionButton(
                                            title: AppStrings.Search.loadMoreContent,
                                            isEnabled: !isLoadingMoreMessages,
                                            isLoading: isLoadingMoreMessages,
                                            systemImage: "arrow.up.circle"
                                        ) { onLoadMoreMessages() }
                                    }
                                    ForEach(messages) { message in
                                        FeedbackMessageBubble(message: message)
                                            .id(message.id)
                                    }
                                }
                            }
                        }
                        .padding(AppTheme.pageHorizontal)
                        .padding(.bottom, AppTheme.sectionSpacing)
                        .appCenteredContent()
                    }
                    .onAppear {
                        scrollToLastMessage(with: proxy, animated: false)
                    }
                    .onChange(of: messages.last?.id) {
                        scrollToLastMessage(with: proxy)
                    }
                }

                Divider()

                ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let actionErrorMessage {
                        InlineMessageCard(style: .error, message: actionErrorMessage)
                    }
                    if item.status.isClosed {
                        Label(AppStrings.Feedback.closedMessage, systemImage: "lock")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if canAppeal {
                            appealEditor
                        }
                    } else {
                        ZStack(alignment: .topLeading) {
                            if replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(AppStrings.Feedback.addReply)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 14)
                            }

                            TextEditor(text: $replyText)
                                .disabled(isSending)
                                .accessibilityIdentifier("feedback.reply.text")
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 86, maxHeight: 120)
                                .padding(8)
                        }
                        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.borderSubtle)
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(replyText.count)/2000")
                                .foregroundStyle(AppTheme.textSecondary)
                            if let validationMessage, actionErrorMessage == nil {
                                Text(validationMessage)
                                    .foregroundStyle(AppTheme.accentDestructiveForeground)
                            }
                        }
                        .font(.caption)

                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                                replyActions
                            }
                        } else {
                            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                                replyActions
                            }
                        }
                    }
                }
                .padding(AppTheme.pageHorizontal)
                .padding(.vertical, 12)
                .appCenteredContent()
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.46 : 0.52))
                .background(AppTheme.pageBackground)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle(FeedbackSupportCopy.conversationTitle)
            .navigationBarBackButtonHidden(isSending)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppStrings.Common.done) {
                        dismiss()
                    }.disabled(isSending)
                }
            }
            .task {
                onLoad()
            }
            .onDisappear {
                onStop()
            }
            .confirmationDialog(
                AppStrings.Feedback.closeConfirmationTitle,
                isPresented: $isShowingCloseConfirmation
            ) {
                Button(AppStrings.Feedback.closeFeedback, role: .destructive) {
                    onClose?()
                }
                Button(AppStrings.Common.cancel, role: .cancel) {}
            } message: {
                Text(AppStrings.Feedback.closeConfirmationMessage)
            }
        }
    }

    private var canAppeal: Bool {
        guard let dsaCase = item.dsaCase,
              dsaCase.status == "decided",
              dsaCase.appeal == nil,
              let deadline = dsaCase.decision?.appealDeadline else { return false }
        return deadline > Date() && onAppeal != nil
    }

    private var appealEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(FeedbackSupportCopy.appealReason)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            TextField(FeedbackSupportCopy.appealReason, text: $appealText, axis: .vertical)
                .disabled(isSending)
                .accessibilityIdentifier("feedback.appeal.reason")
                .lineLimit(3...8)
                .padding(12)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppTheme.borderSubtle))
            if let appealValidationMessage {
                Text(appealValidationMessage).font(.caption).foregroundStyle(AppTheme.accentDestructiveForeground)
            }
            PrimaryActionButton(
                title: AppStrings.Safety.dsaAppealSubmit,
                isEnabled: FeedbackSupportValidation.text(appealText, minimum: 20, maximum: 5_000) && !isSending,
                isLoading: isSending,
                systemImage: "arrow.uturn.backward.circle"
            ) {
                submitAppeal()
            }
        }
        .padding(.top, 6)
    }

    private func submitAppeal() {
        let normalized = appealText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FeedbackSupportValidation.text(normalized, minimum: 20, maximum: 5_000), let onAppeal else {
            appealValidationMessage = AppStrings.Safety.explanationRequired
            return
        }
        Task {
            let succeeded = await onAppeal(normalized)
            if succeeded {
                appealText = ""
                appealValidationMessage = nil
                dismiss()
            } else {
                appealValidationMessage = AppStrings.Feedback.actionFailed
            }
        }
    }

    private func submitReply() {
        let trimmedReply = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedReply.isEmpty {
            validationMessage = AppStrings.Feedback.replyRequired
            return
        }

        if trimmedReply.count > 2000 {
            validationMessage = AppStrings.Feedback.replyTooLong
            return
        }

        validationMessage = nil
        Task {
            let sent = await onSend(trimmedReply)
            if sent {
                replyText = ""
                validationMessage = nil
            } else {
                validationMessage = "\(AppStrings.Feedback.sendMessageFailed) \(AppStrings.Feedback.tryAgain)"
            }
        }
    }

    @ViewBuilder
    private var replyActions: some View {
        PrimaryActionButton(
            title: isSending ? AppStrings.Feedback.sending : AppStrings.Feedback.send,
            isEnabled: !isSending && !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && replyText.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2000,
            isLoading: isSending,
            systemImage: "paperplane"
        ) {
            submitReply()
        }
        .accessibilityIdentifier("feedback.reply.send")

        if allowsClose, onClose != nil {
            Button {
                if item.dsaCase != nil { onClose?() }
                else { isShowingCloseConfirmation = true }
            } label: {
                Text(item.dsaCase == nil ? AppStrings.Feedback.closeFeedback : AppStrings.Safety.dsaDecisionAction)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentDestructiveForeground)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.iconButtonSize)
                    .padding(.horizontal, 12)
                    .background(AppTheme.accentDestructive.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityIdentifier("feedback.conversation.close")
        }
    }

    private func scrollToLastMessage(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastMessageID = messages.last?.id else { return }
        let action = {
            proxy.scrollTo(lastMessageID, anchor: .bottom)
        }

        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: 0.2), action)
        } else {
            action()
        }
    }
}

private struct DsaCaseContextCard: View {
    let dsaCase: DsaCaseSummary

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 20, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(AppStrings.Safety.caseNumberTitle).font(.subheadline.weight(.semibold))
                }
                Text(dsaCase.caseNumber)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let url = URL(string: dsaCase.exactLocation), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Link(destination: url) { Label(dsaCase.exactLocation, systemImage: "arrow.up.right.square") }
                        .font(.footnote).tint(AppTheme.accentPrimaryForeground)
                } else {
                    FeedbackMetadataRow(systemImage: "link", title: dsaCase.exactLocation)
                }
                Text(dsaCase.illegalExplanation)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let legalBasis = dsaCase.legalBasis, !legalBasis.isEmpty {
                    FeedbackMetadataRow(systemImage: "text.book.closed", title: legalBasis)
                }
                if let evidence = dsaCase.evidence, !evidence.isEmpty {
                    FeedbackMetadataRow(systemImage: "doc.text.magnifyingglass", title: evidence)
                }
                if let appeal = dsaCase.appeal {
                    Divider()
                    Label(AppStrings.Safety.dsaAppealTitle, systemImage: "arrow.uturn.backward.circle")
                        .font(.subheadline.weight(.semibold))
                    Text(appeal.reason)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label(AppStrings.Safety.goodFaithConfirmed, systemImage: "checkmark.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

private struct FeedbackOutcomeMenu: View {
    let title: String
    @Binding var selection: String
    let options: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
            Menu {
                ForEach(options, id: \.0) { option in
                    Button { selection = option.0 } label: {
                        if selection == option.0 { Label(option.1, systemImage: "checkmark") }
                        else { Text(option.1) }
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(options.first(where: { $0.0 == selection })?.1 ?? selection)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(.body).foregroundStyle(AppTheme.textPrimary)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 11))
            }
            .accessibilityLabel(title)
            .accessibilityValue(options.first(where: { $0.0 == selection })?.1 ?? selection)
        }
    }
}

private struct DsaAppealDecisionSheet: View {
    let item: FeedbackItem
    let onSubmit: (DsaAppealDecisionFunctionRequest) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var outcome = "upheld"
    @State private var reason = ""
    @State private var humanReviewConfirmed = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isSubmitting && FeedbackSupportValidation.text(reason, minimum: 20, maximum: 5_000) && humanReviewConfirmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    if let dsaCase = item.dsaCase {
                        AppEditorSectionCard {
                            Text(dsaCase.caseNumber).font(.caption).foregroundStyle(AppTheme.textSecondary)
                            DisclosureGroup(FeedbackSupportCopy.caseDetails) { DsaCaseContextCard(dsaCase: dsaCase) }
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    AppEditorSectionCard {
                        VStack(alignment: .leading, spacing: 16) {
                            FeedbackOutcomeMenu(title: AppStrings.Safety.dsaAppealOutcomeTitle, selection: $outcome,
                                options: [("upheld", AppStrings.Safety.dsaAppealUpheld), ("changed", AppStrings.Safety.dsaAppealChanged)])
                            .accessibilityIdentifier("feedback.dsa.appeal.outcome")
                            .disabled(isSubmitting)
                            TextField(AppStrings.Safety.dsaAppealReasonTitle, text: $reason, axis: .vertical)
                                .lineLimit(4...10)
                                .disabled(isSubmitting)
                                .accessibilityIdentifier("feedback.dsa.appeal.reason")
                                .padding(12)
                                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppTheme.borderSubtle))
                            Button { humanReviewConfirmed.toggle() } label: {
                                Label(AppStrings.Safety.dsaHumanReview, systemImage: humanReviewConfirmed ? "checkmark.square.fill" : "square")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isSubmitting)
                            .accessibilityIdentifier("feedback.dsa.appeal.humanReview")
                        }
                    }
                    if let errorMessage { InlineMessageCard(style: .error, message: errorMessage) }
                }
                .padding(AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.sectionSpacing)
                .appCenteredContent()
            }
            .background(AppTheme.pageBackground)
            .navigationTitle(AppStrings.Safety.dsaAppealTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(AppStrings.Common.cancel) { dismiss() }.disabled(isSubmitting) } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    PrimaryActionButton(title: AppStrings.Action.save, isEnabled: canSubmit, isLoading: isSubmitting, systemImage: "checkmark.seal") { submit() }
                        .accessibilityIdentifier("feedback.dsa.appeal.submit")
                        .padding(.horizontal, AppTheme.pageHorizontal)
                        .padding(.vertical, 12)
                        .appCenteredContent()
                }
                .background(AppTheme.pageBackground)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            let succeeded = await onSubmit(DsaAppealDecisionFunctionRequest(
                reportId: item.id,
                outcome: outcome,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                humanReviewConfirmed: true
            ))
            if !succeeded {
                errorMessage = AppStrings.Feedback.actionFailed
                isSubmitting = false
            }
        }
    }
}

private struct DsaDecisionSheet: View {
    let item: FeedbackItem
    let onSubmit: (DsaDecisionFunctionRequest) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var outcome = "noAction"
    @State private var facts = ""
    @State private var legalBasis = ""
    @State private var termsBasis = ""
    @State private var territorialScope = AppStrings.Safety.dsaTerritoryDefault
    @State private var duration = AppStrings.Safety.dsaDurationDefault
    @State private var redress = AppStrings.Safety.dsaRedressDefault
    @State private var humanReviewConfirmed = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isSubmitting && FeedbackSupportValidation.decision(
            facts: facts, legalBasis: legalBasis, termsBasis: termsBasis,
            territory: territorialScope, duration: duration, redress: redress,
            humanReviewed: humanReviewConfirmed
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    if let dsaCase = item.dsaCase {
                        AppEditorSectionCard {
                            Text(dsaCase.caseNumber).font(.caption).foregroundStyle(AppTheme.textSecondary)
                            DisclosureGroup(FeedbackSupportCopy.caseDetails) { DsaCaseContextCard(dsaCase: dsaCase) }
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    fieldCard.disabled(isSubmitting)
                    if let errorMessage { InlineMessageCard(style: .error, message: errorMessage) }
                }
                .padding(AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.sectionSpacing)
                .appCenteredContent()
            }
            .background(AppTheme.pageBackground)
            .navigationTitle(AppStrings.Safety.dsaDecisionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(AppStrings.Common.cancel) { dismiss() }.disabled(isSubmitting) }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    PrimaryActionButton(
                        title: AppStrings.Action.save,
                        isEnabled: canSubmit,
                        isLoading: isSubmitting,
                        systemImage: "checkmark.seal"
                    ) { submit() }
                    .accessibilityIdentifier("feedback.dsa.decision.submit")
                    .padding(.horizontal, AppTheme.pageHorizontal)
                    .padding(.vertical, 12)
                    .appCenteredContent()
                }
                .background(AppTheme.pageBackground)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var fieldCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                FeedbackOutcomeMenu(title: AppStrings.Safety.dsaOutcomeTitle, selection: $outcome,
                    options: [("noAction", AppStrings.Safety.dsaOutcomeNoAction), ("removed", AppStrings.Safety.dsaOutcomeRemoved)])
                dsaTextField(AppStrings.Safety.dsaFactsTitle, id: "facts", text: $facts, maximum: 5_000, axis: .vertical)
                dsaTextField(AppStrings.Safety.legalBasisTitle, id: "legal", text: $legalBasis, maximum: 2000, axis: .vertical)
                dsaTextField(AppStrings.Safety.dsaTermsBasisTitle, id: "terms", text: $termsBasis, maximum: 2000, axis: .vertical)
                dsaTextField(AppStrings.Safety.dsaTerritoryTitle, id: "territory", text: $territorialScope, maximum: 500)
                dsaTextField(AppStrings.Safety.dsaDurationTitle, id: "duration", text: $duration, maximum: 500)
                dsaTextField(AppStrings.Safety.dsaRedressTitle, id: "redress", text: $redress, maximum: 2000, axis: .vertical)
                Button { humanReviewConfirmed.toggle() } label: {
                    Label(
                        AppStrings.Safety.dsaHumanReview,
                        systemImage: humanReviewConfirmed ? "checkmark.square.fill" : "square"
                    )
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feedback.dsa.decision.humanReview")
            }
        }
    }

    private func dsaTextField(_ title: String, id: String, text: Binding<String>, maximum: Int, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
            Text("\(text.wrappedValue.utf16.count)/\(maximum)")
                .font(.caption)
                .foregroundStyle(text.wrappedValue.utf16.count > maximum ? AppTheme.accentDestructiveForeground : AppTheme.textSecondary)
            TextField(title, text: text, axis: axis)
                .lineLimit(axis == .vertical ? 3...8 : 1...1)
                .accessibilityIdentifier("feedback.dsa.field." + id)
                .padding(12)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppTheme.borderSubtle))
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let request = DsaDecisionFunctionRequest(
            reportId: item.id,
            outcome: outcome,
            factsAndCircumstances: facts,
            legalBasis: normalized(legalBasis),
            termsBasis: normalized(termsBasis),
            territorialScope: territorialScope,
            duration: duration,
            redressInformation: redress,
            humanReviewConfirmed: true
        )
        Task {
            let succeeded = await onSubmit(request)
            if !succeeded {
                errorMessage = AppStrings.Feedback.actionFailed
                isSubmitting = false
            }
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ContentReportContextCard: View {
    let context: ContentReportContext
    let occurrenceCount: Int
    var isClosed = false

    private var slaText: String {
        if context.slaDueAt < Date() {
            return AppStrings.Safety.slaOverdue
        }
        return AppStrings.Safety.slaDue(
            LocalizationStore.dateString(
                from: context.slaDueAt,
                dateStyle: .medium,
                timeStyle: .short
            )
        )
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(AppStrings.Safety.moderationContext, systemImage: "shield.lefthalf.filled")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Button { openTarget() } label: {
                    Label("\(context.targetType.title): \(context.targetTitle)", systemImage: context.targetType.systemImage)
                        .font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .tint(AppTheme.accentPrimaryForeground)
                .accessibilityIdentifier("feedback.report.openTarget")
                FeedbackMetadataRow(systemImage: "exclamationmark.bubble", title: context.reason.title)
                if !isClosed {
                FeedbackMetadataRow(
                    systemImage: context.isUrgent ? "clock.badge.exclamationmark" : "clock",
                    title: slaText
                )
                }

                if occurrenceCount > 1 {
                    FeedbackMetadataRow(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: AppStrings.Safety.reportOccurrences(occurrenceCount)
                    )
                }

                if !context.targetExcerpt.isEmpty {
                    Text(context.targetExcerpt)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func openTarget() {
        let action: AppNotificationActionType
        let id: String
        switch context.targetType {
        case .news: action = .openNews; id = context.targetId
        case .event: action = .openEvent; id = context.targetId
        case .organization: action = .openOrganization; id = context.targetId
        case .comment:
            guard let parent = context.parentType, let parentID = context.parentId else { return }
            action = parent == .news ? .openNews : parent == .event ? .openEvent : .openOrganization
            id = parentID
        }
        if let route = RemoteNotificationRoute(notificationId: nil, type: .contentModerationChanged,
            sourceType: nil, sourceId: id, actionType: action, actionTargetId: id, route: nil, routeTargetId: nil) {
            RemoteNotificationRouteCoordinator.shared.receive(route)
        }
    }

}

private struct FeedbackMessageBubble: View {
    let message: FeedbackMessage

    private var isOwnerMessage: Bool {
        message.senderRole == .owner
    }

    var body: some View {
        HStack {
            if isOwnerMessage {
                Spacer(minLength: 32)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(message.isSystem ? AppStrings.Feedback.supportLabel : message.senderRole.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isOwnerMessage ? AppTheme.accentPrimaryForeground : AppTheme.textSecondary)

                    Text(LocalizationStore.dateString(from: message.createdAt, dateStyle: .short, timeStyle: .short))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                (isOwnerMessage ? AppTheme.accentPrimary.opacity(0.10) : AppTheme.surfaceSecondary),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.borderSubtle)
            )
            .frame(maxWidth: 520, alignment: isOwnerMessage ? .trailing : .leading)

            if !isOwnerMessage {
                Spacer(minLength: 32)
            }
        }
    }
}

private struct FeedbackStatusBadge: View {
    let status: FeedbackStatus
    var userFacing = false

    private var tint: Color {
        switch status {
        case .open:
            return AppTheme.accentPrimaryForeground
        case .reviewed, .inProgress:
            return AppTheme.accentPrimaryForeground
        case .answered, .done:
            return AppTheme.textSecondary
        case .archived, .closed:
            return AppTheme.accentDestructiveForeground
        }
    }

    private var title: String {
        if userFacing && status == .open {
            return AppStrings.Feedback.statusWaitingReply
        }
        return status.title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FeedbackMetadataRow: View {
    let systemImage: String
    let title: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(2)
    }
}

struct FeedbackComposerCard: View {
    @Binding var selectedFeedbackType: FeedbackType
    @Binding var feedbackMessage: String
    let statusMessage: String?
    let isSubmitting: Bool
    let onSubmit: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var trimmedMessage: String {
        feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isMessageValid: Bool {
        !trimmedMessage.isEmpty && trimmedMessage.count <= 2000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.Feedback.fieldType)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        feedbackTypePicker
                    }
                } else {
                    LabeledContent(AppStrings.Feedback.fieldType) {
                        feedbackTypePicker
                    }
                }
            }
            .accessibilityLabel(AppStrings.Feedback.fieldType)

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.Feedback.fieldMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)

                ZStack(alignment: .topLeading) {
                    if feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(AppStrings.Feedback.fieldMessage)
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 14)
                    }

                    TextEditor(text: $feedbackMessage)
                        .accessibilityIdentifier("feedback.compose.text")
                        .disabled(isSubmitting)
                        .scrollContentBackground(.hidden)
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 140 : 104)
                        .padding(8)
                        .background(Color.clear)
                }
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.borderSubtle)
                )
                .accessibilityLabel(AppStrings.Feedback.fieldMessage)

                HStack {
                    if trimmedMessage.count > 2000 {
                        Text(AppStrings.Feedback.messageTooLong)
                            .foregroundStyle(AppTheme.accentDestructiveForeground)
                    }
                    Spacer(minLength: 0)
                    Text("\(trimmedMessage.count)/2000")
                        .foregroundStyle(trimmedMessage.count > 2000 ? AppTheme.accentDestructiveForeground : AppTheme.textSecondary)
                }
                .font(.caption)
            }

            if let statusMessage {
                InlineMessageCard(
                    style: statusMessage == AppStrings.Feedback.submitted ? .success : .error,
                    message: statusMessage
                )
            }

            PrimaryActionButton(
                title: AppStrings.Feedback.submit,
                isEnabled: !isSubmitting && isMessageValid,
                isLoading: isSubmitting,
                systemImage: "paperplane"
            ) {
                onSubmit()
            }
            .accessibilityLabel(AppStrings.Feedback.submit)
            .accessibilityIdentifier("feedback.compose.submit")
        }
        .padding(.vertical, 2)
    }

    private var feedbackTypePicker: some View {
        Picker(AppStrings.Feedback.fieldType, selection: $selectedFeedbackType) {
            ForEach(FeedbackType.allCases) { feedbackType in
                Text(feedbackType.title).tag(feedbackType)
            }
        }
        .pickerStyle(.menu)
        .disabled(isSubmitting)
    }
}
