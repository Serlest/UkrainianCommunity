import SwiftUI

extension EventDetailView {
        func cancelledEventNotice(for event: Event) -> some View {
            DetailCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accentDestructiveForeground)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppStrings.Events.cancelledNoticeTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(event.cancellationReason ?? AppStrings.Events.cancelledNoticeBody)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
            }
        }

        func eventScheduleCard(for event: Event) -> some View {
            DetailCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppStrings.Events.detailsSectionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)

                    EventDetailRow(systemImage: "calendar", title: AppStrings.Events.fieldStartDate, value: LocalizationStore.dateString(from: event.startDate, dateStyle: .full, timeStyle: .none))
                    EventDetailRow(systemImage: "clock", title: AppStrings.Events.startTime, value: LocalizationStore.timeRangeString(startDate: event.startDate, endDate: event.endDate))

                    if Calendar.current.startOfDay(for: event.endDate) != Calendar.current.startOfDay(for: event.startDate) {
                        EventDetailRow(systemImage: "calendar.badge.clock", title: AppStrings.Events.fieldEndDate, value: LocalizationStore.dateString(from: event.endDate, dateStyle: .full, timeStyle: .short))
                    }
                }
            }
        }

        func primaryActionsCard(for event: Event) -> some View {
            detailGlassCard(padding: 9) {
                VStack(spacing: 8) {
                    if !event.requiresRegistration {
                        registrationNotRequiredLine
                    }

                    HStack(spacing: 12) {
                        if event.requiresRegistration {
                            registrationButton(for: event)
                                .frame(maxWidth: .infinity)
                        }

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
        }

        var registrationNotRequiredLine: some View {
            Label(AppStrings.Events.registrationNotRequired, systemImage: "checkmark.seal")
                .font(AppTheme.metadataStrongFont)
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder
        func eventRegistrationManagementCard(for event: Event) -> some View {
            if (event.requiresRegistration || event.registeredCount > 0) && canManageEventRegistrations(event) {
                DetailCard {
                    VStack(alignment: .leading, spacing: AppTheme.detailInnerSpacing) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(AppStrings.Events.registrationManagementTitle)
                                .font(AppTheme.sectionTitleFont)
                                .foregroundStyle(AppTheme.textPrimary)

                            Spacer()

                            Text("\(resolvedRegistrationAttendeeCount(for: event))")
                                .font(AppTheme.badgeFont)
                                .foregroundStyle(AppTheme.accentPrimaryForeground)
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.accentPrimarySoft, in: Capsule())
                        }

                        registrationCapacitySummary(for: event)

                        if isLoadingEventRegistrationAttendees && eventRegistrationAttendees.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AppTheme.accentPrimary)

                                Text(AppStrings.Events.registrationManagementLoading)
                                    .font(AppTheme.metadataFont)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let eventRegistrationAttendeesErrorMessage {
                            Text(eventRegistrationAttendeesErrorMessage)
                                .font(AppTheme.metadataFont)
                                .foregroundStyle(AppTheme.accentDestructiveForeground)
                        } else if eventRegistrationAttendees.isEmpty {
                            Text(AppStrings.Events.registrationManagementEmpty)
                                .font(AppTheme.secondaryBodyFont)
                                .foregroundStyle(AppTheme.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(eventRegistrationAttendees.prefix(3)) { attendee in
                                    eventRegistrationAttendeeRow(attendee)
                                }

                                Button {
                                    isShowingRegistrationManagement = true
                                } label: {
                                    Label(AppStrings.Common.viewAll, systemImage: "person.3")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }
                        }
                    }
                }
                .task(id: event.id) {
                    await loadEventRegistrationAttendeesIfNeeded(for: event)
                }
            }
        }

        @ViewBuilder
        func registrationCapacitySummary(for event: Event) -> some View {
            if let capacity = event.capacity {
                let registeredCount = resolvedRegistrationAttendeeCount(for: event)
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(min(registeredCount, capacity)), total: Double(max(capacity, 1)))
                        .tint(registeredCount >= capacity ? AppTheme.accentDestructive : AppTheme.accentPrimary)

                    Text(AppStrings.Events.registrationCapacity(registeredCount, capacity))
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                }
            }
        }

        func resolvedRegistrationAttendeeCount(for event: Event) -> Int {
            if loadedEventRegistrationAttendeesEventID == event.id {
                return eventRegistrationAttendees.count
            }
            return event.registeredCount
        }

        func eventRegistrationAttendeeRow(_ attendee: EventRegistrationAttendee) -> some View {
            HStack(alignment: .center, spacing: 10) {
                AvatarArtworkView(
                    avatarURL: attendee.avatarURL,
                    initials: attendee.initials,
                    size: 32,
                    showsBorder: false,
                    shadowOpacity: 0,
                    shadowRadius: 0,
                    shadowY: 0,
                    initialsFont: AppTheme.badgeFont,
                    placeholderFill: AppTheme.accentPrimarySoft
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(attendee.displayTitle)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(registrationAttendeeSubtitle(attendee))
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .padding(.vertical, 4)
        }

        func registrationAttendeeSubtitle(_ attendee: EventRegistrationAttendee) -> String {
            if let registeredAt = attendee.registeredAt {
                return LocalizationStore.dateString(from: registeredAt, dateStyle: .medium, timeStyle: .short)
            }
            return attendee.displaySubtitle
        }

        func eventActionButton(title: String, systemImage: String, isDisabled: Bool = false, action: @escaping () -> Void = {}) -> some View {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.eventsMetadataSpacing)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.minimumInteractiveTarget)
                    .appGlassActionSurface(.regular)
            }
            .buttonStyle(AppPressFeedbackButtonStyle())
            .frame(minHeight: AppTheme.minimumInteractiveTarget)
            .contentShape(Rectangle())
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.68 : 1)
        }

        func engagementCard(for event: Event, scrollProxy: ScrollViewProxy) -> some View {
            detailGlassCard(padding: 9) {
                DetailActionRow {
                    HStack(spacing: 12) {
                        eventMetricButton(
                            systemImage: event.likeState.isLiked ? "heart.fill" : "heart",
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
                    }
                } trailingContent: {
                    publisherLine(for: event)
                }
            }
        }

        func focusEventComments(using scrollProxy: ScrollViewProxy) {
            let scrollAction = {
                scrollProxy.scrollTo(commentsSectionID, anchor: .top)
            }

            if reduceMotion {
                scrollAction()
            } else {
                withAnimation(.easeInOut(duration: 0.32), scrollAction)
            }

            Task { @MainActor in
                if !reduceMotion {
                    try? await Task.sleep(nanoseconds: 260_000_000)
                }
                isCommentFieldFocused = true
            }
        }

        func eventMetricButton(
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
                        .foregroundStyle(isSelected ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground)

                    Text("\(count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                }
                .frame(minWidth: 74, minHeight: AppTheme.minimumInteractiveTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(AppPressFeedbackButtonStyle())
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(count)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        func publisherLine(for event: Event) -> some View {
            Label(eventPublisherText(for: event), systemImage: "person.crop.circle")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 190, alignment: .trailing)
                .accessibilityLabel(eventPublisherText(for: event))
        }

        func registrationButton(for event: Event) -> some View {
            Button {
                guard authState.isAuthenticated else {
                    guestAccessAction = .registration
                    return
                }

                pendingRegistrationConfirmation = event.registrationState == .registered
                ? .cancel(event.id)
                : .register(event.id)
            } label: {
                Label(event.registrationState == .registered ? AppStrings.Action.cancelRegistration : AppStrings.Events.register, systemImage: event.registrationState == .registered ? "xmark.circle" : "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.eventsMetadataSpacing)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.minimumInteractiveTarget)
                    .background(AppTheme.accentPrimary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(minHeight: AppTheme.minimumInteractiveTarget)
            .contentShape(Rectangle())
            .disabled(viewModel.pendingEventRegistrationIDs.contains(event.id))
            .accessibilityIdentifier("event.register.\(event.id)")
            .accessibilityLabel(event.registrationState == .registered ? AppStrings.Action.cancelRegistration : AppStrings.Action.register)
            .accessibilityHint(AppStrings.Events.title)
        }

        func handleBookmark(for event: Event) {
            guard authState.isAuthenticated else {
                guestAccessAction = .bookmarks
                return
            }

            viewModel.toggleBookmark(for: event.id)
        }

        func handleLike(for event: Event) {
            guard authState.isAuthenticated else {
                guestAccessAction = .likes
                return
            }

            viewModel.toggleLike(for: event.id)
        }
}

struct EventRegistrationManagementView: View {
    @Environment(\.dismiss) private var dismiss
    let event: Event
    let attendees: [EventRegistrationAttendee]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: @MainActor () async -> Void

    @State private var searchText = ""
    @State private var sortOption = AppListSortOption.oldest

    private var visibleAttendees: [EventRegistrationAttendee] {
        attendees
            .filter { attendee in
                LocalSearchMatcher.matches(
                    query: searchText,
                    values: [attendee.displayTitle, attendee.displaySubtitle]
                )
            }
            .sorted { lhs, rhs in
                switch sortOption {
                case .newest:
                    (lhs.registeredAt ?? .distantPast) > (rhs.registeredAt ?? .distantPast)
                case .oldest:
                    (lhs.registeredAt ?? .distantFuture) < (rhs.registeredAt ?? .distantFuture)
                case .nameAscending:
                    LocalizationStore.compareForSorting(lhs.displayTitle, rhs.displayTitle) == .orderedAscending
                case .nameDescending:
                    LocalizationStore.compareForSorting(lhs.displayTitle, rhs.displayTitle) == .orderedDescending
                case .popular:
                    lhs.userID < rhs.userID
                }
            }
    }

    var body: some View {
        NavigationStack {
            EditorScreenShell(
                title: AppStrings.Events.registrationManagementTitle,
                subtitle: event.title,
                closeStyle: .cancel,
                closeAction: { dismiss() }
            ) {
                summaryCard
                searchAndSortCard
                attendeesContent
            }
            .refreshable {
                await onRefresh()
            }
        }
        .presentationDragIndicator(.visible)
        .task {
            if attendees.isEmpty {
                await onRefresh()
            }
        }
    }

    private var summaryCard: some View {
        AppEditorSectionCard {
            HStack(spacing: AppTheme.dashboardSpacing) {
                Label("\(attendees.count)", systemImage: "person.3.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .monospacedDigit()

                Spacer(minLength: 8)

                if let capacity = event.capacity {
                    Text(AppStrings.Events.registrationCapacity(attendees.count, capacity))
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var searchAndSortCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.textSecondary)

                    TextField(AppStrings.Events.registrationSearchPlaceholder, text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        AppSearchClearButton { searchText = "" }
                    }
                }
                .padding(.horizontal, AppTheme.inputHorizontalPadding)
                .frame(minHeight: AppTheme.searchControlHeight)
                .background(AppTheme.surfaceControl, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous).strokeBorder(AppTheme.borderSubtle))

                AppSortMenu(
                    selection: $sortOption,
                    options: [.oldest, .newest, .nameAscending, .nameDescending]
                )
            }
        }
    }

    @ViewBuilder
    private var attendeesContent: some View {
        if isLoading && attendees.isEmpty {
            LoadingStateCard(title: AppStrings.Events.registrationManagementLoading)
        } else if let errorMessage, attendees.isEmpty {
            InlineMessageCard(style: .error, message: errorMessage)
        } else if visibleAttendees.isEmpty {
            EmptyStateCard(
                systemImage: searchText.isEmpty ? "person.3" : "magnifyingglass",
                title: searchText.isEmpty ? AppStrings.Events.registrationManagementEmpty : AppStrings.Search.noResultsTitle,
                message: searchText.isEmpty ? "" : AppStrings.Search.noResultsMessage
            )
        } else {
            LazyVStack(spacing: AppTheme.eventsMetadataSpacing) {
                ForEach(visibleAttendees) { attendee in
                    AppEditorSectionCard {
                        attendeeRow(attendee)
                    }
                }
            }
        }
    }

    private func attendeeRow(_ attendee: EventRegistrationAttendee) -> some View {
        HStack(spacing: AppTheme.dashboardSpacing) {
            AvatarArtworkView(
                avatarURL: attendee.avatarURL,
                initials: attendee.initials,
                size: 40,
                showsBorder: false,
                shadowOpacity: 0,
                shadowRadius: 0,
                shadowY: 0,
                initialsFont: AppTheme.badgeFont,
                placeholderFill: AppTheme.accentPrimarySoft
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(attendee.displayTitle)
                    .font(AppTheme.cardSubtitleFont)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(attendee.registeredAt.map {
                    LocalizationStore.dateString(from: $0, dateStyle: .medium, timeStyle: .short)
                } ?? attendee.displaySubtitle)
                    .font(AppTheme.metadataFont)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(AppTheme.accentSuccessForeground)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
