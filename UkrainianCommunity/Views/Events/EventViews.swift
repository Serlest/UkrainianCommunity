import Combine
import SwiftUI

enum EventPresentationMode {
    case `public`
    case management

    var allowsManagementControls: Bool {
        self == .management
    }
}

private enum EventDiscoveryFilter: CaseIterable, Identifiable {
    case all
    case today
    case thisWeek

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            AppStrings.Events.filterAll
        case .today:
            AppStrings.Events.filterToday
        case .thisWeek:
            AppStrings.Events.filterThisWeek
        }
    }
}

private struct UpcomingEventDaySection: Identifiable {
    let date: Date
    let events: [Event]

    var id: Date { date }
}

private struct EventDiscoveryContent {
    let upcomingSections: [UpcomingEventDaySection]
    let pastEvents: [Event]
}

private func eventScheduleText(for event: Event) -> String {
    let startDateText = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .none)
    let timeRangeText = LocalizationStore.timeRangeString(startDate: event.startDate, endDate: event.endDate)

    guard event.endDate > event.startDate else {
        return "\(startDateText), \(timeRangeText)"
    }

    let isSameDay = Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate)
    if isSameDay {
        return "\(startDateText), \(timeRangeText)"
    }

    let endDateText = LocalizationStore.dateString(from: event.endDate, dateStyle: .medium, timeStyle: .short)
    return "\(startDateText)–\(endDateText)"
}

private func eventDayTitleText(for date: Date) -> String {
    LocalizationStore.dateString(from: date, dateStyle: .full, timeStyle: .none)
}

struct EventsListView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    let eventRepository: EventRepository
    let onEventPublished: @MainActor () async -> Void
    let onEventDeleted: @MainActor @Sendable () -> Void
    let presentationMode: EventPresentationMode
    @State private var pendingDeleteEventID: String?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false
    @State private var isShowingCreateSheet = false
    @State private var selectedFilter: EventDiscoveryFilter = .all
    @State private var guestAccessAction: GuestAccessAction?

    init(
        viewModel: EventsViewModel,
        eventRepository: EventRepository,
        onEventPublished: @escaping @MainActor () async -> Void,
        onEventDeleted: @escaping @MainActor @Sendable () -> Void,
        presentationMode: EventPresentationMode = .public
    ) {
        self.viewModel = viewModel
        self.eventRepository = eventRepository
        self.onEventPublished = onEventPublished
        self.onEventDeleted = onEventDeleted
        self.presentationMode = presentationMode
    }

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
        presentationMode.allowsManagementControls && PermissionService.canCreateEvent(user: authState.user)
    }

    private var canDeleteEvent: Bool {
        presentationMode.allowsManagementControls && PermissionService.canDeleteEvent(user: authState.user)
    }

    private var discoveryContent: EventDiscoveryContent {
        let calendar = Calendar.current
        let now = Date()
        let upcomingEvents = viewModel.events
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
        let filteredUpcomingEvents: [Event]

        switch selectedFilter {
        case .all:
            filteredUpcomingEvents = upcomingEvents
        case .today:
            filteredUpcomingEvents = upcomingEvents.filter { calendar.isDate($0.startDate, inSameDayAs: now) }
        case .thisWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
                filteredUpcomingEvents = upcomingEvents
                break
            }
            filteredUpcomingEvents = upcomingEvents.filter { interval.contains($0.startDate) }
        }

        let groupedEvents = Dictionary(grouping: filteredUpcomingEvents) {
            calendar.startOfDay(for: $0.startDate)
        }

        let upcomingSections = groupedEvents
            .map { UpcomingEventDaySection(date: $0.key, events: $0.value.sorted { $0.startDate < $1.startDate }) }
            .sorted { $0.date < $1.date }

        let pastEvents = viewModel.events
            .filter { $0.endDate < now }
            .sorted { $0.startDate > $1.startDate }

        return EventDiscoveryContent(upcomingSections: upcomingSections, pastEvents: pastEvents)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                BrandedScreenHeader(title: AppStrings.Events.title, subtitle: AppStrings.Home.brandSubtitle) {
                    AppInfoChip(
                        title: AppStrings.Home.regionAllAustria,
                        systemImage: "mappin.and.ellipse",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.surfaceElevated,
                        border: AppTheme.borderSubtle
                    )
                }
                .padding(.top, 10)

                EventFilterChips(selectedFilter: $selectedFilter)

                eventListContent
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.bottom, 112)
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.Events.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .guestAccessAlert($guestAccessAction)
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
                Button {
                    isShowingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(AppStrings.Action.create)
                .accessibilityHint(AppStrings.Events.title)
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            NavigationStack {
                EventEditorView(repository: eventRepository, onPublished: onEventPublished)
            }
        }
    }

    @ViewBuilder
    private var eventListContent: some View {
        if viewModel.events.isEmpty && viewModel.isLoading {
            LoadingStateCard(title: nil)
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if viewModel.events.isEmpty && viewModel.error != nil {
            ErrorStateCard(
                systemImage: "calendar",
                title: AppStrings.Events.title,
                message: errorText,
                retryTitle: AppStrings.Events.retry
            ) {
                viewModel.reload()
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else if viewModel.events.isEmpty {
            EmptyStateCard(
                systemImage: "calendar",
                title: AppStrings.Events.title,
                message: AppStrings.Events.empty
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            let content = discoveryContent

            VStack(alignment: .leading, spacing: AppTheme.feedSpacing) {
                upcomingContent(content)

                if !content.pastEvents.isEmpty {
                    pastContent(content)
                }
            }
        }
    }

    private func upcomingContent(_ content: EventDiscoveryContent) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            DashboardSectionHeader(title: AppStrings.Events.upcomingTitle) {
                AppInfoChip(
                    title: "\(content.upcomingSections.reduce(0) { $0 + $1.events.count })",
                    tint: AppTheme.accentPrimary,
                    fill: AppTheme.badgeBlueFill
                )
            }

            if content.upcomingSections.isEmpty {
                EmptyStateCard(
                    systemImage: "calendar.badge.exclamationmark",
                    title: AppStrings.Events.upcomingTitle,
                    message: AppStrings.Events.filteredUpcomingEmpty
                )
            } else {
                ForEach(content.upcomingSections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        EventDayHeader(dateText: eventDayTitleText(for: section.date))

                        DashboardFeedContainer(items: section.events) { event in
                            eventRow(for: event)
                        }
                    }
                }
            }
        }
    }

    private func pastContent(_ content: EventDiscoveryContent) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            DashboardSectionHeader(title: AppStrings.Events.pastTitle) {
                AppInfoChip(
                    title: "\(content.pastEvents.count)",
                    tint: AppTheme.textSecondary,
                    fill: AppTheme.surfaceElevated,
                    border: AppTheme.borderSubtle
                )
            }

            DashboardFeedContainer(items: content.pastEvents) { event in
                eventRow(for: event)
            }
        }
    }

    private func eventRow(for event: Event) -> some View {
        EventDiscoveryRow(
            event: event,
            viewModel: viewModel,
            onLikeTap: handleLike(for:),
            onEventDeleted: { @MainActor @Sendable in
                onEventDeleted()
            },
            presentationMode: presentationMode,
            canDeleteEvent: canDeleteEvent,
            pendingDeleteEventID: $pendingDeleteEventID
        )
    }

    private func handleLike(for eventID: String) {
        guard authState.isAuthenticated else {
            guestAccessAction = .likes
            return
        }

        viewModel.toggleLike(for: eventID)
    }

}

private struct EventFilterChips: View {
    @Binding var selectedFilter: EventDiscoveryFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(EventDiscoveryFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        AppInfoChip(
                            title: filter.title,
                            systemImage: filter.systemImage,
                            tint: selectedFilter == filter ? AppTheme.accentPrimary : AppTheme.textSecondary,
                            fill: selectedFilter == filter ? AppTheme.badgeBlueFill : AppTheme.surfaceElevated,
                            border: selectedFilter == filter ? nil : AppTheme.borderSubtle
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private extension EventDiscoveryFilter {
    var systemImage: String {
        switch self {
        case .all:
            "square.grid.2x2"
        case .today:
            "calendar"
        case .thisWeek:
            "calendar.badge.clock"
        }
    }
}

private struct EventDayHeader: View {
    let dateText: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)

            Text(dateText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 2)
    }
}

private struct EventDiscoveryRow: View {
    let event: Event
    @ObservedObject var viewModel: EventsViewModel
    let onLikeTap: (String) -> Void
    let onEventDeleted: @MainActor @Sendable () -> Void
    let presentationMode: EventPresentationMode
    let canDeleteEvent: Bool
    @Binding var pendingDeleteEventID: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationLink {
                EventDetailView(
                    viewModel: viewModel,
                    eventID: event.id,
                    onEventDeleted: { @MainActor @Sendable in
                        onEventDeleted()
                    }
                )
                .environment(\.eventPresentationMode, presentationMode)
            } label: {
                EventCard(event: event)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("event.card.\(event.id)")

            LikeButton(isLiked: event.likeState.isLiked, count: event.likeCount) {
                onLikeTap(event.id)
            }
            .disabled(viewModel.pendingEventLikeIDs.contains(event.id))
            .accessibilityIdentifier("event.like.\(event.id)")
            .accessibilityLabel(event.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like)
            .accessibilityHint(AppStrings.Common.likes)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
        .modifier(EventDeleteSwipeActions(isEnabled: canDeleteEvent) {
            pendingDeleteEventID = event.id
        })
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

private struct EventCard: View {
    let event: Event

    var body: some View {
        SoftContentCard {
            HStack(alignment: .center, spacing: 14) {
                AppFeedThumbnail(
                    imageURL: event.imageURL,
                    fallbackSystemImage: "calendar",
                    tint: AppTheme.accentPrimary,
                    fill: AppTheme.badgeBlueFill,
                    source: "EventCard"
                )

                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) {
                            typeChip

                            Spacer(minLength: 8)

                            AppDateBadge(date: event.startDate)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            typeChip
                            AppDateBadge(date: event.startDate)
                        }
                    }

                    Text(event.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if !event.summary.isEmpty {
                        Text(event.summary)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            AppMetadataLine(title: timeText, systemImage: "clock")
                            AppMetadataLine(title: event.city, systemImage: "mappin.and.ellipse")
                            AppMetadataLine(title: event.registrationState.title, systemImage: "checkmark.circle")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            AppMetadataLine(title: timeText, systemImage: "clock")
                            AppMetadataLine(title: event.city, systemImage: "mappin.and.ellipse")
                            AppMetadataLine(title: event.registrationState.title, systemImage: "checkmark.circle")
                        }
                    }
                    .padding(.trailing, 86)

                    if !event.venue.isEmpty {
                        AppMetadataLine(title: event.venue, systemImage: "building.2")
                            .padding(.trailing, 86)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var typeChip: some View {
        AppInfoChip(
            title: AppStrings.Events.title.uppercased(),
            systemImage: "calendar",
            tint: AppTheme.accentPrimary,
            fill: AppTheme.badgeBlueFill
        )
    }

    private var timeText: String {
        let startTime = LocalizationStore.dateString(from: event.startDate, dateStyle: .none, timeStyle: .short)
        guard event.endDate > event.startDate else {
            return startTime
        }

        let endTime = LocalizationStore.dateString(from: event.endDate, dateStyle: .none, timeStyle: .short)
        return "\(startTime) - \(endTime)"
    }

    private var accessibilitySummary: String {
        [
            event.title,
            event.summary,
            eventScheduleText(for: event),
            event.city,
            event.registrationState.title,
            "\(event.likeCount) \(AppStrings.Common.likes)"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.eventPresentationMode) private var presentationMode
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    let eventID: String
    let onEventDeleted: @MainActor @Sendable () -> Void
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var isDeleting = false
    @State private var isShowingEditSheet = false
    @State private var pendingRemovalEventID: String?
    @State private var guestAccessAction: GuestAccessAction?
    private let detailImageHeight: CGFloat = 260

    private var canEditEvent: Bool {
        presentationMode.allowsManagementControls && PermissionService.canEditEvent(user: authState.user)
    }

    private var canDeleteEvent: Bool {
        presentationMode.allowsManagementControls && PermissionService.canDeleteEvent(user: authState.user)
    }

    private var detailCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    @ViewBuilder
    private var editSheetContent: some View {
        if let event = viewModel.event(for: eventID) {
            NavigationStack {
                EventEditorView(repository: viewModel.editorRepository, event: event) {
                    await viewModel.refresh()
                }
            }
        }
    }

    var body: some View {
        Group {
            if let event = viewModel.event(for: eventID) {
                GeometryReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(event.title)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.primary)

                                Text(event.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                ViewThatFits(in: .horizontal) {
                                    HStack(alignment: .center, spacing: 12) {
                                        Label(eventScheduleText(for: event), systemImage: "calendar")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)

                                        Spacer(minLength: 12)

                                        Text(event.registrationState.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.primaryBlue)
                                    }

                                    VStack(alignment: .leading, spacing: 10) {
                                        Label(eventScheduleText(for: event), systemImage: "calendar")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)

                                        Text(event.registrationState.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.primaryBlue)
                                    }
                                }
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(detailCardShape)
                            .overlay(
                                detailCardShape
                                    .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
                            )

                            if let imageURL = event.imageURL {
                                VStack(alignment: .leading, spacing: 0) {
                                    RemoteImageView(
                                        imageURL: imageURL,
                                        height: detailImageHeight,
                                        cornerRadius: 18,
                                        source: "EventDetailView"
                                    )
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.cardBackground)
                                .clipShape(detailCardShape)
                                .overlay(
                                    detailCardShape
                                        .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
                                )
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text(event.details)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)

                                EventDetailMetadataBlock(
                                    label: AppStrings.Events.fieldStartDate,
                                    value: eventScheduleText(for: event),
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
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(detailCardShape)
                            .overlay(
                                detailCardShape
                                    .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
                            )

                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .center, spacing: 12) {
                                    registrationButton(for: event)

                                    Spacer(minLength: 0)

                                    likeButton(for: event)
                                }
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    registrationButton(for: event)
                                    likeButton(for: event)
                                }
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(detailCardShape)
                            .overlay(
                                detailCardShape
                                    .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
                            )

                            VStack(alignment: .leading, spacing: 12) {
                                Text(AppStrings.Common.comments)
                                    .font(.headline)
                                if event.comments.isEmpty {
                                    Text(AppStrings.Common.commentsPlaceholder)
                                        .font(.footnote)
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
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.cardBackground)
                            .clipShape(detailCardShape)
                            .overlay(
                                detailCardShape
                                    .strokeBorder(AppTheme.primaryBlue.opacity(0.08))
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                        .frame(width: proxy.size.width, alignment: .leading)
                    }
                    .frame(width: proxy.size.width)
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .navigationTitle(AppStrings.Events.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEditEvent, viewModel.event(for: eventID) != nil {
                Button {
                    isShowingEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(AppStrings.Action.edit)
                .accessibilityHint(AppStrings.Events.title)
            }

            if canDeleteEvent {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isDeleting)
                .accessibilityLabel(AppStrings.Action.delete)
                .accessibilityHint(AppStrings.Events.title)
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
        .sheet(isPresented: $isShowingEditSheet) {
            editSheetContent
        }
        .guestAccessAlert($guestAccessAction)
        .task {
            await viewModel.loadIfNeeded()
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

    private func registrationButton(for event: Event) -> some View {
        Button(event.registrationState == .registered ? AppStrings.Events.registered : AppStrings.Events.register) {
            guard authState.isAuthenticated else {
                guestAccessAction = .registration
                return
            }

            viewModel.toggleRegistration(for: event.id)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.primaryBlue)
        .disabled(viewModel.pendingEventRegistrationIDs.contains(event.id))
        .accessibilityIdentifier("event.register.\(event.id)")
        .accessibilityLabel(event.registrationState == .registered ? AppStrings.Action.cancelRegistration : AppStrings.Action.register)
        .accessibilityHint(AppStrings.Events.title)
    }

    private func likeButton(for event: Event) -> some View {
        LikeButton(isLiked: event.likeState.isLiked, count: event.likeCount) {
            guard authState.isAuthenticated else {
                guestAccessAction = .likes
                return
            }

            viewModel.toggleLike(for: event.id)
        }
        .disabled(viewModel.pendingEventLikeIDs.contains(event.id))
        .accessibilityIdentifier("event.like.\(event.id)")
        .accessibilityLabel(event.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like)
        .accessibilityHint(AppStrings.Common.likes)
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
            onEventDeleted: {},
            presentationMode: .management
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
        .environment(\.eventPresentationMode, .management)
    }
    .environmentObject(AuthState())
}

private struct EventDeleteSwipeActions: ViewModifier {
    let isEnabled: Bool
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.swipeActions(edge: .trailing) {
                Button(AppStrings.Events.delete, role: .destructive) {
                    onDelete()
                }
            }
        } else {
            content
        }
    }
}

private struct EventPresentationModeKey: EnvironmentKey {
    static let defaultValue: EventPresentationMode = .public
}

extension EnvironmentValues {
    var eventPresentationMode: EventPresentationMode {
        get { self[EventPresentationModeKey.self] }
        set { self[EventPresentationModeKey.self] = newValue }
    }
}
