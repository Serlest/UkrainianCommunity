import EventKit
import MapKit
import SwiftUI
import UIKit

enum EventRegistrationConfirmation: Equatable {
    case register(String)
    case cancel(String)

    var eventID: String {
        switch self {
        case .register(let eventID), .cancel(let eventID):
            eventID
        }
    }

    var isCancellation: Bool {
        if case .cancel = self {
            return true
        }
        return false
    }
}

struct EventDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var analyticsScenePhase
    @Environment(\.eventPresentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.contentReportPresentation) var contentReportPresentation
    @Environment(\.userBlockingPresentation) var userBlockingPresentation
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    let eventID: String
    let onEventDeleted: @MainActor @Sendable () -> Void
    let onNavigateBack: (() -> Void)?
    let analyticsSourceScreen: String
    let organizationRepository: OrganizationRepository
    @State private var refreshError: AppError?
    @State var showDeleteConfirmation = false
    @State var deleteErrorMessage: String?
    @State var isDeleting = false
    @State var isShowingEditSheet = false
    @State var pendingRemovalEventID: String?
    @State var guestAccessAction: GuestAccessAction?
    @State var calendarAlert: EventCalendarAlert?
    @State var calendarEventIDs = Set<String>()
    @State var isAddingToCalendar = false
    @State var recordedViewKeys = Set<String>()
    @State var pendingCommentDeleteID: String?
    @State var commentDeleteErrorMessage: String?
    @State var permissionOrganization: Organization?
    @State var pendingRegistrationConfirmation: EventRegistrationConfirmation?
    @State var eventRegistrationAttendees: [EventRegistrationAttendee] = []
    @State var isLoadingEventRegistrationAttendees = false
    @State var eventRegistrationAttendeesErrorMessage: String?
    @State var loadedEventRegistrationAttendeesEventID: String?
    @State var isShowingRegistrationManagement = false
    @State var eventRecommendations: [EventContentRecommendation] = []
    @FocusState var isCommentFieldFocused: Bool
    let calendarWriter = EventCalendarWriter()
    let commentsSectionID = "eventCommentsSection"
    let detailImageHeight: CGFloat = 220
    let detailSectionSpacing: CGFloat = AppTheme.detailSectionSpacing

    init(
        viewModel: EventsViewModel,
        eventID: String,
        onEventDeleted: @escaping @MainActor @Sendable () -> Void,
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        onNavigateBack: (() -> Void)? = nil,
        analyticsSourceScreen: String = "event_detail"
    ) {
        self.viewModel = viewModel
        self.eventID = eventID
        self.onEventDeleted = onEventDeleted
        self.onNavigateBack = onNavigateBack
        self.analyticsSourceScreen = analyticsSourceScreen
        self.organizationRepository = organizationRepository
    }

    func canEditEvent(_ event: Event) -> Bool {
        if let organizationID = event.source.organizationId,
           let organization = organizationForPermissions(organizationID: organizationID) {
            return PermissionService.canEditOrganizationEvent(organization, user: authState.user)
        }
        return PermissionService.canEditEvent(event, user: authState.user)
    }

    func canDeleteEvent(_ event: Event) -> Bool {
        if let organizationID = event.source.organizationId,
           let organization = organizationForPermissions(organizationID: organizationID) {
            return PermissionService.canDeleteOrganizationContent(organization, user: authState.user)
        }
        return PermissionService.canDeleteEvent(event, user: authState.user)
    }

    @ViewBuilder
    var editSheetContent: some View {
        if let event = viewModel.event(for: eventID) {
            NavigationStack {
                EventEditorView(repository: viewModel.editorRepository, event: event) { _ in
                    await viewModel.refresh()
                    return true
                }
            }
        }
    }

    @ViewBuilder
    var registrationManagementSheetContent: some View {
        if let event = viewModel.event(for: eventID) {
            EventRegistrationManagementView(
                event: event,
                attendees: eventRegistrationAttendees,
                isLoading: isLoadingEventRegistrationAttendees,
                errorMessage: eventRegistrationAttendeesErrorMessage
            ) {
                await loadEventRegistrationAttendeesIfNeeded(for: event, force: true)
            }
        }
    }

    var body: some View {
        Group {
            if let event = viewModel.event(for: eventID) {
                DetailScreenShell(
                    contentSpacing: detailSectionSpacing,
                    backAction: navigateBack,
                    refreshAction: refreshEventDetail
                ) {
                    eventHeaderActions(for: event)
                } scrollContent: { scrollProxy in
                    if let refreshError {
                        InlineMessageCard(style: .error, message: readableEventErrorText(refreshError))
                    }
                    articleHeader(for: event)
                        .onTapGesture { isCommentFieldFocused = false }

                    if event.isCancelled {
                        cancelledEventNotice(for: event)
                            .onTapGesture { isCommentFieldFocused = false }
                    }

                    heroImageSection(for: event)
                        .onTapGesture { isCommentFieldFocused = false }

                    if !event.localizedSummary.isEmpty {
                        leadBlock(for: event)
                            .onTapGesture { isCommentFieldFocused = false }
                    }

                    eventScheduleCard(for: event)
                        .onTapGesture { isCommentFieldFocused = false }

                    if !event.isCancelled {
                        primaryActionsCard(for: event)
                            .onTapGesture { isCommentFieldFocused = false }
                    }

                    eventRegistrationManagementCard(for: event)
                        .onTapGesture { isCommentFieldFocused = false }

                    aboutCard(for: event)
                        .onTapGesture { isCommentFieldFocused = false }

                    eventTagsCard(for: event)
                        .onTapGesture { isCommentFieldFocused = false }

                    organizerCard(for: event)
                        .onTapGesture { isCommentFieldFocused = false }

                    eventContactCard(for: event)

                    locationCard(for: event)
                        .onTapGesture { isCommentFieldFocused = false }

                    detailsCard(for: event)
                        .onTapGesture { isCommentFieldFocused = false }

                    similarEventsSection(for: event)
                        .onTapGesture { isCommentFieldFocused = false }

                    engagementCard(for: event, scrollProxy: scrollProxy)

                    commentsCard(for: event)
                        .id(commentsSectionID)
                }
            } else {
                ZStack {
                    AppBackgroundView()
                        .allowsHitTesting(false)

                    EmptyStateView(title: AppStrings.Common.noItems)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .appDestructiveActionDialog(Binding(
            get: {
                guard showDeleteConfirmation,
                      let event = viewModel.event(for: eventID) else { return nil }
                return AppDestructiveActionDialog(
                    title: eventDestructiveActionConfirmationTitle(for: event),
                    message: eventDestructiveActionConfirmationMessage(for: event),
                    destructiveActionTitle: eventDestructiveActionTitle(for: event),
                    cancelTitle: AppStrings.Events.cancel
                ) {
                    Task {
                        await deleteCurrentEvent()
                    }
                }
            },
            set: { if $0 == nil { showDeleteConfirmation = false } }
        ))
        .confirmationDialog(eventRegistrationConfirmationTitle, isPresented: Binding(
            get: { pendingRegistrationConfirmation != nil },
            set: { if !$0 { pendingRegistrationConfirmation = nil } }
        ), titleVisibility: .visible) {
            Button(eventRegistrationConfirmationButton, role: pendingRegistrationConfirmation?.isCancellation == true ? .destructive : nil) {
                confirmPendingRegistrationChange()
            }
            Button(AppStrings.Events.cancel, role: .cancel) {
                pendingRegistrationConfirmation = nil
            }
        } message: {
            Text(eventRegistrationConfirmationMessage)
        }
        .appDestructiveActionDialog(Binding(
            get: {
                guard let commentID = pendingCommentDeleteID else { return nil }
                return AppDestructiveActionDialog(
                    title: AppStrings.Common.deleteCommentConfirmation,
                    message: "",
                    destructiveActionTitle: AppStrings.Action.delete,
                    cancelTitle: AppStrings.Events.cancel
                ) {
                    Task {
                        await deleteComment(commentID: commentID)
                    }
                }
            },
            set: { if $0 == nil { pendingCommentDeleteID = nil } }
        ))
        .appErrorDialog(Binding(
            get: {
                deleteErrorMessage.map {
                    AppErrorDialog(
                        title: viewModel.event(for: eventID).map(eventDestructiveActionFailedTitle(for:)) ?? AppStrings.Events.deleteFailed,
                        message: $0,
                        okTitle: AppStrings.Events.dismissError
                    )
                }
            },
            set: { if $0 == nil { deleteErrorMessage = nil } }
        ))
        .appErrorDialog(Binding(
            get: {
                commentDeleteErrorMessage.map {
                    AppErrorDialog(
                        title: AppStrings.Common.deleteCommentFailed,
                        message: $0,
                        okTitle: AppStrings.Events.dismissError
                    )
                }
            },
            set: { if $0 == nil { commentDeleteErrorMessage = nil } }
        ))
        .appErrorDialog(Binding(
            get: {
                guard let registrationError = viewModel.registrationError,
                      registrationError.eventID == eventID else { return nil }
                return AppErrorDialog(
                    title: AppStrings.Events.registrationErrorTitle,
                    message: readableEventRegistrationErrorText(registrationError.reason),
                    okTitle: AppStrings.Events.dismissError
                )
            },
            set: { if $0 == nil { viewModel.dismissRegistrationError(for: eventID) } }
        ))
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
        .sheet(isPresented: $isShowingRegistrationManagement) {
            registrationManagementSheetContent
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
        .task(id: analyticsScenePhase == .active && viewModel.event(for: eventID)?.isCancelled == false
              ? viewModel.event(for: eventID)?.id : nil) {
            guard analyticsScenePhase == .active,
                  let event = viewModel.event(for: eventID), !event.isCancelled else { return }
            await viewModel.trackViewWhileVisible(for: event, sourceScreen: analyticsSourceScreen)
        }
        .task {
            if viewModel.event(for: eventID) == nil {
                await viewModel.loadEventIfNeeded(eventID: eventID)
            }
            guard let event = viewModel.event(for: eventID) else { return }
            await loadPermissionOrganizationIfNeeded(organizationID: event.source.organizationId)
            await loadEventRegistrationAttendeesIfNeeded(for: event)
            await viewModel.loadRecommendationCandidates()
            refreshEventRecommendations()
            guard !event.isCancelled else { return }
            await viewModel.loadComments(for: eventID)
            guard !recordedViewKeys.contains(eventViewTaskID) else { return }
            recordedViewKeys.insert(eventViewTaskID)
            viewModel.recordView(for: eventID)
            RecentViewRecorder.recordEvent(event)
        }
        .onChange(of: authState.user?.id) { _, _ in
            eventRegistrationAttendees = []
            loadedEventRegistrationAttendeesEventID = nil
            guard let event = viewModel.event(for: eventID) else { return }
            Task {
                await loadPermissionOrganizationIfNeeded(organizationID: event.source.organizationId)
                await loadEventRegistrationAttendeesIfNeeded(for: event, force: true)
            }
            guard !recordedViewKeys.contains(eventViewTaskID) else { return }
            recordedViewKeys.insert(eventViewTaskID)
            viewModel.recordView(for: eventID)
            RecentViewRecorder.recordEvent(event)
        }
        .onChange(of: viewModel.contentVersion) { _, _ in
            refreshEventRecommendations()
        }
        .onDisappear {
            viewModel.stopListeningComments(for: eventID)
            guard let pendingRemovalEventID else { return }
            withTransaction(Transaction(animation: nil)) {
                viewModel.removeDeletedEvent(id: pendingRemovalEventID)
            }
            self.pendingRemovalEventID = nil
        }
    }

    func refreshEventRecommendations() {
        guard let event = viewModel.event(for: eventID) else {
            eventRecommendations = []
            return
        }
        eventRecommendations = ContentRecommendationEngine.eventRecommendations(
            for: event,
            candidates: viewModel.events
        )
    }

    func refreshEventDetail() async {
        refreshError = nil
        guard await viewModel.loadEventIfNeeded(eventID: eventID, force: true) else {
            refreshError = viewModel.error
            return
        }
        guard let event = viewModel.event(for: eventID) else { return }
        await loadPermissionOrganizationIfNeeded(organizationID: event.source.organizationId)
        await loadEventRegistrationAttendeesIfNeeded(for: event, force: true)
        guard !event.isCancelled else { return }
        await viewModel.loadComments(for: eventID, forceRefresh: true)
    }

    var eventRegistrationConfirmationTitle: String {
        guard let pendingRegistrationConfirmation else {
            return AppStrings.Events.confirmRegisterTitle
        }
        return pendingRegistrationConfirmation.isCancellation
        ? AppStrings.Events.confirmCancelRegistrationTitle
        : AppStrings.Events.confirmRegisterTitle
    }

    var eventRegistrationConfirmationButton: String {
        guard let pendingRegistrationConfirmation else {
            return AppStrings.Events.confirmRegisterButton
        }
        return pendingRegistrationConfirmation.isCancellation
        ? AppStrings.Events.confirmCancelRegistrationButton
        : AppStrings.Events.confirmRegisterButton
    }

    var eventRegistrationConfirmationMessage: String {
        guard let pendingRegistrationConfirmation,
              let event = viewModel.event(for: pendingRegistrationConfirmation.eventID) else {
            return ""
        }
        return pendingRegistrationConfirmation.isCancellation
        ? AppStrings.Events.confirmCancelRegistrationMessage(event.localizedTitle)
        : AppStrings.Events.confirmRegisterMessage(event.localizedTitle)
    }

    func confirmPendingRegistrationChange() {
        guard let pendingRegistrationConfirmation else { return }
        viewModel.toggleRegistration(for: pendingRegistrationConfirmation.eventID)
        loadedEventRegistrationAttendeesEventID = nil
        Task {
            await viewModel.waitForRegistrationMutation(for: pendingRegistrationConfirmation.eventID)
            guard let event = viewModel.event(for: pendingRegistrationConfirmation.eventID) else { return }
            await loadEventRegistrationAttendeesIfNeeded(for: event, force: true)
        }
        self.pendingRegistrationConfirmation = nil
    }

    @MainActor
    func deleteCurrentEvent() async {
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

    func organizationForPermissions(organizationID: String) -> Organization? {
        guard permissionOrganization?.id == organizationID else { return nil }
        return permissionOrganization
    }

    @MainActor
    func loadPermissionOrganizationIfNeeded(organizationID: String?) async {
        guard let organizationID else {
            permissionOrganization = nil
            return
        }
        guard permissionOrganization?.id != organizationID else { return }

        do {
            permissionOrganization = try await RefreshRequest.run { [self] in try await organizationRepository.fetchOrganization(id: organizationID) }
        } catch {
            permissionOrganization = nil
        }
    }

    @MainActor
    func deleteComment(commentID: String) async {
        pendingCommentDeleteID = nil
        if case .failure(let error) = await viewModel.deleteComment(eventID: eventID, commentID: commentID) {
            commentDeleteErrorMessage = readableEventErrorText(error)
        }
    }

    func addToCalendar(_ event: Event) {
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

    func detailGlassCard<Content: View>(padding: CGFloat = AppTheme.detailCardPadding, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(
            cornerRadius: AppTheme.cardRadius,
            material: .ultraThinMaterial,
            surface: AppTheme.glassSurface(for: colorScheme),
            borderOpacity: 0.62,
            shadowRadius: 8,
            shadowY: 4
        )
    }

    func eventParticipantsText(for event: Event) -> String {
        if let capacity = event.capacity {
            "\(event.registeredCount) / \(capacity)"
        } else {
            "\(event.registeredCount)"
        }
    }

    func eventSourceName(for event: Event) -> String {
        let organizationName = event.source.displayOrganizationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return organizationName.isEmpty ? AppStrings.Home.brandTitle : organizationName
    }

    func eventPublisherText(for event: Event) -> String {
        let sourceName = eventSourceName(for: event)
        let authorName = event.authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !authorName.isEmpty else {
            return sourceName
        }

        return "\(authorName) · \(sourceName)"
    }

    func eventPriceText(for event: Event) -> String {
        let amount: (Double) -> String = { value in
            value.rounded(.down) == value ? "€\(Int(value))" : "€\(String(format: "%.2f", value))"
        }
        switch event.pricing.kind {
        case .unspecified: return ContentPublishingStrings.priceUnspecified
        case .free: return AppStrings.Events.freePrice
        case .exact: return event.pricing.amount.map(amount) ?? ContentPublishingStrings.priceUnspecified
        case .startingFrom: return event.pricing.amount.map { "\(ContentPublishingStrings.priceFrom) \(amount($0))" } ?? ContentPublishingStrings.priceUnspecified
        case .range:
            guard let minimum = event.pricing.amount, let maximum = event.pricing.maximumAmount else { return ContentPublishingStrings.priceUnspecified }
            return "\(amount(minimum))–\(amount(maximum))"
        }
    }

    var eventViewTaskID: String {
        "\(eventID)-\(authState.user?.id ?? "guest")"
    }

    func eventViewCountText(for event: Event) -> String {
        AppStrings.Events.viewCount(event.viewCount)
    }

    func canManageEvent(_ event: Event) -> Bool {
        PermissionService.canEditEvent(event, user: authState.user)
    }

    func canManageEventRegistrations(_ event: Event) -> Bool {
        canEditEvent(event)
    }

    @MainActor
    func loadEventRegistrationAttendeesIfNeeded(for event: Event, force: Bool = false) async {
        guard event.requiresRegistration || event.registeredCount > 0 else {
            eventRegistrationAttendees = []
            eventRegistrationAttendeesErrorMessage = nil
            loadedEventRegistrationAttendeesEventID = nil
            return
        }
        guard canManageEventRegistrations(event) else { return }
        guard force || loadedEventRegistrationAttendeesEventID != event.id else { return }
        guard !isLoadingEventRegistrationAttendees else { return }

        isLoadingEventRegistrationAttendees = true
        eventRegistrationAttendeesErrorMessage = nil
        defer { isLoadingEventRegistrationAttendees = false }

        do {
            eventRegistrationAttendees = try await RefreshRequest.run { [self] in try await viewModel.editorRepository.fetchEventRegistrations(eventID: event.id) }
            loadedEventRegistrationAttendeesEventID = event.id
        } catch let appError as AppError {
            eventRegistrationAttendeesErrorMessage = readableEventErrorText(appError)
        } catch {
            eventRegistrationAttendeesErrorMessage = readableEventErrorText(.unknown)
        }
    }

    func eventLocationText(for event: Event) -> String {
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

    func deduplicatedLocationLines(for event: Event) -> (title: String, subtitle: String?, city: String?) {
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

    func firstNonEmpty(_ values: [String], fallback: String) -> String {
        values.first { !$0.isEmpty } ?? fallback
    }

    func isLocationText(_ value: String, duplicateOf otherValue: String) -> Bool {
        let left = normalizedLocationText(value)
        let right = normalizedLocationText(otherValue)
        guard left.count > 3, right.count > 3 else {
            return left == right
        }

        return left == right || left.contains(right) || right.contains(left)
    }

    func normalizedLocationText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: LocalizationStore.locale)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(separator: " ")
            .joined(separator: " ")
    }

    func eventCoordinate(for event: Event) -> CLLocationCoordinate2D? {
        guard let latitude = event.latitude, let longitude = event.longitude else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func canOpenEventInMaps(_ event: Event) -> Bool {
        eventCoordinate(for: event) != nil || !eventLocationText(for: event).isEmpty
    }

    func openEventInMaps(_ event: Event) {
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

func readableEventRegistrationErrorText(_ error: EventRegistrationMutationError) -> String {
    switch error {
    case .full:
        AppStrings.Events.registrationFullError
    case .registrationNotRequired:
        AppStrings.Events.registrationNotRequiredError
    case .eventCancelled:
        AppStrings.Events.registrationCancelledError
    case .eventPast:
        AppStrings.Events.registrationPastError
    case .permissionDenied:
        AppStrings.Events.registrationPermissionError
    case .network:
        AppStrings.Events.registrationNetworkError
    case .notFound:
        AppStrings.Events.registrationNotFoundError
    case .unavailable:
        AppStrings.Events.registrationUnavailableError
    }
}

func eventUsesCancellationWording(_ event: Event) -> Bool {
    event.moderationStatus == .approved || event.registeredCount > 0
}

func eventDestructiveActionTitle(for event: Event) -> String {
    eventUsesCancellationWording(event) ? AppStrings.Events.cancelEvent : AppStrings.Events.delete
}

func eventDestructiveActionConfirmationTitle(for event: Event) -> String {
    eventUsesCancellationWording(event) ? AppStrings.Events.cancelEventConfirmation : AppStrings.Events.deleteConfirmation
}

func eventDestructiveActionConfirmationMessage(for event: Event) -> String {
    eventUsesCancellationWording(event) ? AppStrings.Events.cancelEventConfirmationMessage : ""
}

func eventDestructiveActionFailedTitle(for event: Event) -> String {
    eventUsesCancellationWording(event) ? AppStrings.Events.cancelEventFailed : AppStrings.Events.deleteFailed
}

struct EventCalendarAlert {
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
final class EventCalendarWriter {
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

        let now = Date()
        let futureOccurrences = appEvent.occurrences.filter {
            $0.status == .scheduled && $0.endDate >= now
        }
        let occurrences = futureOccurrences.isEmpty
            ? [EventOccurrence(startDate: appEvent.startDate, endDate: appEvent.endDate, isAllDay: appEvent.isAllDay)]
            : futureOccurrences

        for occurrence in occurrences {
            let calendarEvent = EKEvent(eventStore: eventStore)
            calendarEvent.title = appEvent.localizedTitle
            calendarEvent.startDate = occurrence.startDate
            calendarEvent.endDate = occurrence.endDate
            calendarEvent.isAllDay = occurrence.isAllDay
            calendarEvent.location = joinedLocation(for: appEvent)
            calendarEvent.notes = [appEvent.localizedSummary, appEvent.localizedDetails, appEvent.externalAction?.url]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            calendarEvent.calendar = calendar
            try eventStore.save(calendarEvent, span: .thisEvent, commit: false)
        }
        try eventStore.commit()
    }

    func joinedLocation(for event: Event) -> String {
        [event.venue, event.address ?? "", event.city]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    func requestAccessIfNeeded() async throws {
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
