import Combine
import SwiftUI
import UIKit

struct EventNavigationRoute: Hashable {
    let eventID: String
}

private let eventsRootScrollTopID = "eventsRootScrollTop"

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

private struct EventCategoryFilter: Identifiable, Hashable {
    let category: EventCategory?
    var id: String { category?.rawValue ?? "all" }
    var title: String { category?.title ?? AppStrings.Events.allCategories }
    var systemImage: String { category?.systemImage ?? "tag" }
    static let all = EventCategoryFilter(category: nil)
    static var allCases: [EventCategoryFilter] {
        [.all] + EventCategory.allCases.map { EventCategoryFilter(category: $0) }
    }
}

private struct EventAudienceFilter: Identifiable, Hashable {
    let audience: EventAudience?
    var id: String { audience?.rawValue ?? "all" }
    var title: String { audience?.title ?? AppStrings.Events.audienceAll }
    var systemImage: String { audience?.systemImage ?? "person.3" }
    static let all = EventAudienceFilter(audience: nil)
    static var allCases: [EventAudienceFilter] {
        [.all] + EventAudience.allCases.filter { $0 != .everyone }.map { EventAudienceFilter(audience: $0) }
    }
}

private enum EventAgeFilter: CaseIterable, Identifiable {
    case any, child, teen, adult
    var id: Self { self }
    var title: String {
        switch self {
        case .any: AppStrings.Events.ageFilterAny
        case .child: AppStrings.Events.ageFilterChildren
        case .teen: AppStrings.Events.ageFilterTeens
        case .adult: AppStrings.Events.ageFilterAdults
        }
    }
    var ageRange: ClosedRange<Int>? {
        switch self {
        case .any: nil
        case .child: 0...12
        case .teen: 13...17
        case .adult: 18...120
        }
    }
}

private enum EventFeedScope {
    case all
    case saved
    case registered
}

private struct UpcomingEventDaySection: Identifiable {
    let date: Date
    let events: [Event]

    var id: Date { date }
}

private struct UpcomingEventMonthSection: Identifiable {
    let monthStart: Date
    let events: [Event]

    var id: Date { monthStart }
}

private struct EventDiscoveryContent {
    let upcomingSections: [UpcomingEventDaySection]
    let pastEvents: [Event]
}

func eventScheduleText(for event: Event) -> String {
    let occurrence = event.nextOccurrence() ?? event.occurrences.first
    let startDate = occurrence?.startDate ?? event.startDate
    let endDate = occurrence?.endDate ?? event.endDate
    let isAllDay = occurrence?.isAllDay ?? event.isAllDay
    let startDateText = LocalizationStore.dateString(from: startDate, dateStyle: .medium, timeStyle: .none)
    let timeRangeText = LocalizationStore.timeRangeString(startDate: startDate, endDate: endDate, isAllDay: isAllDay)

    guard endDate > startDate else {
        return "\(startDateText), \(timeRangeText)"
    }

    let isSameDay = Calendar.current.isDate(startDate, inSameDayAs: endDate)
    if isSameDay {
        return "\(startDateText), \(timeRangeText)"
    }

    let endDateText = LocalizationStore.dateString(from: endDate, dateStyle: .medium, timeStyle: .short)
    return "\(startDateText)–\(endDateText)"
}

private func eventMonthTitleText(for date: Date) -> String {
    LocalizationStore.dateString(from: date, localizedTemplate: "MMMM yyyy")
}

func eventMonthBucketStart(for date: Date, calendar: Calendar = .current) -> Date {
    calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
}

struct CalendarMonthGroup<Element> {
    let monthStart: Date
    let elements: [Element]
}

func calendarMonthGroups<Element>(
    _ elements: [Element],
    calendar: Calendar = .current,
    date: (Element) -> Date
) -> [CalendarMonthGroup<Element>] {
    Dictionary(grouping: elements) {
        eventMonthBucketStart(for: date($0), calendar: calendar)
    }
    .map { CalendarMonthGroup(monthStart: $0.key, elements: $0.value) }
    .sorted { $0.monthStart < $1.monthStart }
}

struct EventsListView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    let eventRepository: EventRepository
    @Binding var navigationPath: [EventNavigationRoute]
    let onEventPublished: @MainActor () async -> Void
    let onEventDeleted: @MainActor @Sendable () -> Void
    let presentationMode: EventPresentationMode
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    let scrollResetToken: Int
    let searchResetToken: Int
    @State private var pendingDeleteEventID: String?
    @State private var deleteErrorEvent: Event?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false
    @State private var selectedFilter: EventDiscoveryFilter = .all
    @State private var selectedCategory: EventCategoryFilter = .all
    @State private var selectedAudience: EventAudienceFilter = .all
    @State private var selectedAge: EventAgeFilter = .any
    @State private var selectedFederalState: AustrianFederalState?
    @State private var selectedFeedScope: EventFeedScope = .all
    @State private var didManuallyChangeRegion = false
    @State private var isRegionPickerPresented = false
    @State private var guestAccessAction: GuestAccessAction?
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var isLoadingSearchPages = false

    init(
        viewModel: EventsViewModel,
        eventRepository: EventRepository,
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        featuredBannerCache: FeaturedBannerCache = FeaturedBannerCache(),
        navigationPath: Binding<[EventNavigationRoute]> = .constant([]),
        onEventPublished: @escaping @MainActor () async -> Void,
        onEventDeleted: @escaping @MainActor @Sendable () -> Void,
        presentationMode: EventPresentationMode = .public,
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        scrollResetToken: Int = 0,
        searchResetToken: Int = 0
    ) {
        self.viewModel = viewModel
        self.eventRepository = eventRepository
        self.onEventPublished = onEventPublished
        self.onEventDeleted = onEventDeleted
        self.presentationMode = presentationMode
        self.onFeaturedBannerTap = onFeaturedBannerTap
        self.scrollResetToken = scrollResetToken
        self.searchResetToken = searchResetToken
        _featuredBannerViewModel = StateObject(wrappedValue: FeaturedBannerListViewModel(
            repository: featuredBannerRepository,
            cache: featuredBannerCache
        ))
        _navigationPath = navigationPath
    }

    private var featuredBannerLoadKey: String {
        selectedFederalState?.rawValue ?? "allAustria"
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

    private func canDeleteEvent(_ event: Event) -> Bool {
        canManageEvent(event)
    }

    private var discoveryContent: EventDiscoveryContent {
        let calendar = Calendar.current
        let now = Date()
        let events = filteredEvents
        let upcomingEvents = events
            .filter { $0.nextOccurrence(relativeTo: now) != nil }
            .sorted {
                let left = $0.nextOccurrence(relativeTo: now)?.startDate ?? $0.startDate
                let right = $1.nextOccurrence(relativeTo: now)?.startDate ?? $1.startDate
                return left == right ? $0.id < $1.id : left < right
            }
        let filteredUpcomingEvents: [Event]

        switch selectedFilter {
        case .all:
            filteredUpcomingEvents = upcomingEvents
        case .today:
            filteredUpcomingEvents = upcomingEvents.filter { calendar.isDate($0.nextOccurrence(relativeTo: now)?.startDate ?? $0.startDate, inSameDayAs: now) }
        case .thisWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
                filteredUpcomingEvents = upcomingEvents
                break
            }
            filteredUpcomingEvents = upcomingEvents.filter { interval.contains($0.nextOccurrence(relativeTo: now)?.startDate ?? $0.startDate) }
        }

        let groupedEvents = Dictionary(grouping: filteredUpcomingEvents) {
            calendar.startOfDay(for: $0.nextOccurrence(relativeTo: now)?.startDate ?? $0.startDate)
        }

        let upcomingSections = groupedEvents
            .map { day, events in
                UpcomingEventDaySection(
                    date: day,
                    events: events.sorted {
                        let left = $0.nextOccurrence(relativeTo: now)?.startDate ?? $0.startDate
                        let right = $1.nextOccurrence(relativeTo: now)?.startDate ?? $1.startDate
                        return left == right ? $0.id < $1.id : left < right
                    }
                )
            }
            .sorted { $0.date < $1.date }

        let pastEvents = events
            .filter { $0.nextOccurrence(relativeTo: now) == nil }
            .sorted {
                $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate > $1.startDate
            }

        return EventDiscoveryContent(upcomingSections: upcomingSections, pastEvents: pastEvents)
    }

    private var filteredEvents: [Event] {
        viewModel.events.filter { event in
            matchesSelectedCategory(event)
                && matchesSelectedAudience(event)
                && matchesSelectedAge(event)
                && matchesSelectedRegion(event)
                && matchesSelectedFeedScope(event)
                && matchesSearch(event)
        }
    }

    private var hasActiveSearch: Bool {
        LocalSearchMatcher.hasQuery(searchText)
    }

    private func matchesSelectedRegion(_ event: Event) -> Bool {
        RegionVisibilityMatcher.isVisible(
            regionScope: event.regionScope,
            federalState: event.federalState,
            selectedFederalState: selectedFederalState
        )
    }

    private func matchesSelectedCategory(_ event: Event) -> Bool {
        guard let category = selectedCategory.category else { return true }
        return event.category == category || event.additionalCategories.contains(category)
    }

    private func matchesSelectedAudience(_ event: Event) -> Bool {
        guard let audience = selectedAudience.audience else { return true }
        return event.audience == .everyone || event.audience == audience
    }

    private func matchesSelectedAge(_ event: Event) -> Bool {
        guard let range = selectedAge.ageRange else { return true }
        let eventRange = (event.minimumAge ?? 0)...(event.maximumAge ?? 120)
        return eventRange.overlaps(range)
    }

    private func matchesSelectedFeedScope(_ event: Event) -> Bool {
        switch selectedFeedScope {
        case .all:
            return true
        case .saved:
            return authState.user != nil && event.isBookmarked
        case .registered:
            return authState.user != nil && event.registrationState == .registered
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                Color.clear
                    .frame(height: 0)
                    .id(eventsRootScrollTopID)

                VStack(alignment: .leading, spacing: 0) {
                    eventsHeader
                        .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

                    eventsHero
                        .padding(
                            .bottom,
                            featuredBannerViewModel.banners.isEmpty && featuredBannerViewModel.error == nil
                                ? 0
                                : AppTheme.homeSectionSpacing
                        )

                    EventFilterRow(
                        selectedPeriod: selectedFilter,
                        selectedFederalState: selectedFederalState,
                        selectedCategory: selectedCategory,
                        selectedAudience: selectedAudience,
                        selectedAge: selectedAge,
                        selectedFeedScope: selectedFeedScope,
                        onSelectPeriod: { selectedFilter = $0 },
                        onSelectCategory: { selectedCategory = $0 },
                        onSelectAudience: { selectedAudience = $0 },
                        onSelectAge: { selectedAge = $0 },
                        onSelectRegion: { isRegionPickerPresented = true },
                        onSelectSaved: { selectedFeedScope = selectedFeedScope == .saved ? .all : .saved },
                        onSelectRegistered: { selectedFeedScope = selectedFeedScope == .registered ? .all : .registered }
                    )
                    .padding(.bottom, AppTheme.homeSectionSpacing)

                    AppGroupedContentPlane(padding: AppTheme.homeFeedPlanePadding) {
                        eventListContent
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
                .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollResetToken) {
                scrollToTop(with: scrollProxy)
            }
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: EventNavigationRoute.self) { route in
            EventDetailView(
                viewModel: viewModel,
                eventID: route.eventID,
                onEventDeleted: { @MainActor @Sendable in
                    onEventDeleted()
                }
            )
            .environment(\.eventPresentationMode, presentationMode)
        }
        .task(id: featuredBannerLoadKey) {
            applyDefaultRegion()
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
            await refreshFeaturedBannersIfStale()
        }
        .task(id: searchText) {
            let queryKey = LocalSearchMatcher.normalized(searchText)
            isLoadingSearchPages = false
            guard !queryKey.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isLoadingSearchPages = true
            defer {
                if LocalSearchMatcher.normalized(searchText) == queryKey {
                    isLoadingSearchPages = false
                }
            }
            await viewModel.loadRemainingPagesForSearch()
        }
        .appRefreshable {
            async let content: Void = viewModel.refresh()
            async let banners: Void = refreshFeaturedBanners()
            _ = await (content, banners)
        }
        .onChange(of: authState.user?.selectedFederalState) { _, newRegion in
            guard !didManuallyChangeRegion else { return }
            selectedFederalState = newRegion
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .guestAccessAlert($guestAccessAction)
        .appErrorDialog(Binding(
            get: {
                viewModel.interactionError.map {
                    AppErrorDialog(message: readableEventErrorText($0))
                }
            },
            set: { if $0 == nil { viewModel.dismissInteractionError() } }
        ))
        .observesKeyboardDismissTaps()
        .confirmationDialog(AppStrings.Home.regionAllAustria, isPresented: $isRegionPickerPresented, titleVisibility: .visible) {
            Button(AppStrings.Home.regionAllAustria) {
                selectRegion(nil)
            }

            ForEach(AustrianFederalState.allCases) { federalState in
                Button(federalState.displayName) {
                    selectRegion(federalState)
                }
            }

            Button(AppStrings.Events.cancel, role: .cancel) {}
        }
        .appDestructiveActionDialog(Binding(
            get: {
                guard let eventID = pendingDeleteEventID else { return nil }
                let event = viewModel.event(for: eventID)
                return AppDestructiveActionDialog(
                    title: event.map(eventDestructiveActionConfirmationTitle(for:)) ?? AppStrings.Events.deleteConfirmation,
                    message: event.map(eventDestructiveActionConfirmationMessage(for:)) ?? "",
                    destructiveActionTitle: event.map(eventDestructiveActionTitle(for:)) ?? AppStrings.Events.delete,
                    cancelTitle: AppStrings.Events.cancel
                ) {
                    Task {
                        do {
                            try await viewModel.deleteEvent(id: eventID)
                            onEventDeleted()
                        } catch let appError as AppError {
                            deleteErrorEvent = event
                            deleteErrorMessage = readableEventErrorText(appError)
                            isShowingDeleteError = true
                        } catch {
                            deleteErrorEvent = event
                            deleteErrorMessage = AppStrings.Events.actionUnknownError
                            isShowingDeleteError = true
                        }
                        pendingDeleteEventID = nil
                    }
                }
            },
            set: { if $0 == nil { pendingDeleteEventID = nil } }
        ))
        .appErrorDialog(Binding(
            get: {
                guard isShowingDeleteError else { return nil }
                let event = deleteErrorEvent ?? pendingDeleteEventID.flatMap { viewModel.event(for: $0) }
                return AppErrorDialog(
                    title: event.map(eventDestructiveActionFailedTitle(for:)) ?? AppStrings.Events.deleteFailed,
                    message: deleteErrorMessage ?? AppStrings.Events.actionUnknownError,
                    okTitle: AppStrings.Events.dismissError
                )
            },
            set: {
                if $0 == nil {
                    isShowingDeleteError = false
                    deleteErrorEvent = nil
                    deleteErrorMessage = nil
                }
            }
        ))
    }

    private func scrollToTop(with scrollProxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy.scrollTo(eventsRootScrollTopID, anchor: .top)
        }
    }

    private func selectRegion(_ federalState: AustrianFederalState?) {
        selectedFederalState = federalState
        didManuallyChangeRegion = true
    }

    private func applyDefaultRegion() {
        guard !didManuallyChangeRegion else { return }
        selectedFederalState = authState.user?.selectedFederalState
    }

    private var eventsHeader: some View {
        AppSearchableBrandHeader(
            isSearchPresented: $isSearchPresented,
            searchText: $searchText,
            placeholder: AppStrings.Search.eventsPlaceholder,
            collapseToken: searchResetToken,
            creationKind: .event
        )
    }

    @ViewBuilder
    private var eventsHero: some View {
        if !featuredBannerViewModel.banners.isEmpty {
            FeaturedBannerCarouselView(
                banners: featuredBannerViewModel.banners,
                sizing: .responsiveHero,
                onBannerTap: onFeaturedBannerTap
            )
        } else if let error = featuredBannerViewModel.error {
            FeaturedBannerLoadFailureView(error: error) {
                await refreshFeaturedBanners()
            }
        }
    }

    private func refreshFeaturedBannersIfStale() async {
        await featuredBannerViewModel.refreshIfStale(
            for: .events,
            federalState: selectedFederalState
        )
    }

    private func refreshFeaturedBanners() async {
        await featuredBannerViewModel.refresh(
            for: .events,
            federalState: selectedFederalState
        )
    }

    @ViewBuilder
    private var eventListContent: some View {
        if viewModel.events.isEmpty && viewModel.isLoading {
            LoadingStateCard(title: nil)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.events.isEmpty && viewModel.error != nil {
            ErrorStateCard(
                systemImage: "calendar",
                title: AppStrings.Events.title,
                message: errorText,
                retryTitle: AppStrings.Events.retry
            ) {
                viewModel.reload()
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.events.isEmpty {
            EmptyStateCard(
                systemImage: "calendar",
                title: AppStrings.Events.title,
                message: AppStrings.Events.empty
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if filteredEvents.isEmpty, isLoadingSearchPages {
            LoadingStateCard(title: AppStrings.Search.searching)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if filteredEvents.isEmpty {
            EmptyStateCard(
                systemImage: hasActiveSearch ? "magnifyingglass" : filteredEventsEmptySystemImage,
                title: hasActiveSearch ? AppStrings.Search.noResultsTitle : AppStrings.Events.title,
                message: filteredEventsEmptyMessage
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            let content = discoveryContent

            VStack(alignment: .leading, spacing: AppTheme.eventsSectionSpacing) {
                upcomingContent(content)

                if !content.pastEvents.isEmpty {
                    pastContent(content)
                }
            }
        }
    }

    private var filteredEventsEmptySystemImage: String {
        switch selectedFeedScope {
        case .saved:
            "bookmark"
        case .registered:
            "checkmark.circle"
        case .all:
            selectedCategory == .all ? "calendar.badge.exclamationmark" : selectedCategory.systemImage
        }
    }

    private var filteredEventsEmptyMessage: String {
        if hasActiveSearch {
            return AppStrings.Search.noResultsMessage
        }

        return switch selectedFeedScope {
        case .saved:
            AppStrings.Events.emptySaved
        case .registered:
            AppStrings.Events.emptyRegistered
        case .all:
            selectedFederalState == nil ? AppStrings.Events.filteredUpcomingEmpty : AppStrings.Home.emptyRegion
        }
    }

    private func matchesSearch(_ event: Event) -> Bool {
        LocalSearchMatcher.matches(
            query: searchText,
            values: [
                event.localizedTitle,
                event.localizedSummary,
                event.localizedDetails,
                event.city,
                event.venue,
                event.address,
                event.locationNote,
                event.organizerName,
                event.authorName,
                event.source.displayOrganizationName,
                event.category.title,
                event.category.rawValue,
                event.audience.title,
                event.audience.rawValue
            ] + event.tags.map(Optional.some)
        )
    }

    private func upcomingContent(_ content: EventDiscoveryContent) -> some View {
        let monthSections = upcomingMonthSections(from: content.upcomingSections)

        return VStack(alignment: .leading, spacing: AppTheme.eventsSectionSpacing) {
            if content.upcomingSections.isEmpty {
                EmptyStateCard(
                    systemImage: "calendar.badge.exclamationmark",
                    title: AppStrings.Events.upcomingTitle,
                    message: AppStrings.Events.filteredUpcomingEmpty
                )
            } else {
                ForEach(monthSections) { section in
                    VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                        EventMonthHeader(title: eventMonthTitleText(for: section.monthStart))

                        DashboardFeedContainer(
                            items: section.events,
                            spacing: AppTheme.feedRowSpacing,
                            onItemAppear: { event in
                                Task {
                                    await viewModel.loadNextPageIfNeeded(currentItemID: event.id)
                                }
                            }
                        ) { event in
                            eventRow(for: event)
                        }
                    }
                }
            }
        }
    }

    private func upcomingMonthSections(from daySections: [UpcomingEventDaySection]) -> [UpcomingEventMonthSection] {
        let calendar = Calendar.current
        return calendarMonthGroups(daySections, calendar: calendar, date: \.date)
            .map { group in
                UpcomingEventMonthSection(
                    monthStart: group.monthStart,
                    events: group.elements
                        .sorted { $0.date < $1.date }
                        .flatMap(\.events)
                )
            }
    }

    private func pastContent(_ content: EventDiscoveryContent) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
            EventMonthHeader(title: AppStrings.Events.pastTitle)

            DashboardFeedContainer(
                items: content.pastEvents,
                spacing: AppTheme.feedRowSpacing,
                onItemAppear: { event in
                    Task {
                        await viewModel.loadNextPageIfNeeded(currentItemID: event.id)
                    }
                }
            ) { event in
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
            canDeleteEvent: canDeleteEvent(event),
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

    private func canManageEvent(_ event: Event) -> Bool {
        PermissionService.canDeleteEvent(event, user: authState.user)
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

private struct EventFilterRow: View {
    let selectedPeriod: EventDiscoveryFilter
    let selectedFederalState: AustrianFederalState?
    let selectedCategory: EventCategoryFilter
    let selectedAudience: EventAudienceFilter
    let selectedAge: EventAgeFilter
    let selectedFeedScope: EventFeedScope
    let onSelectPeriod: (EventDiscoveryFilter) -> Void
    let onSelectCategory: (EventCategoryFilter) -> Void
    let onSelectAudience: (EventAudienceFilter) -> Void
    let onSelectAge: (EventAgeFilter) -> Void
    let onSelectRegion: () -> Void
    let onSelectSaved: () -> Void
    let onSelectRegistered: () -> Void

    private enum Filter: String {
        case period, category, audience, age, region, registered, saved
    }

    var body: some View {
        AppPrioritizedFilterRow(
            pinned: [.period, .region],
            filters: [.category, .audience, .age, .registered, .saved],
            isActive: isActive
        ) { filter in
            filterControl(filter)
                .accessibilityIdentifier("events.filter.\(filter.rawValue)")
        }
        .accessibilityIdentifier("events.filters")
    }

    private func isActive(_ filter: Filter) -> Bool {
        switch filter {
        case .period: selectedPeriod != .all
        case .category: selectedCategory != .all
        case .audience: selectedAudience != .all
        case .age: selectedAge != .any
        case .region: selectedFederalState != nil
        case .registered: selectedFeedScope == .registered
        case .saved: selectedFeedScope == .saved
        }
    }

    @ViewBuilder
    private func filterControl(_ filter: Filter) -> some View {
        switch filter {
        case .period:
            Menu {
                ForEach(EventDiscoveryFilter.allCases) { period in
                    Button {
                        onSelectPeriod(period)
                    } label: {
                        Label(period.title, systemImage: period.systemImage)
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedPeriod.title,
                    systemImage: selectedPeriod.systemImage,
                    isSelected: selectedPeriod != .all,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        case .category:
            Menu {
                ForEach(EventCategoryFilter.allCases) { category in
                    Button {
                        onSelectCategory(category)
                    } label: {
                        Label(category.title, systemImage: category.systemImage)
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedCategory.title,
                    systemImage: selectedCategory.systemImage,
                    isSelected: selectedCategory != .all,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        case .audience:
            Menu {
                ForEach(EventAudienceFilter.allCases) { audience in
                    Button { onSelectAudience(audience) } label: {
                        Label(audience.title, systemImage: audience.systemImage)
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedAudience.title,
                    systemImage: selectedAudience.systemImage,
                    isSelected: selectedAudience != .all,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        case .age:
            Menu {
                ForEach(EventAgeFilter.allCases) { age in
                    Button { onSelectAge(age) } label: {
                        Label(age.title, systemImage: "birthday.cake")
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedAge.title,
                    systemImage: "birthday.cake",
                    isSelected: selectedAge != .any,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        case .region:
            Button(action: onSelectRegion) {
                AppFilterChip(
                    title: selectedFederalState?.displayName ?? AppStrings.Home.regionAllAustria,
                    systemImage: "mappin.and.ellipse",
                    isSelected: selectedFederalState != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        case .registered:
            Button(action: onSelectRegistered) {
                AppFilterChip(
                    title: AppStrings.Events.filterRegistered,
                    systemImage: "checkmark.circle.fill",
                    isSelected: selectedFeedScope == .registered
                )
            }
            .buttonStyle(.plain)
        case .saved:
            Button(action: onSelectSaved) {
                AppFilterChip(
                    title: AppStrings.Home.filterSaved,
                    systemImage: "bookmark",
                    isSelected: selectedFeedScope == .saved
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct EventMonthHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimaryForeground)
            .lineLimit(1)
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
        NavigationLink(value: EventNavigationRoute(eventID: event.id)) {
            EventCard(event: event)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("event.card.\(event.id)")
        .modifier(EventDeleteSwipeActions(isEnabled: canDeleteEvent, title: eventDestructiveActionTitle(for: event)) {
            pendingDeleteEventID = event.id
        })
    }
}


func readableEventErrorText(_ error: AppError?) -> String {
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

func sanitizedEventCommentAuthorName(_ rawValue: String) -> String {
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

struct EventCard: View {
    let event: Event
    var previewImage: UIImage? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SoftContentCard(padding: AppTheme.homeFeedCardPadding) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacing) {
                    HStack(alignment: .top, spacing: AppTheme.compactCardInnerSpacing) {
                        AppEventDateBlock(date: displayOccurrence.startDate)

                        Spacer(minLength: 0)

                        eventThumbnail
                    }

                    eventDetails
                }
            } else {
                HStack(alignment: .center, spacing: AppTheme.compactCardInnerSpacing) {
                    AppEventDateBlock(date: displayOccurrence.startDate)
                    eventDetails

                    Spacer(minLength: 0)

                    eventThumbnail
                        .layoutPriority(-1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var eventDetails: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
            typeChip

            Text(event.localizedTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if !event.localizedSummary.isEmpty {
                Text(event.localizedSummary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.compactCardInnerSpacingTight) {
                    AppMetadataLine(title: timeText, systemImage: "clock")
                    AppMetadataLine(title: locationText, systemImage: locationIcon)
                }

                VStack(alignment: .leading, spacing: 3) {
                    AppMetadataLine(title: timeText, systemImage: "clock")
                    AppMetadataLine(title: locationText, systemImage: locationIcon)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 0 : 6)
    }

    private var eventThumbnail: some View {
        Group {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: AppTheme.eventsThumbnailSize, height: AppTheme.eventsThumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCardCornerRadius, style: .continuous))
            } else {
                AppFeedThumbnail(
                    imageURL: event.imageURL,
                    fallbackSystemImage: "calendar",
                    tint: AppTheme.accentPrimaryForeground,
                    fill: AppTheme.badgeBlueFill,
                    size: AppTheme.eventsThumbnailSize,
                    cornerRadius: AppTheme.rowCardCornerRadius,
                    source: "EventCard"
                )
            }
        }
        .frame(maxHeight: AppTheme.eventsThumbnailSize)
    }

    private var typeChip: some View {
        AppInfoChip(
            title: AppStrings.Events.title.uppercased(),
            systemImage: "calendar",
            tint: AppTheme.accentPrimaryForeground,
            fill: AppTheme.badgeBlueFill,
            size: .small
        )
    }

    private var timeText: String {
        LocalizationStore.timeRangeString(
            startDate: displayOccurrence.startDate,
            endDate: displayOccurrence.endDate,
            isAllDay: displayOccurrence.isAllDay
        )
    }

    private var displayOccurrence: EventOccurrence {
        event.nextOccurrence() ?? event.occurrences.first ?? EventOccurrence(
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay
        )
    }

    private var locationText: String {
        event.city.isEmpty ? event.venue : event.city
    }

    private var locationIcon: String {
        event.city.isEmpty ? "building.2" : "mappin.and.ellipse"
    }

    private var accessibilitySummary: String {
        [
            event.localizedTitle,
            event.localizedSummary,
            eventScheduleText(for: event),
            event.city,
            event.registrationState.title,
            "\(event.likeCount) \(AppStrings.Common.likes)"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}

struct EventDeleteSwipeActions: ViewModifier {
    let isEnabled: Bool
    let title: String
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.swipeActions(edge: .trailing) {
                Button(title, role: .destructive) {
                    onDelete()
                }
            }
        } else {
            content
        }
    }
}
