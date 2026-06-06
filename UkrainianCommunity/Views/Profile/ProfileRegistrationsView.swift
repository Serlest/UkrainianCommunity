import SwiftUI

private enum MyEventsSegment: String, CaseIterable, Identifiable {
    case all
    case upcoming
    case past

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppStrings.Home.filterAll
        case .upcoming:
            return AppStrings.Profile.myEventsUpcoming
        case .past:
            return AppStrings.Profile.myEventsPast
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "calendar"
        case .upcoming:
            return "calendar.badge.clock"
        case .past:
            return "clock.arrow.circlepath"
        }
    }
}

struct MyRegistrationsView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: MyRegistrationsViewModel
    let eventRepository: EventRepository
    @ObservedObject private var eventsViewModel: EventsViewModel
    @State private var selectedSegment: MyEventsSegment = .upcoming

    init(
        viewModel: MyRegistrationsViewModel,
        eventRepository: EventRepository,
        eventsViewModel: EventsViewModel? = nil
    ) {
        self.viewModel = viewModel
        self.eventRepository = eventRepository
        self.eventsViewModel = eventsViewModel ?? EventsViewModel(repository: eventRepository)
    }

    private var calendar: Calendar { .current }

    private var upcomingEvents: [Event] {
        let startOfToday = calendar.startOfDay(for: Date())
        return viewModel.events
            .filter { $0.endDate >= startOfToday }
            .sorted { $0.startDate < $1.startDate }
    }

    private var pastEvents: [Event] {
        let startOfToday = calendar.startOfDay(for: Date())
        return viewModel.events
            .filter { $0.endDate < startOfToday }
            .sorted { $0.endDate > $1.endDate }
    }

    private var filteredEvents: [Event] {
        switch selectedSegment {
        case .all:
            return upcomingEvents + pastEvents
        case .upcoming:
            return upcomingEvents
        case .past:
            return pastEvents
        }
    }

    private var emptyStateTitle: String {
        switch selectedSegment {
        case .all:
            return AppStrings.Profile.myEventsEmptyAllTitle
        case .upcoming:
            return AppStrings.Profile.myEventsEmptyUpcomingTitle
        case .past:
            return AppStrings.Profile.myEventsEmptyPastTitle
        }
    }

    private var emptyStateMessage: String {
        switch selectedSegment {
        case .all:
            return AppStrings.Profile.myEventsEmptyRegisterMessage
        case .upcoming:
            return viewModel.events.isEmpty
                ? AppStrings.Profile.myEventsEmptyRegisterMessage
                : AppStrings.Profile.myEventsEmptyUpcomingMessage
        case .past:
            return viewModel.events.isEmpty
                ? AppStrings.Profile.myEventsEmptyRegisterMessage
                : AppStrings.Profile.myEventsEmptyPastMessage
        }
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.myRegistrations,
            introSubtitle: AppStrings.Profile.myEventsIntro
        ) {
            filtersRow
            registrationsContent
        }
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onChange(of: eventsViewModel.contentVersion) { _, _ in
            viewModel.synchronize(with: eventsViewModel.events)
        }
    }

    @ViewBuilder
    private var filtersRow: some View {
        AppHorizontalFilterRow {
            ForEach(MyEventsSegment.allCases) { segment in
                Button {
                    selectedSegment = segment
                } label: {
                    AppFilterChip(
                        title: segment.title,
                        systemImage: segment.systemImage,
                        isSelected: selectedSegment == segment
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var registrationsContent: some View {
        if viewModel.isLoading && viewModel.events.isEmpty {
            LoadingStateCard(title: AppStrings.Profile.registrationsLoading)
        } else if let error = viewModel.error, viewModel.events.isEmpty {
            ErrorStateCard(
                title: AppStrings.Profile.myRegistrations,
                message: readableRegistrationsErrorText(error)
            )
        } else if viewModel.events.isEmpty || filteredEvents.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: viewModel.events.isEmpty ? "calendar.badge.clock" : selectedSegment.systemImage,
                title: emptyStateTitle,
                message: emptyStateMessage
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(filteredEvents) { event in
                    registrationRow(for: event)
                }
            }
        }
    }

    @ViewBuilder
    private func registrationRow(for event: Event) -> some View {
        NavigationLink {
            RegisteredEventDetailContainer(
                event: event,
                repository: eventRepository,
                eventsViewModel: eventsViewModel
            )
        } label: {
            RegistrationEventRow(
                event: event,
                isUpdating: viewModel.pendingCancellationIDs.contains(event.id)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(registrationEventScheduleText(for: event))")
    }

    private func readableRegistrationsErrorText(_ error: AppError) -> String {
        switch error {
        case .network:
            AppStrings.Events.loadNetworkError
        case .permissionDenied:
            AppStrings.Events.loadPermissionError
        case .validationFailed:
            AppStrings.Events.loadValidationError
        case .notFound:
            AppStrings.Profile.registrationsEmptyMessage
        case .unknown:
            AppStrings.Events.loadUnknownError
        }
    }
}

private struct RegisteredEventDetailContainer: View {
    let event: Event
    @StateObject private var detailViewModel: EventsViewModel

    init(
        event: Event,
        repository: EventRepository,
        eventsViewModel: EventsViewModel? = nil
    ) {
        self.event = event
        let resolvedViewModel = eventsViewModel ?? EventsViewModel(repository: repository)
        resolvedViewModel.cacheEvent(event)
        _detailViewModel = StateObject(wrappedValue: resolvedViewModel)
    }

    var body: some View {
        EventDetailView(
            viewModel: detailViewModel,
            eventID: event.id,
            onEventDeleted: {}
        )
        .environment(\.eventPresentationMode, .public)
    }
}

private struct RegistrationEventRow: View {
    let event: Event
    let isUpdating: Bool

    var body: some View {
        SoftContentCard(padding: AppTheme.eventsCardPadding) {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                AppEventDateBlock(date: event.startDate)

                VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
                    AppInfoChip(
                        title: AppStrings.Events.title.uppercased(),
                        systemImage: "calendar",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.badgeBlueFill,
                        size: .small
                    )

                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if !event.summary.isEmpty {
                        Text(event.summary)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.88))
                            .lineLimit(1)
                    }

                    HStack(spacing: AppTheme.eventsMetadataSpacing) {
                        AppMetadataLine(title: LocalizationStore.timeRangeString(startDate: event.startDate, endDate: event.endDate), systemImage: "clock")
                        AppMetadataLine(title: event.city.isEmpty ? event.venue : event.city, systemImage: event.city.isEmpty ? "building.2" : "mappin.and.ellipse")
                    }
                }
                .padding(.trailing, 6)

                Spacer(minLength: 0)

                ZStack(alignment: .topTrailing) {
                    AppFeedThumbnail(
                        imageURL: event.imageURL,
                        fallbackSystemImage: "calendar",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.badgeBlueFill,
                        size: AppTheme.eventsThumbnailSize,
                        cornerRadius: 14,
                        source: "RegistrationEventRow"
                    )

                    if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppTheme.accentPrimary)
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                    }
                }
                .padding(.trailing, 26)
                .frame(maxHeight: AppTheme.eventsThumbnailSize)
                .layoutPriority(-1)
            }
        }
        .opacity(isUpdating ? 0.7 : 1)
    }
}
func registrationEventScheduleText(for event: Event) -> String {
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
extension MyRegistrationsViewModel {
    var registrationsCountText: String {
        if isLoading && events.isEmpty {
            return AppStrings.Profile.loadingStatValue
        }

        return "\(registrationsCount)"
    }
}
