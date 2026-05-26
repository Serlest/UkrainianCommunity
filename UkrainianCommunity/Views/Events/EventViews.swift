import Combine
import EventKit
import MapKit
import PhotosUI
import SwiftUI
import UIKit

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
            .padding(.bottom, 112)
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
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
            AppNotificationBellButton()
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

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.eventPresentationMode) private var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    let eventID: String
    let onEventDeleted: @MainActor @Sendable () -> Void
    private let organizationRepository: OrganizationRepository
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var isDeleting = false
    @State private var isShowingEditSheet = false
    @State private var sharePayload: EventSharePayload?
    @State private var pendingRemovalEventID: String?
    @State private var guestAccessAction: GuestAccessAction?
    @State private var calendarAlert: EventCalendarAlert?
    @State private var calendarEventIDs = Set<String>()
    @State private var isAddingToCalendar = false
    @State private var recordedViewKeys = Set<String>()
    @State private var commentText = ""
    @State private var editingCommentID: String?
    @State private var pendingCommentDeleteID: String?
    @State private var commentDeleteErrorMessage: String?
    @State private var permissionOrganization: Organization?
    @FocusState private var isCommentFieldFocused: Bool
    private let calendarWriter = EventCalendarWriter()
    private let commentsSectionID = "eventCommentsSection"
    private let detailImageHeight: CGFloat = 220
    private let detailCardPadding: CGFloat = 14
    private let detailCardRadius: CGFloat = 18
    private let detailSectionSpacing: CGFloat = 13

    init(
        viewModel: EventsViewModel,
        eventID: String,
        onEventDeleted: @escaping @MainActor @Sendable () -> Void,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.viewModel = viewModel
        self.eventID = eventID
        self.onEventDeleted = onEventDeleted
        self.organizationRepository = organizationRepository
    }

    private func canEditEvent(_ event: Event) -> Bool {
        if let organizationID = event.source.organizationId,
           let organization = organizationForPermissions(organizationID: organizationID) {
            return PermissionService.canEditOrganizationEvent(organization, user: authState.user)
        }
        return PermissionService.canEditEvent(event, user: authState.user)
    }

    private func canDeleteEvent(_ event: Event) -> Bool {
        if let organizationID = event.source.organizationId,
           let organization = organizationForPermissions(organizationID: organizationID) {
            return PermissionService.canManageOrganizationRoles(organization, user: authState.user)
        }
        return PermissionService.canDeleteEvent(event, user: authState.user)
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
                    let contentHorizontalPadding = AppTheme.pageHorizontal
                    let contentWidth = max(proxy.size.width - (contentHorizontalPadding * 2), 0)

                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: detailSectionSpacing) {
                                detailHeader

                                articleHeader(for: event)
                                    .onTapGesture { isCommentFieldFocused = false }

                                heroImageSection(for: event)
                                    .onTapGesture { isCommentFieldFocused = false }

                                if !event.summary.isEmpty {
                                    leadBlock(for: event)
                                        .onTapGesture { isCommentFieldFocused = false }
                                }

                                eventScheduleCard(for: event)
                                    .onTapGesture { isCommentFieldFocused = false }

                                primaryActionsCard(for: event)
                                    .onTapGesture { isCommentFieldFocused = false }

                                aboutCard(for: event)
                                    .onTapGesture { isCommentFieldFocused = false }

                                organizerCard(for: event)
                                    .onTapGesture { isCommentFieldFocused = false }

                                locationCard(for: event)
                                    .onTapGesture { isCommentFieldFocused = false }

                                detailsCard(for: event)
                                    .onTapGesture { isCommentFieldFocused = false }

                                similarEventsSection(for: event)
                                    .onTapGesture { isCommentFieldFocused = false }

                                engagementCard(for: event, scrollProxy: scrollProxy)

                                managementCard
                                    .onTapGesture { isCommentFieldFocused = false }

                                commentsCard(for: event)
                                    .id(commentsSectionID)
                            }
                            .frame(width: contentWidth, alignment: .leading)
                            .padding(.horizontal, contentHorizontalPadding)
                            .padding(.bottom, AppTheme.homeBottomContentPadding + 160)
                        }
                        .frame(width: proxy.size.width)
                        .scrollDismissesKeyboard(.interactively)
                        .refreshable {
                            await refreshEventDetail()
                        }
                    }
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(AppStrings.Events.deleteConfirmation, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(AppStrings.Events.delete, role: .destructive) {
                Task {
                    await deleteCurrentEvent()
                }
            }
            Button(AppStrings.Events.cancel, role: .cancel) {}
        }
        .confirmationDialog(AppStrings.Common.deleteCommentConfirmation, isPresented: Binding(
            get: { pendingCommentDeleteID != nil },
            set: { if !$0 { pendingCommentDeleteID = nil } }
        ), titleVisibility: .visible) {
            Button(AppStrings.Action.delete, role: .destructive) {
                guard let pendingCommentDeleteID else { return }
                Task {
                    await deleteComment(commentID: pendingCommentDeleteID)
                }
            }
            Button(AppStrings.Events.cancel, role: .cancel) {
                pendingCommentDeleteID = nil
            }
        }
        .alert(AppStrings.Events.deleteFailed, isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button(AppStrings.Events.dismissError, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert(AppStrings.Common.deleteCommentFailed, isPresented: Binding(
            get: { commentDeleteErrorMessage != nil },
            set: { if !$0 { commentDeleteErrorMessage = nil } }
        )) {
            Button(AppStrings.Events.dismissError, role: .cancel) {}
        } message: {
            Text(commentDeleteErrorMessage ?? readableEventErrorText(.unknown))
        }
        .alert(calendarAlert?.title ?? "", isPresented: Binding(
            get: { calendarAlert != nil },
            set: { if !$0 { calendarAlert = nil } }
        )) {
            Button(AppStrings.Common.ok, role: .cancel) {
                calendarAlert = nil
            }
        } message: {
            Text(calendarAlert?.message ?? "")
        }
        .sheet(isPresented: $isShowingEditSheet) {
            editSheetContent
        }
        .sheet(item: $sharePayload) { payload in
            EventShareSheet(activityItems: payload.items)
        }
        .guestAccessAlert($guestAccessAction)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppStrings.Common.done) {
                    isCommentFieldFocused = false
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            guard let event = viewModel.event(for: eventID) else { return }
            await loadPermissionOrganizationIfNeeded(organizationID: event.source.organizationId)
            await viewModel.loadComments(for: eventID)
            guard !recordedViewKeys.contains(eventViewTaskID) else { return }
            recordedViewKeys.insert(eventViewTaskID)
            viewModel.recordView(for: eventID)
            RecentViewRecorder.recordEvent(event)
        }
        .onChange(of: authState.user?.id) { _, _ in
            guard let event = viewModel.event(for: eventID) else { return }
            guard !recordedViewKeys.contains(eventViewTaskID) else { return }
            recordedViewKeys.insert(eventViewTaskID)
            viewModel.recordView(for: eventID)
            RecentViewRecorder.recordEvent(event)
        }
        .onDisappear {
            guard let pendingRemovalEventID else { return }
            withTransaction(Transaction(animation: nil)) {
                viewModel.removeDeletedEvent(id: pendingRemovalEventID)
            }
            self.pendingRemovalEventID = nil
        }
    }

    private func refreshEventDetail() async {
        await viewModel.refresh()
        guard let event = viewModel.event(for: eventID) else { return }
        await loadPermissionOrganizationIfNeeded(organizationID: event.source.organizationId)
        await viewModel.loadComments(for: eventID)
    }

    private var detailHeader: some View {
        AppCenteredBrandHeader {
            detailIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                isCommentFieldFocused = false
                dismiss()
            }
        } trailingContent: {
            HStack(spacing: 10) {
                detailIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: AppStrings.Action.share) {
                    if let event = viewModel.event(for: eventID) {
                        sharePayload = EventSharePayload(event: event)
                    }
                }

                if let event = viewModel.event(for: eventID) {
                    detailIconButton(
                        systemImage: event.isBookmarked ? "bookmark.fill" : "bookmark",
                        accessibilityLabel: AppStrings.Action.save
                    ) {
                        handleBookmark(for: event)
                    }
                    .disabled(viewModel.pendingEventBookmarkIDs.contains(event.id))
                }
            }
        }
    }

    private func detailIconButton(
        systemImage: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        AppGlassIconButton(
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel,
            role: role
        ) {
            action()
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func heroImageSection(for event: Event) -> some View {
        if let imageURL = eventImageURL(for: event) {
            eventHeroImage(imageURL: imageURL, size: nil)
        }
    }

    private func articleHeader(for event: Event) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            eventBadge(for: event)

            Text(event.title)
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(AppTheme.accentPrimary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            metadataRow(for: event)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func eventBadge(for event: Event) -> some View {
        Label {
            Text(eventDetailCategoryTitle(for: event.category).uppercased())
                .font(.caption2.weight(.bold))
        } icon: {
            Image(systemName: event.category.systemImage)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(AppTheme.badgePurpleFill, in: Capsule())
    }

    private func metadataRow(for event: Event) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                metadataItems(for: event)
            }

            VStack(alignment: .leading, spacing: 7) {
                metadataItems(for: event)
            }
        }
    }

    private func metadataItems(for event: Event) -> some View {
        Group {
            detailMetadataItem(systemImage: "calendar", text: LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .none))
            detailMetadataItem(systemImage: "clock", text: LocalizationStore.timeRangeString(startDate: event.startDate, endDate: event.endDate))
            detailMetadataItem(systemImage: "eye", text: eventViewCountText(for: event))
        }
    }

    private func detailMetadataItem(systemImage: String, text: String) -> some View {
        Label {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 15, height: 15)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.accentPrimary.opacity(0.88))
    }

    private func eventHeroImage(imageURL: String, size: CGFloat?) -> some View {
        RemoteImageView(
            imageURL: imageURL,
            height: size ?? detailImageHeight,
            cornerRadius: AppTheme.imageRadius,
            source: "EventDetailView",
            placeholderStyle: .glassSkeleton
        )
        .frame(width: size, height: size)
        .frame(minHeight: size == nil ? detailImageHeight : nil, maxHeight: size == nil ? detailImageHeight : nil)
        .frame(maxWidth: size == nil ? .infinity : size)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.78))
        )
        .shadow(color: AppTheme.glassShadow(for: colorScheme).opacity(0.55), radius: 8, y: 4)
    }

    private func eventImageURL(for event: Event) -> String? {
        guard let imageURL = event.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
            return nil
        }
        return imageURL
    }

    private func eventDetailCategoryTitle(for category: EventCategory) -> String {
        switch category {
        case .unspecified:
            AppStrings.Events.genericEventBadge
        case .meetups:
            AppStrings.Events.categoryMeetupSingular
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

    private func leadBlock(for event: Event) -> some View {
        detailGlassCard(padding: 12) {
            HStack(alignment: .top, spacing: AppTheme.dashboardSpacing) {
                Image(systemName: "info.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.Events.aboutSectionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(event.summary)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func eventScheduleCard(for event: Event) -> some View {
        detailGlassCard(padding: detailCardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.Events.detailsSectionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)

                EventDetailRow(systemImage: "calendar", title: AppStrings.Events.fieldStartDate, value: LocalizationStore.dateString(from: event.startDate, dateStyle: .full, timeStyle: .none))
                EventDetailRow(systemImage: "clock", title: AppStrings.Events.startTime, value: LocalizationStore.timeRangeString(startDate: event.startDate, endDate: event.endDate))

                if Calendar.current.startOfDay(for: event.endDate) != Calendar.current.startOfDay(for: event.startDate) {
                    EventDetailRow(systemImage: "calendar.badge.clock", title: AppStrings.Events.fieldEndDate, value: LocalizationStore.dateString(from: event.endDate, dateStyle: .full, timeStyle: .short))
                }
            }
        }
    }

    private func primaryActionsCard(for event: Event) -> some View {
        detailGlassCard(padding: 9) {
            HStack(spacing: 12) {
                registrationButton(for: event)
                    .frame(maxWidth: .infinity)

                eventActionButton(
                    title: AppStrings.Events.addToCalendar,
                    systemImage: calendarEventIDs.contains(event.id) ? "checkmark.circle.fill" : "calendar.badge.plus",
                    isDisabled: isAddingToCalendar
                ) {
                    addToCalendar(event)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func eventActionButton(title: String, systemImage: String, isDisabled: Bool = false, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, AppTheme.eventsMetadataSpacing)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.68 : 1)
    }

    private func engagementCard(for event: Event, scrollProxy: ScrollViewProxy) -> some View {
        detailGlassCard(padding: 9) {
            HStack(spacing: 12) {
                eventMetricButton(
                    systemImage: event.likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                    count: event.likeCount,
                    accessibilityLabel: event.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like,
                    isSelected: event.likeState.isLiked
                ) {
                    handleLike(for: event)
                }
                .disabled(viewModel.pendingEventLikeIDs.contains(event.id))
                .accessibilityIdentifier("event.like.\(event.id)")
                .accessibilityHint(AppStrings.Common.likes)

                eventMetricButton(
                    systemImage: "bubble.left",
                    count: event.commentCount,
                    accessibilityLabel: AppStrings.Common.comments
                ) {
                    focusEventComments(using: scrollProxy)
                }

                Spacer(minLength: 0)

                publisherLine(for: event)
            }
        }
    }

    private func focusEventComments(using scrollProxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.32)) {
            scrollProxy.scrollTo(commentsSectionID, anchor: .top)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            isCommentFieldFocused = true
        }
    }

    private func eventMetricButton(
        systemImage: String,
        count: Int,
        accessibilityLabel: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? AppTheme.accentDestructive : AppTheme.accentPrimary)

                Text("\(count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
            }
            .frame(minWidth: 74, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(count)")
    }

    private func publisherLine(for event: Event) -> some View {
        Label(eventPublisherText(for: event), systemImage: "person.crop.circle")
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.86))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 190, alignment: .trailing)
            .accessibilityLabel(eventPublisherText(for: event))
    }

    @ViewBuilder
    private func infoCard(for event: Event) -> some View {
        if let capacity = event.capacity ?? (event.registeredCount > 0 ? event.registeredCount : nil) {
            SoftContentCard(padding: AppTheme.detailCompactCardPadding) {
                HStack(spacing: AppTheme.dashboardSpacing) {
                    Image(systemName: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)

                    VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
                        Text(AppStrings.Events.expectedParticipants)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(event.capacity == nil ? "\(event.registeredCount)" : "\(event.registeredCount) / \(capacity)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
    }

    private func aboutCard(for event: Event) -> some View {
        detailGlassCard(padding: detailCardPadding) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.Events.aboutSectionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)

                Text(event.details)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.accentPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func organizerCard(for event: Event) -> some View {
        detailGlassCard(padding: detailCardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.Events.detailOrganizerSectionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)

                HStack(spacing: AppTheme.dashboardSpacing) {
                    AppFeedThumbnail(
                        imageURL: event.source.organizationImageURL,
                        fallbackSystemImage: "building.2",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.accentPrimarySoft,
                        size: AppTheme.organizationsThumbnailSize,
                        cornerRadius: AppTheme.feedThumbnailRadius,
                        source: "EventDetailOrganizer"
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(eventSourceName(for: event))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)

                        Label(eventPublisherText(for: event), systemImage: "person.crop.circle")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        AppInfoChip(
                            title: event.source.sourceType == .organization ? AppStrings.Organizations.detailBadge : AppStrings.Home.brandTitle,
                            systemImage: "building.2",
                            tint: AppTheme.accentPrimary,
                            fill: AppTheme.accentPrimarySoft,
                            size: .small
                        )
                    }

                }
            }
        }
    }

    private func detailsCard(for event: Event) -> some View {
        detailGlassCard(padding: detailCardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.Events.detailsSectionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)
                EventDetailRow(systemImage: "tag", title: AppStrings.Events.priceTitle, value: eventPriceText(for: event))
                EventDetailRow(systemImage: "person.2", title: AppStrings.Events.expectedParticipants, value: eventParticipantsText(for: event))
                EventDetailRow(systemImage: "calendar", title: AppStrings.Events.addedDate, value: LocalizationStore.dateString(from: event.createdAt, dateStyle: .medium, timeStyle: .none))
            }
        }
    }

    private func locationCard(for event: Event) -> some View {
        detailGlassCard(padding: detailCardPadding) {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                Text(AppStrings.Events.locationSectionTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)

                if let coordinate = eventCoordinate(for: event) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: AppTheme.dashboardSpacing) {
                            locationMapPreviewBlock(coordinate: coordinate)

                            locationVenueBlock(for: event, alignsWithMapPreview: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                        }

                        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                            eventMapPreview(coordinate: coordinate)
                                .frame(maxWidth: .infinity)
                                .frame(height: 144)

                            locationVenueBlock(for: event)
                        }
                    }
                } else {
                    locationVenueBlock(for: event)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func locationVenueBlock(for event: Event, alignsWithMapPreview: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            locationTextBlock(for: event)

            if alignsWithMapPreview {
                Spacer(minLength: AppTheme.eventsMetadataSpacing)
            }

            eventActionButton(title: AppStrings.Events.showOnMap, systemImage: "location.north", isDisabled: !canOpenEventInMaps(event)) {
                openEventInMaps(event)
            }
            .padding(.top, 2)
        }
        .frame(minHeight: alignsWithMapPreview ? 124 : 0, alignment: .top)
    }

    private func locationTextBlock(for event: Event) -> some View {
        let locationLines = deduplicatedLocationLines(for: event)

        return VStack(alignment: .leading, spacing: 5) {
            Text(locationLines.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            if let subtitle = locationLines.subtitle {
                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }

            if let city = locationLines.city {
                Text(city)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
                    .lineLimit(1)
            }

            if let locationNote = locationNoteText(for: event) {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary.opacity(0.86))
                        .padding(.top, 1)

                    Text(locationNote)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(3)
                }
                .padding(.top, 2)
            }
        }
    }

    private func locationNoteText(for event: Event) -> String? {
        let trimmedLocationNote = event.locationNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLocationNote?.isEmpty == true ? nil : trimmedLocationNote
    }

    private func locationMapPreviewBlock(coordinate: CLLocationCoordinate2D) -> some View {
        VStack {
            Spacer(minLength: 0)
            eventMapPreview(coordinate: coordinate)
                .frame(width: 158, height: 112)
            Spacer(minLength: 0)
        }
        .frame(width: 158, alignment: .center)
        .frame(minHeight: 124, alignment: .center)
    }

    private func eventMapPreview(coordinate: CLLocationCoordinate2D) -> some View {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )

        return Map(initialPosition: .region(region), interactionModes: []) {
            Marker("", coordinate: coordinate)
                .tint(AppTheme.accentPrimary)
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
    }

    @ViewBuilder
    private func similarEventsSection(for event: Event) -> some View {
        let similarEvents = viewModel.events
            .filter { $0.id != event.id && $0.endDate >= Date() }
            .prefix(6)

        if !similarEvents.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(AppStrings.Events.similarEvents)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Text(AppStrings.Common.viewAll)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .opacity(0.72)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.eventsMetadataSpacing) {
                        ForEach(Array(similarEvents)) { relatedEvent in
                            EventSimilarCard(event: relatedEvent)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private func commentsCard(for event: Event) -> some View {
        detailGlassCard(padding: detailCardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.Common.comments)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)

                eventCommentComposer(eventID: event.id)

                if event.comments.isEmpty {
                    Text(AppStrings.Common.noCommentsYet)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(event.comments) { comment in
                        eventCommentRow(comment)
                            .padding(.vertical, AppTheme.eventsCardContentSpacing)
                    }
                }
            }
        }
    }

    private func eventCommentComposer(eventID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if authState.isAuthenticated {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(AppStrings.Common.commentInputPlaceholder, text: $commentText, axis: .vertical)
                        .focused($isCommentFieldFocused)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                        )

                    Button {
                        submitEventComment(eventID: eventID)
                    } label: {
                        Image(systemName: editingCommentID == nil ? "paperplane.fill" : "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.accentPrimary, in: Circle())
                    }
                    .disabled(trimmedCommentText.isEmpty || viewModel.pendingEventCommentIDs.contains(eventID))
                    .opacity(trimmedCommentText.isEmpty ? 0.55 : 1)
                }

                Text("\(commentText.count)/1000")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Button {
                    guestAccessAction = .comments
                } label: {
                    Label(AppStrings.Common.signInToComment, systemImage: "person.crop.circle.badge.plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func eventCommentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            eventCommentAvatar(comment)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Text(sanitizedEventCommentAuthorName(comment.authorName))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Text(LocalizationStore.dateString(from: comment.createdAt, dateStyle: .short, timeStyle: .short))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    if canEditComment(comment) || canDeleteComment(comment) {
                        eventCommentActionMenu(for: comment)
                    }
                }

                Text(comment.text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func eventCommentActionMenu(for comment: Comment) -> some View {
        Menu {
            if canEditComment(comment) {
                Button(AppStrings.Action.edit, systemImage: "pencil") {
                    editingCommentID = comment.id
                    commentText = comment.text
                    isCommentFieldFocused = true
                }
            }
            if canDeleteComment(comment) {
                Button(AppStrings.Action.delete, systemImage: "trash", role: .destructive) {
                    pendingCommentDeleteID = comment.id
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.Action.delete)
    }

    @ViewBuilder
    private var managementCard: some View {
        if let event = viewModel.event(for: eventID), canEditEvent(event) || canDeleteEvent(event) {
            detailGlassCard(padding: 9) {
                HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                    if canEditEvent(event) {
                        eventManagementButton(title: AppStrings.Action.edit, systemImage: "pencil") {
                            isShowingEditSheet = true
                        }
                    }

                    if canDeleteEvent(event) {
                        eventManagementButton(title: AppStrings.Action.delete, systemImage: "trash", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(isDeleting)
                    }
                }
            }
        }
    }

    private func eventManagementButton(title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(role == .destructive ? AppTheme.accentDestructive : AppTheme.accentPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
        Button {
            guard authState.isAuthenticated else {
                guestAccessAction = .registration
                return
            }

            viewModel.toggleRegistration(for: event.id)
        } label: {
            Label(event.registrationState == .registered ? AppStrings.Events.registered : AppStrings.Events.register, systemImage: event.registrationState == .registered ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, AppTheme.eventsMetadataSpacing)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(AppTheme.accentPrimary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.pendingEventRegistrationIDs.contains(event.id))
        .accessibilityIdentifier("event.register.\(event.id)")
        .accessibilityLabel(event.registrationState == .registered ? AppStrings.Action.cancelRegistration : AppStrings.Action.register)
        .accessibilityHint(AppStrings.Events.title)
    }

    private func handleBookmark(for event: Event) {
        guard authState.isAuthenticated else {
            guestAccessAction = .bookmarks
            return
        }

        viewModel.toggleBookmark(for: event.id)
    }

    private func handleLike(for event: Event) {
        guard authState.isAuthenticated else {
            guestAccessAction = .likes
            return
        }

        viewModel.toggleLike(for: event.id)
    }

    private var trimmedCommentText: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitEventComment(eventID: String) {
        guard let user = authState.user else {
            guestAccessAction = .comments
            return
        }
        let text = String(trimmedCommentText.prefix(1000))
        guard !text.isEmpty else { return }
        let editingID = editingCommentID
        Task {
            if let editingID {
                await viewModel.updateComment(eventID: eventID, commentID: editingID, text: text)
            } else {
                await viewModel.addComment(to: eventID, text: text, author: user)
            }
            await MainActor.run {
                commentText = ""
                editingCommentID = nil
                isCommentFieldFocused = false
            }
        }
    }

    private func canEditComment(_ comment: Comment) -> Bool {
        guard let user = authState.user else { return false }
        return comment.authorId == user.id
    }

    private func canDeleteComment(_ comment: Comment) -> Bool {
        guard let user = authState.user else { return false }
        if comment.authorId == user.id {
            return true
        }
        if PermissionService.canModerate(section: .comments, user: user) || PermissionService.canModerate(section: .events, user: user) {
            return true
        }
        guard let event = viewModel.event(for: eventID), let organizationId = event.source.organizationId else {
            return false
        }
        if let organization = organizationForPermissions(organizationID: organizationId) {
            return PermissionService.canModerateOrganizationContent(organization, user: user)
        }
        return PermissionService.canModerateOrganizationComments(organizationId: organizationId, user: user)
    }

    private func organizationForPermissions(organizationID: String) -> Organization? {
        guard permissionOrganization?.id == organizationID else { return nil }
        return permissionOrganization
    }

    @MainActor
    private func loadPermissionOrganizationIfNeeded(organizationID: String?) async {
        guard let organizationID else {
            permissionOrganization = nil
            return
        }
        guard permissionOrganization?.id != organizationID else { return }

        do {
            permissionOrganization = try await organizationRepository.fetchOrganization(id: organizationID)
        } catch {
            permissionOrganization = nil
        }
    }

    @MainActor
    private func deleteComment(commentID: String) async {
        pendingCommentDeleteID = nil
        await viewModel.deleteComment(eventID: eventID, commentID: commentID)
        if let error = viewModel.error {
            commentDeleteErrorMessage = readableEventErrorText(error)
        }
    }

    private func eventCommentAvatar(_ comment: Comment) -> some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentPrimarySoft)
            if let authorPhotoURL = comment.authorPhotoURL, !authorPhotoURL.isEmpty {
                AsyncImage(url: URL(string: authorPhotoURL)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Text(eventCommentInitials(comment))
                            .font(.caption.weight(.bold))
                    }
                }
            } else {
                Text(eventCommentInitials(comment))
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(AppTheme.accentPrimary)
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private func eventCommentInitials(_ comment: Comment) -> String {
        let name = sanitizedEventCommentAuthorName(comment.authorName)
        return String(name.prefix(1)).uppercased()
    }

    private func addToCalendar(_ event: Event) {
        guard !isAddingToCalendar else { return }
        guard !calendarEventIDs.contains(event.id) else {
            calendarAlert = .alreadyAdded
            return
        }

        Task {
            isAddingToCalendar = true
            defer { isAddingToCalendar = false }

            do {
                try await calendarWriter.add(event)
                calendarEventIDs.insert(event.id)
                calendarAlert = .added
            } catch EventCalendarWriter.CalendarError.accessDenied {
                calendarAlert = .permissionDenied
            } catch {
                calendarAlert = .failed
            }
        }
    }

    private func detailGlassCard<Content: View>(padding: CGFloat = 14, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(
            cornerRadius: detailCardRadius,
            material: .ultraThinMaterial,
            surface: AppTheme.glassSurface(for: colorScheme),
            borderOpacity: 0.62,
            shadowRadius: 8,
            shadowY: 4
        )
    }

    private func eventParticipantsText(for event: Event) -> String {
        if let capacity = event.capacity {
            "\(event.registeredCount) / \(capacity)"
        } else {
            "\(event.registeredCount)"
        }
    }

    private func eventSourceName(for event: Event) -> String {
        let organizationName = event.source.displayOrganizationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return organizationName.isEmpty ? AppStrings.Home.brandTitle : organizationName
    }

    private func eventPublisherText(for event: Event) -> String {
        let sourceName = eventSourceName(for: event)
        let authorName = event.authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !authorName.isEmpty else {
            return sourceName
        }

        return "\(authorName) · \(sourceName)"
    }

    private func eventPriceText(for event: Event) -> String {
        guard event.price > 0 else {
            return AppStrings.Events.freePrice
        }

        if event.price.rounded(.down) == event.price {
            return "€\(Int(event.price))"
        }

        return "€\(String(format: "%.2f", event.price))"
    }

    private var eventViewTaskID: String {
        "\(eventID)-\(authState.user?.id ?? "guest")"
    }

    private func eventViewCountText(for event: Event) -> String {
        AppStrings.Events.viewCount(event.viewCount)
    }

    private func canManageEvent(_ event: Event) -> Bool {
        PermissionService.canEditEvent(event, user: authState.user)
    }

    private func eventLocationText(for event: Event) -> String {
        let venue = event.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty {
            return venue
        }

        let city = event.city.trimmingCharacters(in: .whitespacesAndNewlines)
        if !city.isEmpty {
            return city
        }

        return event.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func deduplicatedLocationLines(for event: Event) -> (title: String, subtitle: String?, city: String?) {
        let venue = event.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = event.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let city = event.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = firstNonEmpty([venue, address, city], fallback: AppStrings.Events.locationSectionTitle)
        let subtitle = address.isEmpty || isLocationText(address, duplicateOf: title) ? nil : address
        let cityLine = city.isEmpty
            || isLocationText(city, duplicateOf: title)
            || subtitle.map { isLocationText(city, duplicateOf: $0) } == true
            ? nil
            : city
        return (title, subtitle, cityLine)
    }

    private func firstNonEmpty(_ values: [String], fallback: String) -> String {
        values.first { !$0.isEmpty } ?? fallback
    }

    private func isLocationText(_ value: String, duplicateOf otherValue: String) -> Bool {
        let left = normalizedLocationText(value)
        let right = normalizedLocationText(otherValue)
        guard left.count > 3, right.count > 3 else {
            return left == right
        }

        return left == right || left.contains(right) || right.contains(left)
    }

    private func normalizedLocationText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: LocalizationStore.locale)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func eventCoordinate(for event: Event) -> CLLocationCoordinate2D? {
        guard let latitude = event.latitude, let longitude = event.longitude else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func canOpenEventInMaps(_ event: Event) -> Bool {
        eventCoordinate(for: event) != nil || !eventLocationText(for: event).isEmpty
    }

    private func openEventInMaps(_ event: Event) {
        let url: URL?
        if let coordinate = eventCoordinate(for: event) {
            let query = eventLocationText(for: event).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            url = URL(string: "http://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(query)")
        } else {
            let query = eventLocationText(for: event).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            url = URL(string: "http://maps.apple.com/?q=\(query)")
        }

        guard let url else { return }
        UIApplication.shared.open(url)
    }
}

private struct EventSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]

    init(event: Event) {
        items = [
            event.title,
            event.summary,
            eventScheduleText(for: event),
            [event.venue, event.city].filter { !$0.isEmpty }.joined(separator: ", ")
        ].filter { !$0.isEmpty }
    }
}

private struct EventShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct EventCalendarAlert {
    let title: String
    let message: String

    static let added = EventCalendarAlert(
        title: AppStrings.Events.calendarAddedTitle,
        message: AppStrings.Events.calendarAddedMessage
    )

    static let alreadyAdded = EventCalendarAlert(
        title: AppStrings.Events.calendarAlreadyAddedTitle,
        message: AppStrings.Events.calendarAlreadyAddedMessage
    )

    static let permissionDenied = EventCalendarAlert(
        title: AppStrings.Events.calendarPermissionTitle,
        message: AppStrings.Events.calendarPermissionMessage
    )

    static let failed = EventCalendarAlert(
        title: AppStrings.Events.calendarErrorTitle,
        message: AppStrings.Events.calendarErrorMessage
    )
}

@MainActor
private final class EventCalendarWriter {
    enum CalendarError: Error {
        case accessDenied
        case missingCalendar
    }

    private let eventStore = EKEventStore()

    func add(_ appEvent: Event) async throws {
        try await requestAccessIfNeeded()

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarError.missingCalendar
        }

        let calendarEvent = EKEvent(eventStore: eventStore)
        calendarEvent.title = appEvent.title
        calendarEvent.startDate = appEvent.startDate
        calendarEvent.endDate = appEvent.endDate
        calendarEvent.isAllDay = appEvent.isAllDay
        calendarEvent.location = joinedLocation(for: appEvent)
        calendarEvent.notes = [appEvent.summary, appEvent.details]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        calendarEvent.calendar = calendar

        try eventStore.save(calendarEvent, span: .thisEvent, commit: true)
    }

    private func joinedLocation(for event: Event) -> String {
        [event.venue, event.address ?? "", event.city]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func requestAccessIfNeeded() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)

        if #available(iOS 17.0, *) {
            switch status {
            case .fullAccess, .writeOnly:
                return
            case .notDetermined:
                let granted = try await eventStore.requestWriteOnlyAccessToEvents()
                guard granted else { throw CalendarError.accessDenied }
            default:
                throw CalendarError.accessDenied
            }
        } else {
            switch status {
            case .authorized:
                return
            case .notDetermined:
                let granted = try await eventStore.requestAccess(to: .event)
                guard granted else { throw CalendarError.accessDenied }
            default:
                throw CalendarError.accessDenied
            }
        }
    }
}

private struct EventSimilarCard: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL = event.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty {
                RemoteImageView(
                    imageURL: imageURL,
                    height: 98,
                    cornerRadius: 14,
                    source: "EventSimilarCard",
                    placeholderStyle: .glassSkeleton
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                AppInfoChip(
                    title: AppStrings.Events.title.uppercased(),
                    systemImage: "calendar",
                    tint: Color.purple,
                    fill: AppTheme.badgePurpleFill,
                    size: .small
                )

                Text(event.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                Text(LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .short))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(10)
        }
        .frame(width: 166, alignment: .leading)
        .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}

private struct EventDetailRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: systemImage)
                .font(AppTheme.detailMetadataIconFont)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.sectionSpacing, height: AppTheme.sectionSpacing)

            Text(title)
                .font(AppTheme.detailMetadataFont)
                .foregroundStyle(AppTheme.textSecondary)

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            Text(value)
                .font(AppTheme.detailMetadataFont.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity)
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
