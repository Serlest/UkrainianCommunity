import SwiftUI

private enum MyEventsSegment: String, CaseIterable, Identifiable {
    case upcoming, ongoing, past, cancelled, all
    var id: String { rawValue }
    var status: RegistrationEventStatus? { RegistrationEventStatus(rawValue: rawValue) }
    var title: String {
        switch self {
        case .all: AppStrings.Home.filterAll
        case .upcoming: AppStrings.Profile.myEventsUpcoming
        case .ongoing: RegistrationsText.ongoing
        case .past: AppStrings.Profile.myEventsPast
        case .cancelled: RegistrationsText.cancelled
        }
    }
    var systemImage: String {
        switch self {
        case .all: "calendar"
        case .upcoming: "calendar.badge.clock"
        case .ongoing: "clock"
        case .past: "clock.arrow.circlepath"
        case .cancelled: "calendar.badge.exclamationmark"
        }
    }
    var emptyTitle: String {
        switch self {
        case .all: AppStrings.Profile.myEventsEmptyAllTitle
        case .upcoming: AppStrings.Profile.myEventsEmptyUpcomingTitle
        case .ongoing: RegistrationsText.ongoingEmpty
        case .past: AppStrings.Profile.myEventsEmptyPastTitle
        case .cancelled: RegistrationsText.cancelledEmpty
        }
    }
}

struct MyRegistrationsView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: MyRegistrationsViewModel
    let eventRepository: EventRepository
    @ObservedObject private var eventsViewModel: EventsViewModel
    @State private var selectedSegment: MyEventsSegment = .upcoming

    init(viewModel: MyRegistrationsViewModel, eventRepository: EventRepository, eventsViewModel: EventsViewModel) {
        self.viewModel = viewModel; self.eventRepository = eventRepository; self.eventsViewModel = eventsViewModel
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let groups = Dictionary(grouping: viewModel.events) { RegistrationEventStatus.resolve($0, now: now) }
            let visible = (selectedSegment.status.map { groups[$0] ?? [] } ?? viewModel.events).sorted { left, right in
                let lhs = RegistrationEventStatus.occurrence(for: left, now: now)
                let rhs = RegistrationEventStatus.occurrence(for: right, now: now)
                if selectedSegment == .all {
                    let order: [RegistrationEventStatus: Int] = [.ongoing: 0, .upcoming: 1, .past: 2, .cancelled: 3]
                    let a = order[RegistrationEventStatus.resolve(left, now: now)] ?? 0
                    let b = order[RegistrationEventStatus.resolve(right, now: now)] ?? 0
                    if a != b { return a < b }
                }
                if lhs.startDate == rhs.startDate { return left.id < right.id }
                let descending = selectedSegment == .past || (selectedSegment == .all && RegistrationEventStatus.resolve(left, now: now) == .past)
                return descending ? lhs.startDate > rhs.startDate : lhs.startDate < rhs.startDate
            }
            ProfileDestinationLayout(title: PermissionService.isAppOwner(user: authState.user) ? OwnerProfileText.registrations : AppStrings.Profile.myRegistrations,
                                     introSubtitle: AppStrings.Profile.myEventsIntro) {
                Text(RegistrationsText.scope).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                AppHorizontalFilterRow {
                    ForEach(MyEventsSegment.allCases) { segment in
                        Button { selectedSegment = segment } label: {
                            AppFilterChip(title: "\(segment.title): \(segment.status.map { groups[$0]?.count ?? 0 } ?? viewModel.events.count)",
                                          systemImage: segment.systemImage, isSelected: selectedSegment == segment)
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("registrations.filter.\(segment.rawValue)")
                    }
                }
                .accessibilityIdentifier("registrations.filters")
                if let error = viewModel.error {
                    InlineMessageCard(style: .error, message: readableRegistrationsErrorText(error))
                        .accessibilityIdentifier("registrations.error")
                    Button(RegistrationsText.retry) { Task { await viewModel.refresh() } }
                        .disabled(viewModel.isLoading || viewModel.isLoadingMore)
                        .accessibilityIdentifier("registrations.retry")
                }
                if viewModel.hasMore {
                    Text(RegistrationsText.partial).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("registrations.partial")
                }
                if (viewModel.isLoading || !viewModel.hasLoaded && viewModel.error == nil) && viewModel.events.isEmpty {
                    LoadingStateCard(title: AppStrings.Profile.registrationsLoading).accessibilityIdentifier("registrations.loading")
                } else if visible.isEmpty && viewModel.error == nil {
                    ProfileDestinationEmptyStateCard(systemImage: selectedSegment.systemImage,
                        title: selectedSegment.emptyTitle,
                        message: viewModel.hasMore ? RegistrationsText.partial : RegistrationsText.emptyFilter)
                        .accessibilityIdentifier("registrations.empty")
                } else {
                    LazyVStack(spacing: AppTheme.feedRowSpacing) {
                        ForEach(visible) { event in
                            NavigationLink {
                                RegisteredEventDetailContainer(event: event, eventsViewModel: eventsViewModel) { @MainActor @Sendable in
                                    viewModel.removeRegistrationEvent(id: event.id)
                                }
                            } label: {
                                RegistrationEventRow(event: event, isUpdating: viewModel.pendingCancellationIDs.contains(event.id), now: now)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("registrations.open.\(event.id)")
                                .accessibilityLabel("\(event.localizedTitle), \(registrationEventScheduleText(for: event, now: now))")
                        }
                    }
                }
                if viewModel.hasMore {
                    Button { Task { await viewModel.loadMore() } } label: {
                        HStack {
                            if viewModel.isLoadingMore { ProgressView() }
                            Text(RegistrationsText.loadMore)
                        }.frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget)
                    }.disabled(viewModel.isLoading || viewModel.isLoadingMore)
                        .accessibilityIdentifier("registrations.loadMore")
                }
            }
        }
        .task { await viewModel.refreshIfStale() }
        .appRefreshable { await viewModel.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.refreshIfStale() } }
        }
        .onChange(of: eventsViewModel.contentVersion) { _, _ in viewModel.synchronize(with: eventsViewModel.events) }
        .onChange(of: authState.user?.id) { _, _ in selectedSegment = .upcoming }
    }

    private func readableRegistrationsErrorText(_ error: AppError) -> String {
        switch error {
        case .network: AppStrings.Events.loadNetworkError
        case .permissionDenied: AppStrings.Events.loadPermissionError
        case .validationFailed: AppStrings.Events.loadValidationError
        case .notFound: AppStrings.Profile.registrationsEmptyMessage
        case .unknown: AppStrings.Events.loadUnknownError
        }
    }
}

private struct RegisteredEventDetailContainer: View {
    let event: Event
    @ObservedObject private var eventsViewModel: EventsViewModel
    let onEventDeleted: @MainActor @Sendable () -> Void

    init(
        event: Event,
        eventsViewModel: EventsViewModel,
        onEventDeleted: @escaping @MainActor @Sendable () -> Void
    ) {
        self.event = event
        self.eventsViewModel = eventsViewModel
        self.onEventDeleted = onEventDeleted
    }

    var body: some View {
        EventDetailView(
            viewModel: eventsViewModel,
            eventID: event.id,
            onEventDeleted: onEventDeleted
        )
        .environment(\.eventPresentationMode, .public)
        .task(id: event.id) { @MainActor in
            guard eventsViewModel.event(for: event.id) == nil else { return }
            eventsViewModel.cacheEvent(event)
        }
    }
}

private struct RegistrationEventRow: View {
    let event: Event
    let isUpdating: Bool
    let now: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let occurrence = RegistrationEventStatus.occurrence(for: event, now: now)
        let status = RegistrationEventStatus.resolve(event, now: now)
        SoftContentCard(padding: AppTheme.eventsCardPadding) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    Label(status.title, systemImage: status == .cancelled ? "calendar.badge.exclamationmark" : "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status == .cancelled ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground)
                    Text(event.localizedTitle).font(.headline).foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(registrationEventScheduleText(for: event, now: now))
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(event.city.isEmpty ? event.venue : event.city, systemImage: "mappin.and.ellipse")
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                    if isUpdating { ProgressView() }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                    AppEventDateBlock(date: occurrence.startDate)
                    VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
                        AppInfoChip(title: status.title, systemImage: "calendar",
                                    tint: status == .cancelled ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground,
                                    fill: status == .cancelled ? AppTheme.accentDestructive.opacity(0.10) : AppTheme.badgeBlueFill, size: .small)
                        Text(event.localizedTitle).font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary).lineLimit(2)
                        if !event.localizedSummary.isEmpty {
                            Text(event.localizedSummary).font(.caption2.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary).lineLimit(1)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            AppMetadataLine(title: LocalizationStore.timeRangeString(startDate: occurrence.startDate, endDate: occurrence.endDate, isAllDay: occurrence.isAllDay), systemImage: "clock")
                            AppMetadataLine(title: event.city.isEmpty ? event.venue : event.city, systemImage: "mappin.and.ellipse")
                        }.lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if event.imageURL != nil {
                        AppFeedThumbnail(imageURL: event.imageURL, fallbackSystemImage: "calendar",
                            tint: AppTheme.accentPrimaryForeground, fill: AppTheme.badgeBlueFill,
                            size: AppTheme.eventsThumbnailSize, cornerRadius: 14, source: "RegistrationEventRow")
                            .layoutPriority(-1)
                    }
                    if isUpdating { ProgressView().controlSize(.small) }
                }
            }
        }.opacity(isUpdating ? 0.7 : 1)
    }

}
func registrationEventScheduleText(for event: Event, now: Date = Date()) -> String {
    let occurrence = RegistrationEventStatus.occurrence(for: event, now: now)
    if occurrence.isAllDay {
        let start = LocalizationStore.dateString(from: occurrence.startDate, dateStyle: .medium, timeStyle: .none)
        let displayEnd = RegistrationEventStatus.displayEndDate(for: occurrence)
        if Calendar.current.isDate(occurrence.startDate, inSameDayAs: displayEnd) { return start }
        return start + " – " + LocalizationStore.dateString(from: displayEnd, dateStyle: .medium, timeStyle: .none)
    }
    let startDateText = LocalizationStore.dateString(from: occurrence.startDate, dateStyle: .medium, timeStyle: .short)

    guard occurrence.endDate > occurrence.startDate else {
        return startDateText
    }

    let isSameDay = Calendar.current.isDate(occurrence.startDate, inSameDayAs: occurrence.endDate)
    if isSameDay {
        let endTimeText = LocalizationStore.dateString(from: occurrence.endDate, dateStyle: .none, timeStyle: .short)
        return "\(startDateText) - \(endTimeText)"
    }

    let endDateText = LocalizationStore.dateString(from: occurrence.endDate, dateStyle: .medium, timeStyle: .short)
    return "\(startDateText) - \(endDateText)"
}
extension MyRegistrationsViewModel {
    var registrationsCountText: String {
        if isLoading && events.isEmpty {
            return AppStrings.Profile.loadingStatValue
        }

        return "\(registrationsCount)"
    }
}

private extension RegistrationEventStatus {
    var title: String {
        switch self {
        case .upcoming: RegistrationsText.upcomingBadge
        case .ongoing: RegistrationsText.ongoingBadge
        case .past: RegistrationsText.pastBadge
        case .cancelled: RegistrationsText.cancelledBadge
        }
    }
}
