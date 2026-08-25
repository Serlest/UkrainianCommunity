import SwiftUI

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
        case .open: item.status == .open
        case .answered: item.status.isAnswered
        case .closed: item.status.isClosed
        }
    }
}

struct MyFeedbackView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: MyFeedbackViewModel
    let currentUserID: String
    @State private var selectedFeedback: FeedbackItem?
    @State private var selectedFilter: MyFeedbackFilter = .all
    @State private var sortOption: AppListSortOption = .newest
    @State private var searchText = ""
    @State private var isShowingClearConfirmation = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var filteredItems: [FeedbackItem] {
        return viewModel.items.filter { item in
            selectedFilter.includes(item)
                && LocalSearchMatcher.matches(
                    query: searchText,
                    values: [item.type.title, item.message, item.lastMessageText, item.id]
                )
        }.sorted(by: feedbackSort)
    }

    var body: some View {
        PushedScreenShell(
            title: AppStrings.Feedback.myFeedbackTitle,
            subtitle: AppStrings.Feedback.myFeedbackSubtitle
        ) {
            if viewModel.isClearing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                    .accessibilityLabel(AppStrings.Feedback.clearMyFeedback)
            } else if !viewModel.items.isEmpty {
                AppGlassIconButton(
                    systemImage: "trash",
                    accessibilityLabel: AppStrings.Feedback.clearMyFeedback,
                    role: .destructive
                ) {
                    isShowingClearConfirmation = true
                }
                .accessibilityIdentifier("myFeedback.clearAll")
            }
        } content: {
            if !viewModel.items.isEmpty {
                myFeedbackControls
            }
            feedbackContent
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(AppStrings.Feedback.myFeedbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: currentUserID) {
            await viewModel.loadIfNeeded(userID: currentUserID)
        }
        .refreshable {
            await viewModel.refresh(userID: currentUserID)
        }
        .confirmationDialog(
            AppStrings.Feedback.clearMyFeedbackConfirmationTitle,
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.Feedback.clearMyFeedback, role: .destructive) {
                Task { await viewModel.clearMyFeedback() }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.Feedback.clearMyFeedbackConfirmationMessage)
        }
        .sheet(item: $selectedFeedback) { item in
            let currentItem = currentFeedbackItem(for: item)
            FeedbackConversationSheet(
                item: currentItem,
                messages: viewModel.messages(for: currentItem),
                isLoadingMessages: viewModel.loadingMessageFeedbackIDs.contains(currentItem.id),
                isSending: viewModel.sendingMessageFeedbackIDs.contains(currentItem.id),
                actionErrorMessage: viewModel.actionError.map(feedbackActionErrorMessage(_:)),
                allowsClose: false,
                onLoad: {
                    Task { await viewModel.loadMessages(for: currentItem) }
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
                onClose: nil
            )
            .presentationDetents([.medium, .large])
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

                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField(AppStrings.Feedback.myFeedbackSearchPlaceholder, text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        AppSearchClearButton { searchText = "" }
                    }
                }
                .padding(.horizontal, AppTheme.inputHorizontalPadding)
                .frame(minHeight: AppTheme.searchControlHeight)
                .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
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
            LoadingStateCard(title: AppStrings.Feedback.myFeedbackTitle)
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Feedback.myFeedbackTitle,
                message: feedbackErrorMessage(error)
            ) {
                PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh(userID: currentUserID) }
                }
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
            )
        } else {
            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                if let actionError = viewModel.actionError {
                    InlineMessageCard(style: .error, message: feedbackActionErrorMessage(actionError))
                }

                if let error = viewModel.error {
                    InlineMessageCard(style: .error, message: feedbackErrorMessage(error))
                }

                ForEach(filteredItems) { item in
                    Button {
                        selectedFeedback = item
                    } label: {
                        FeedbackUserRequestCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func feedbackErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return AppStrings.Moderation.loadPermissionError
        case .network:
            return AppStrings.Moderation.loadNetworkError
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

                    Spacer(minLength: 0)

                    FeedbackStatusBadge(status: item.status, userFacing: true)
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
            item.status == .open
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
    @State private var selectedFeedback: FeedbackItem?
    @State private var selectedFilter: FeedbackInboxFilter = .open
    @State private var sortOption: AppListSortOption = .newest
    @State private var searchText = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var filteredItems: [FeedbackItem] {
        return viewModel.items.filter { item in
            selectedFilter.includes(item)
                && LocalSearchMatcher.matches(
                    query: searchText,
                    values: [item.userDisplayName, item.userId, item.type.title, item.message, item.lastMessageText, item.id]
                )
        }.sorted(by: feedbackSort)
    }

    init(
        repository: FeedbackRepository,
        notificationInboxRepository: NotificationInboxRepository? = nil
    ) {
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
            EmptyView()
        } content: {
            inboxContent
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(AppStrings.Feedback.inboxTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $selectedFeedback) { item in
            let currentItem = currentFeedbackItem(for: item)
            FeedbackDetailSheet(
                item: currentItem,
                messages: viewModel.messages(for: currentItem),
                isLoadingMessages: viewModel.loadingMessageFeedbackIDs.contains(currentItem.id),
                isUpdating: viewModel.updatingFeedbackIDs.contains(currentItem.id),
                actionErrorMessage: viewModel.actionError.map(feedbackActionErrorMessage(_:)),
                onLoad: {
                    Task { await viewModel.loadMessages(for: currentItem) }
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
                },
                onClose: {
                    Task {
                        let closed = await viewModel.close(currentFeedbackItem(for: currentItem))
                        if closed { selectedFeedback = nil }
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var inboxContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            LoadingStateCard(title: AppStrings.Feedback.inboxTitle)
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.Feedback.inboxTitle,
                message: feedbackErrorMessage(error)
            ) {
                PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh() }
                }
            }
        } else if viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "bubble.left.and.bubble.right",
                title: AppStrings.Feedback.inboxTitle,
                message: AppStrings.Feedback.inboxEmpty
            )
        } else if filteredItems.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "line.3.horizontal.decrease.circle",
                title: selectedFilter.title,
                message: AppStrings.Feedback.inboxFilterEmpty
            )
        } else {
            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                if let error = viewModel.error {
                    InlineMessageCard(style: .error, message: feedbackErrorMessage(error))
                }

                ForEach(filteredItems) { item in
                    Button {
                        selectedFeedback = item
                    } label: {
                        FeedbackInboxRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func feedbackErrorMessage(_ error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return AppStrings.Moderation.loadPermissionError
        case .network:
            return AppStrings.Moderation.loadNetworkError
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

    private var inboxSearchField: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.textSecondary)
            TextField(AppStrings.Feedback.searchPlaceholder, text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
            if !searchText.isEmpty {
                AppSearchClearButton { searchText = "" }
            }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(minHeight: AppTheme.searchControlHeight)
        .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        }
    }

    private func currentFeedbackItem(for item: FeedbackItem) -> FeedbackItem {
        viewModel.items.first { $0.id == item.id } ?? item
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

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 2)
            }
        }
    }
}

private struct FeedbackDetailSheet: View {
    let item: FeedbackItem
    let messages: [FeedbackMessage]
    let isLoadingMessages: Bool
    let isUpdating: Bool
    let actionErrorMessage: String?
    let onLoad: () -> Void
    let onSendReply: (String) async -> Bool
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        FeedbackConversationSheet(
            item: item,
            messages: messages,
            isLoadingMessages: isLoadingMessages,
            isSending: isUpdating,
            actionErrorMessage: actionErrorMessage,
            allowsClose: true,
            onLoad: onLoad,
            onSend: onSendReply,
            onStop: onStop,
            onClose: onClose
        )
    }
}

private struct FeedbackConversationSheet: View {
    let item: FeedbackItem
    let messages: [FeedbackMessage]
    let isLoadingMessages: Bool
    let isSending: Bool
    let actionErrorMessage: String?
    let allowsClose: Bool
    let onLoad: () -> Void
    let onSend: (String) async -> Bool
    let onStop: () -> Void
    let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var replyText = ""
    @State private var validationMessage: String?
    @State private var isShowingCloseConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            AppEditorSectionCard {
                                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(item.type.title)
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        Spacer(minLength: 0)
                                        FeedbackStatusBadge(status: item.status, userFacing: true)
                                    }

                                    FeedbackMetadataRow(systemImage: "person", title: item.userDisplayName.isEmpty ? AppStrings.Profile.unknownUser : item.userDisplayName)
                                    FeedbackMetadataRow(systemImage: "calendar", title: LocalizationStore.dateString(from: item.createdAt, dateStyle: .medium, timeStyle: .short))
                                }
                            }

                            if let reportContext = item.reportContext {
                                ContentReportContextCard(
                                    context: reportContext,
                                    occurrenceCount: item.occurrenceCount
                                )
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

                VStack(alignment: .leading, spacing: 10) {
                    if let actionErrorMessage {
                        InlineMessageCard(style: .error, message: actionErrorMessage)
                    }
                    if item.status.isClosed {
                        Label(AppStrings.Feedback.closedMessage, systemImage: "lock")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 86, maxHeight: 120)
                                .padding(8)
                        }
                        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.borderSubtle)
                        )

                        HStack {
                            Text("\(replyText.count)/2000")
                                .foregroundStyle(AppTheme.textSecondary)
                            Spacer(minLength: 0)
                            if let validationMessage {
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
                .background(AppTheme.pageBackground)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle(AppStrings.Feedback.inboxTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppStrings.Common.done) {
                        dismiss()
                    }
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
            isEnabled: !isSending,
            isLoading: isSending,
            systemImage: "paperplane"
        ) {
            submitReply()
        }

        if allowsClose, onClose != nil {
            Button {
                isShowingCloseConfirmation = true
            } label: {
                Label(AppStrings.Feedback.closeFeedback, systemImage: "checkmark.seal")
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

private struct ContentReportContextCard: View {
    let context: ContentReportContext
    let occurrenceCount: Int

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

                FeedbackMetadataRow(
                    systemImage: context.targetType.systemImage,
                    title: "\(context.targetType.title): \(context.targetTitle)"
                )
                FeedbackMetadataRow(systemImage: "exclamationmark.bubble", title: context.reason.title)
                FeedbackMetadataRow(
                    systemImage: context.isUrgent ? "clock.badge.exclamationmark" : "clock",
                    title: slaText
                )

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
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
        case .answered, .reviewed:
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
            .background(tint.opacity(0.10), in: Capsule())
            .lineLimit(1)
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
            Text(AppStrings.Feedback.subtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

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
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 92)
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
    }
}
