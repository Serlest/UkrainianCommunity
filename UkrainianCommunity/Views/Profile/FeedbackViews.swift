import SwiftUI

struct MyFeedbackView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: MyFeedbackViewModel
    let currentUserID: String
    @State private var selectedFeedback: FeedbackItem?

    var body: some View {
        PushedScreenShell(
            title: AppStrings.Feedback.myFeedbackTitle,
            subtitle: AppStrings.Feedback.myFeedbackSubtitle
        ) {
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
        .sheet(item: $selectedFeedback) { item in
            let currentItem = currentFeedbackItem(for: item)
            FeedbackConversationSheet(
                item: currentItem,
                messages: viewModel.messages(for: currentItem),
                isLoadingMessages: viewModel.loadingMessageFeedbackIDs.contains(currentItem.id),
                isSending: viewModel.sendingMessageFeedbackIDs.contains(currentItem.id),
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
                },
                onClose: nil
            )
            .presentationDetents([.medium, .large])
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
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(viewModel.items) { item in
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

    private var filteredItems: [FeedbackItem] {
        viewModel.items.filter { selectedFilter.includes($0) }
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
            Picker(AppStrings.Feedback.inboxFilter, selection: $selectedFilter) {
                ForEach(FeedbackInboxFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
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
                        await viewModel.close(currentFeedbackItem(for: currentItem))
                        selectedFeedback = nil
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
            VStack(spacing: AppTheme.feedRowSpacing) {
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
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
    let allowsClose: Bool
    let onLoad: () -> Void
    let onSend: (String) async -> Bool
    let onStop: () -> Void
    let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var replyText = ""
    @State private var validationMessage: String?

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
                                    .foregroundStyle(AppTheme.accentDestructive)
                            }
                        }
                        .font(.caption)

                        HStack(spacing: AppTheme.eventsMetadataSpacing) {
                            PrimaryActionButton(
                                title: isSending ? AppStrings.Feedback.sending : AppStrings.Feedback.send,
                                isEnabled: !isSending,
                                isLoading: isSending,
                                systemImage: "paperplane"
                            ) {
                                submitReply()
                            }

                            if allowsClose, let onClose {
                                Button(action: onClose) {
                                    Label(AppStrings.Feedback.closeFeedback, systemImage: "checkmark.seal")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.accentDestructive)
                                        .frame(height: AppTheme.iconButtonSize)
                                        .padding(.horizontal, 12)
                                        .background(AppTheme.accentDestructive.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(isSending)
                            }
                        }
                    }
                }
                .padding(AppTheme.pageHorizontal)
                .padding(.vertical, 12)
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

    private func scrollToLastMessage(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastMessageID = messages.last?.id else { return }
        let action = {
            proxy.scrollTo(lastMessageID, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.2), action)
        } else {
            action()
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
                        .foregroundStyle(isOwnerMessage ? AppTheme.accentPrimary : AppTheme.textSecondary)

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
            return AppTheme.accentPrimary
        case .answered, .reviewed:
            return AppTheme.textSecondary
        case .archived, .closed:
            return AppTheme.accentDestructive
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.Feedback.subtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent(AppStrings.Feedback.fieldType) {
                Picker(AppStrings.Feedback.fieldType, selection: $selectedFeedbackType) {
                    ForEach(FeedbackType.allCases) { feedbackType in
                        Text(feedbackType.title).tag(feedbackType)
                    }
                }
                .pickerStyle(.menu)
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
            }

            if let statusMessage {
                InlineMessageCard(
                    style: statusMessage == AppStrings.Feedback.submitted ? .success : .error,
                    message: statusMessage
                )
            }

            PrimaryActionButton(
                title: AppStrings.Feedback.submit,
                isEnabled: !isSubmitting,
                isLoading: isSubmitting,
                systemImage: "paperplane"
            ) {
                onSubmit()
            }
            .accessibilityLabel(AppStrings.Feedback.submit)
        }
        .padding(.vertical, 2)
    }
}
