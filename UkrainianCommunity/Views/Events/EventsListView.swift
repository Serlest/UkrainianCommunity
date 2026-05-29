import Combine
import PhotosUI
import SwiftUI

struct EventNavigationRoute: Hashable {
    let eventID: String
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

private enum EventCategoryFilter: CaseIterable, Identifiable {
    case all
    case meetups
    case training
    case culture
    case education
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            AppStrings.Events.filterAll
        case .meetups:
            AppStrings.Events.categoryMeetups
        case .training:
            AppStrings.Events.categoryTraining
        case .culture:
            AppStrings.Events.categoryCulture
        case .education:
            AppStrings.Events.categoryEducation
        case .other:
            AppStrings.Events.categoryOther
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "tag"
        case .meetups:
            "person.2"
        case .training:
            "graduationcap"
        case .culture:
            "theatermasks"
        case .education:
            "book"
        case .other:
            "square.grid.2x2"
        }
    }

    var category: EventCategory? {
        switch self {
        case .all:
            nil
        case .meetups:
            .meetups
        case .training:
            .training
        case .culture:
            .culture
        case .education:
            .education
        case .other:
            .other
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

private struct EventDiscoveryContent {
    let upcomingSections: [UpcomingEventDaySection]
    let pastEvents: [Event]
}

func eventScheduleText(for event: Event) -> String {
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

private func eventMonthTitleText(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = LocalizationStore.locale
    formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
    return formatter.string(from: date)
}

struct EventsListView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    @StateObject private var heroBannerViewModel: AppHeroBannerViewModel
    let eventRepository: EventRepository
    let onEventPublished: @MainActor () async -> Void
    let onEventDeleted: @MainActor @Sendable () -> Void
    let presentationMode: EventPresentationMode
    @State private var pendingDeleteEventID: String?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false
    @State private var selectedFilter: EventDiscoveryFilter = .all
    @State private var selectedCategory: EventCategoryFilter = .all
    @State private var selectedFederalState: AustrianFederalState?
    @State private var selectedFeedScope: EventFeedScope = .all
    @State private var didManuallyChangeRegion = false
    @State private var isRegionPickerPresented = false
    @State private var selectedBannerPhoto: PhotosPickerItem?
    @State private var guestAccessAction: GuestAccessAction?

    init(
        viewModel: EventsViewModel,
        eventRepository: EventRepository,
        bannerService: HomeBannerServiceProtocol = FirestoreHomeBannerService(),
        onEventPublished: @escaping @MainActor () async -> Void,
        onEventDeleted: @escaping @MainActor @Sendable () -> Void,
        presentationMode: EventPresentationMode = .public
    ) {
        self.viewModel = viewModel
        self.eventRepository = eventRepository
        self.onEventPublished = onEventPublished
        self.onEventDeleted = onEventDeleted
        self.presentationMode = presentationMode
        _heroBannerViewModel = StateObject(wrappedValue: AppHeroBannerViewModel(
            section: .events,
            bannerService: bannerService
        ))
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

        let pastEvents = events
            .filter { $0.endDate < now }
            .sorted { $0.startDate > $1.startDate }

        return EventDiscoveryContent(upcomingSections: upcomingSections, pastEvents: pastEvents)
    }

    private var filteredEvents: [Event] {
        viewModel.events.filter { event in
            matchesSelectedCategory(event)
                && matchesSelectedRegion(event)
                && matchesSelectedFeedScope(event)
        }
    }

    private func matchesSelectedRegion(_ event: Event) -> Bool {
        guard let selectedFederalState else { return true }
        return event.federalState == selectedFederalState
    }

    private func matchesSelectedCategory(_ event: Event) -> Bool {
        guard let category = selectedCategory.category else { return true }
        return event.category == category
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                eventsHeader
                    .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

                eventsHero
                    .padding(.bottom, AppTheme.homeSectionSpacing)

                EventFilterRow(
                    selectedFederalState: selectedFederalState,
                    selectedCategory: selectedCategory,
                    selectedFeedScope: selectedFeedScope,
                    onSelectCategory: { selectedCategory = $0 },
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
        .task {
            applyDefaultRegion()
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
            await heroBannerViewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
            await heroBannerViewModel.refresh()
        }
        .onChange(of: selectedBannerPhoto) { _, newItem in
            Task {
                await updateEventsBanner(from: newItem)
                selectedBannerPhoto = nil
            }
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
        .confirmationDialog(AppStrings.Home.regionAllAustria, isPresented: $isRegionPickerPresented, titleVisibility: .visible) {
            Button(AppStrings.Home.regionAllAustria) {
                selectRegion(nil)
            }

            ForEach(AustrianFederalState.allCases) { federalState in
                Button(federalState.eventFilterDisplayName) {
                    selectRegion(federalState)
                }
            }

            Button(AppStrings.Events.cancel, role: .cancel) {}
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
        .alert(
            AppStrings.Home.bannerUploadFailed,
            isPresented: Binding(
                get: { heroBannerViewModel.error != nil },
                set: { isPresented in
                    if !isPresented {
                        heroBannerViewModel.clearError()
                    }
                }
            )
        ) {
            Button(AppStrings.News.dismissError, role: .cancel) {
                heroBannerViewModel.clearError()
            }
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
        AppBrandHeader {
            EmptyView()
        }
    }

    private var eventsHero: some View {
        ZStack(alignment: .bottomTrailing) {
            AppHeroBanner(
                title: AppStrings.Events.heroTitle,
                subtitle: AppStrings.Events.heroSubtitle,
                imageSource: heroBannerViewModel.imageSource,
                height: AppTheme.eventsHeroHeight,
                displaysTextOverImage: true
            )

            if PermissionService.canManageHomeBanner(user: authState.user) {
                AppHeroBannerEditButton(
                    selectedItem: $selectedBannerPhoto,
                    isUploading: heroBannerViewModel.isUploading
                )
                .padding(10)
            }
        }
    }

    private func updateEventsBanner(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                heroBannerViewModel.setSelectionFailed()
                return
            }

            await heroBannerViewModel.updateImage(data: data, user: authState.user)
        } catch {
            heroBannerViewModel.setSelectionFailed()
        }
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
        } else if filteredEvents.isEmpty {
            EmptyStateCard(
                systemImage: filteredEventsEmptySystemImage,
                title: AppStrings.Events.title,
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
        switch selectedFeedScope {
        case .saved:
            AppStrings.Events.emptySaved
        case .registered:
            AppStrings.Events.emptyRegistered
        case .all:
            selectedFederalState == nil ? AppStrings.Events.filteredUpcomingEmpty : AppStrings.Home.emptyRegion
        }
    }

    private func upcomingContent(_ content: EventDiscoveryContent) -> some View {
        let upcomingEvents = content.upcomingSections.flatMap(\.events)

        return VStack(alignment: .leading, spacing: AppTheme.eventsListRowSpacing) {
            if let firstDate = upcomingEvents.first?.startDate {
                EventMonthHeader(title: eventMonthTitleText(for: firstDate))
            }

            if content.upcomingSections.isEmpty {
                EmptyStateCard(
                    systemImage: "calendar.badge.exclamationmark",
                    title: AppStrings.Events.upcomingTitle,
                    message: AppStrings.Events.filteredUpcomingEmpty
                )
            } else {
                DashboardFeedContainer(items: upcomingEvents, spacing: AppTheme.eventsListRowSpacing) { event in
                    eventRow(for: event)
                }
            }
        }
    }

    private func pastContent(_ content: EventDiscoveryContent) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsListRowSpacing) {
            EventMonthHeader(title: AppStrings.Events.pastTitle)

            DashboardFeedContainer(items: content.pastEvents, spacing: AppTheme.eventsListRowSpacing) { event in
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

    var next: EventDiscoveryFilter {
        switch self {
        case .all:
            .today
        case .today:
            .thisWeek
        case .thisWeek:
            .all
        }
    }
}

private struct EventFilterRow: View {
    let selectedFederalState: AustrianFederalState?
    let selectedCategory: EventCategoryFilter
    let selectedFeedScope: EventFeedScope
    let onSelectCategory: (EventCategoryFilter) -> Void
    let onSelectRegion: () -> Void
    let onSelectSaved: () -> Void
    let onSelectRegistered: () -> Void

    var body: some View {
        AppHorizontalFilterRow {
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

            Button(action: onSelectRegion) {
                AppFilterChip(
                    title: selectedFederalState?.eventFilterDisplayName ?? AppStrings.Home.regionAllAustria,
                    systemImage: "mappin.and.ellipse",
                    isSelected: selectedFederalState != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)

            Button(action: onSelectRegistered) {
                AppFilterChip(
                    title: AppStrings.Events.filterRegistered,
                    systemImage: "checkmark.circle.fill",
                    isSelected: selectedFeedScope == .registered
                )
            }
            .buttonStyle(.plain)

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

private extension AustrianFederalState {
    var eventFilterDisplayName: String {
        switch self {
        case .burgenland:
            "Burgenland"
        case .kaernten:
            "Kärnten"
        case .niederoesterreich:
            "Niederösterreich"
        case .oberoesterreich:
            "Oberösterreich"
        case .salzburg:
            "Salzburg"
        case .steiermark:
            "Steiermark"
        case .tirol:
            "Tirol"
        case .vorarlberg:
            "Vorarlberg"
        case .wien:
            "Wien"
        }
    }
}

private struct EventMonthHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
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
        .modifier(EventDeleteSwipeActions(isEnabled: canDeleteEvent) {
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

private struct EventCard: View {
    let event: Event

    var body: some View {
        SoftContentCard(padding: AppTheme.eventsCardPadding) {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                AppEventDateBlock(date: event.startDate)

                VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
                    typeChip

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
                        AppMetadataLine(title: timeText, systemImage: "clock")
                        AppMetadataLine(title: locationText, systemImage: locationIcon)
                    }
                }
                .padding(.trailing, 6)

                Spacer(minLength: 0)

                AppFeedThumbnail(
                    imageURL: event.imageURL,
                    fallbackSystemImage: "calendar",
                    tint: AppTheme.accentPrimary,
                    fill: AppTheme.badgeBlueFill,
                    size: AppTheme.eventsThumbnailSize,
                    cornerRadius: 14,
                    source: "EventCard"
                )
                .padding(.trailing, 26)
                .frame(maxHeight: AppTheme.eventsThumbnailSize)
                .layoutPriority(-1)
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
            fill: AppTheme.badgeBlueFill,
            size: .small
        )
    }

    private var timeText: String {
        LocalizationStore.timeRangeString(startDate: event.startDate, endDate: event.endDate)
    }

    private var locationText: String {
        event.city.isEmpty ? event.venue : event.city
    }

    private var locationIcon: String {
        event.city.isEmpty ? "building.2" : "mappin.and.ellipse"
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

struct EventDeleteSwipeActions: ViewModifier {
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
