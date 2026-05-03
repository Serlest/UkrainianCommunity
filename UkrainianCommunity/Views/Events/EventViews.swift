import SwiftUI

struct EventsListView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    let eventRepository: EventRepository
    let onEventPublished: @MainActor () async -> Void
    let onEventDeleted: @MainActor () -> Void
    @State private var pendingDeleteEventID: String?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false

    private var errorText: String {
        switch viewModel.error {
        case .network:
            AppStrings.Events.loadNetworkError
        case .permissionDenied:
            AppStrings.Events.loadPermissionError
        case .validationFailed:
            AppStrings.Events.loadValidationError
        case .notFound:
            AppStrings.Events.empty
        case .unknown:
            AppStrings.Events.loadUnknownError
        case nil:
            ""
        }
    }

    private var canCreateEvent: Bool {
        authState.user?.role.permissions.canCreateEvent == true
    }

    private var canDeleteEvent: Bool {
        authState.user?.role.permissions.canDeleteEvent == true
    }

    var body: some View {
        ScrollView {
            if viewModel.events.isEmpty && viewModel.isLoading {
                VStack {
                    Spacer(minLength: 0)
                    ProgressView()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if viewModel.events.isEmpty && viewModel.error != nil {
                EventsStateView(
                    systemImage: "calendar",
                    title: AppStrings.Events.title,
                    subtitle: errorText
                ) {
                    Button(AppStrings.Events.retry) {
                        viewModel.reload()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if viewModel.events.isEmpty {
                EventsStateView(
                    systemImage: "calendar",
                    title: AppStrings.Events.title,
                    subtitle: AppStrings.Events.empty
                ) {
                    Button(AppStrings.Events.retry) {
                        viewModel.reload()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 16) {
                    if viewModel.error != nil {
                        VStack(spacing: 8) {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button(AppStrings.Events.retry) {
                                viewModel.reload()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 16)
                    }

                    AdaptiveCardGrid(items: viewModel.events) { event in
                        ZStack(alignment: .bottomTrailing) {
                            NavigationLink {
                                EventDetailView(
                                    viewModel: viewModel,
                                    eventID: event.id,
                                    onEventDeleted: onEventDeleted
                                )
                            } label: {
                                EventCard(event: event)
                            }
                            .buttonStyle(.plain)

                            LikeButton(isLiked: event.likeState.isLiked, count: event.likeCount) {
                                viewModel.toggleLike(for: event.id)
                            }
                            .padding(.trailing, 18)
                            .padding(.bottom, 18)
                        }
                        .swipeActions(edge: .trailing) {
                            if canDeleteEvent {
                                Button(AppStrings.Events.delete, role: .destructive) {
                                    pendingDeleteEventID = event.id
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(AppStrings.Events.title)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .confirmationDialog(
            AppStrings.Events.deleteConfirmation,
            isPresented: Binding(
                get: { pendingDeleteEventID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteEventID = nil
                    }
                }
            )
        ) {
            Button(AppStrings.Events.delete, role: .destructive) {
                guard let eventID = pendingDeleteEventID else { return }
                Task {
                    do {
                        try await viewModel.deleteEvent(id: eventID)
                        viewModel.removeDeletedEvent(id: eventID)
                        onEventDeleted()
                    } catch let appError as AppError {
                        deleteErrorMessage = readableEventErrorText(appError)
                        isShowingDeleteError = true
                    } catch {
                        deleteErrorMessage = AppStrings.Events.actionUnknownError
                        isShowingDeleteError = true
                    }
                    pendingDeleteEventID = nil
                }
            }
            Button(AppStrings.Events.cancel, role: .cancel) {
                pendingDeleteEventID = nil
            }
        }
        .alert(AppStrings.Events.deleteFailed, isPresented: $isShowingDeleteError) {
            Button(AppStrings.Events.dismissError) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? AppStrings.Events.actionUnknownError)
        }
        .toolbar {
            if canCreateEvent {
                NavigationLink {
                    EventEditorView(repository: eventRepository, onPublished: onEventPublished)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

}

private func readableEventErrorText(_ error: AppError?) -> String {
    switch error {
    case .network:
        AppStrings.Events.loadNetworkError
    case .permissionDenied:
        AppStrings.Events.actionPermissionError
    case .validationFailed:
        AppStrings.Events.actionValidationError
    case .notFound:
        AppStrings.Events.actionNotFoundError
    case .unknown:
        AppStrings.Events.actionUnknownError
    case nil:
        AppStrings.Events.actionUnknownError
    }
}

private func sanitizedEventCommentAuthorName(_ rawValue: String) -> String {
    let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
        return AppStrings.NewsEditor.authorFallback
    }

    if looksLikeRawEventAuthorIdentifier(trimmedValue) {
        return AppStrings.NewsEditor.authorFallback
    }

    return trimmedValue
}

private func looksLikeRawEventAuthorIdentifier(_ value: String) -> Bool {
    guard value.count >= 20 else { return false }
    guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }

    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return value.rangeOfCharacter(from: allowedCharacters.inverted) == nil
}

private struct EventsStateView<ActionContent: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    @ViewBuilder let actionContent: ActionContent

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                actionContent
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

private struct EventCard: View {
    let event: Event

    var body: some View {
        CommunityCard {
            RemoteCardImage(imageURL: event.imageURL, height: 220, source: "EventCard")

            VStack(alignment: .leading, spacing: 10) {
                Text(event.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(event.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                VStack(alignment: .leading, spacing: 6) {
                    Label(eventDateTimeText, systemImage: "calendar")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(alignment: .center, spacing: 12) {
                        Label(event.city, systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                            Text(event.registrationState.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.primaryBlue)
                                .lineLimit(1)
                    }
                }
                .padding(.trailing, 88)
            }
        }
    }

    private var eventDateTimeText: String {
        let startDateText = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .short)

        guard event.endDate > event.startDate else {
            return startDateText
        }

        let isSameDay = Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate)
        if isSameDay {
            let endTimeText = LocalizationStore.dateString(from: event.endDate, dateStyle: .none, timeStyle: .short)
            return "\(startDateText) - \(endTimeText)"
        }

        let endDateText = LocalizationStore.dateString(from: event.endDate, dateStyle: .medium, timeStyle: .short)
        return "\(startDateText) - \(endDateText)"
    }
}

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    let eventID: String
    let onEventDeleted: () -> Void
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var isDeleting = false
    @State private var pendingRemovalEventID: String?
    private let detailImageHeight: CGFloat = 260

    private var canDeleteEvent: Bool {
        authState.user?.role.permissions.canDeleteEvent == true
    }

    private func eventDateTimeText(for event: Event) -> String {
        let startDateText = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .short)

        guard event.endDate > event.startDate else {
            return startDateText
        }

        let isSameDay = Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate)
        if isSameDay {
            let endTimeText = LocalizationStore.dateString(from: event.endDate, dateStyle: .none, timeStyle: .short)
            return "\(startDateText) - \(endTimeText)"
        }

        let endDateText = LocalizationStore.dateString(from: event.endDate, dateStyle: .medium, timeStyle: .short)
        return "\(startDateText) - \(endDateText)"
    }

    var body: some View {
        Group {
            if let event = viewModel.event(for: eventID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GradientHeroCard(title: event.title, subtitle: event.summary) {
                            Text(event.registrationState.title)
                                .font(.subheadline.weight(.semibold))
                        }

                        RemoteCardImage(imageURL: event.imageURL, height: detailImageHeight, cornerRadius: 22, source: "EventDetailView")

                        CommunityCard {
                            Text(event.details)
                            EventDetailMetadataBlock(
                                label: AppStrings.Events.fieldStartDate,
                                value: eventDateTimeText(for: event),
                                systemImage: "calendar"
                            )
                            EventDetailMetadataBlock(
                                label: AppStrings.Common.city,
                                value: event.city,
                                systemImage: "mappin"
                            )
                            EventDetailMetadataBlock(
                                label: AppStrings.Common.venue,
                                value: event.venue,
                                systemImage: "building"
                            )

                            HStack(alignment: .center, spacing: 12) {
                                Button(event.registrationState == .registered ? AppStrings.Events.registered : AppStrings.Events.register) {
                                    viewModel.toggleRegistration(for: event.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.primaryBlue)

                                Spacer(minLength: 0)

                                LikeButton(isLiked: event.likeState.isLiked, count: event.likeCount) {
                                    viewModel.toggleLike(for: event.id)
                                }
                            }
                        }

                        CommunityCard {
                            Text(AppStrings.Common.comments)
                                .font(.headline)
                            if event.comments.isEmpty {
                                Text(AppStrings.Common.commentsPlaceholder)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(event.comments) { comment in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(sanitizedEventCommentAuthorName(comment.authorName))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text(comment.body)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .navigationTitle(AppStrings.Events.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canDeleteEvent {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isDeleting)
            }
        }
        .confirmationDialog(AppStrings.Events.deleteConfirmation, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(AppStrings.Events.delete, role: .destructive) {
                Task {
                    await deleteCurrentEvent()
                }
            }
            Button(AppStrings.Events.cancel, role: .cancel) {}
        }
        .alert(AppStrings.Events.deleteFailed, isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button(AppStrings.Events.dismissError, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .onDisappear {
            guard let pendingRemovalEventID else { return }
            withTransaction(Transaction(animation: nil)) {
                viewModel.removeDeletedEvent(id: pendingRemovalEventID)
            }
            self.pendingRemovalEventID = nil
        }
    }

    @MainActor
    private func deleteCurrentEvent() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await viewModel.deleteEvent(id: eventID)
            pendingRemovalEventID = eventID
            dismiss()
            onEventDeleted()
        } catch let appError as AppError {
            deleteErrorMessage = readableEventErrorText(appError)
        } catch {
            deleteErrorMessage = readableEventErrorText(.unknown)
        }
    }
}

private struct EventDetailMetadataBlock: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.primaryBlue)
            }

            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

#Preview("Events List") {
    NavigationStack {
        EventsListView(
            viewModel: EventsViewModel(repository: MockEventRepository()),
            eventRepository: MockEventRepository(),
            onEventPublished: {},
            onEventDeleted: {}
        )
            .environmentObject(AuthState())
    }
}

#Preview("Event Detail") {
    NavigationStack {
        EventDetailView(
            viewModel: EventsViewModel(repository: MockEventRepository()),
            eventID: MockContentBuilder.events().first!.id,
            onEventDeleted: {}
        )
    }
    .environmentObject(AuthState())
}
