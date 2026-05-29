import SwiftUI

extension EventDetailView {
        func eventScheduleCard(for event: Event) -> some View {
            DetailCard {
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
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder
        func eventRegistrationManagementCard(for event: Event) -> some View {
            if event.requiresRegistration && canManageEventRegistrations(event) {
                DetailCard {
                    VStack(alignment: .leading, spacing: AppTheme.detailInnerSpacing) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(AppStrings.Events.registrationManagementTitle)
                                .font(AppTheme.sectionTitleFont)
                                .foregroundStyle(AppTheme.textPrimary)

                            Spacer()

                            Text("\(resolvedRegistrationAttendeeCount(for: event))")
                                .font(AppTheme.badgeFont)
                                .foregroundStyle(AppTheme.accentPrimary)
                                .monospacedDigit()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.accentPrimarySoft, in: Capsule())
                        }

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
                                .foregroundStyle(AppTheme.accentDestructive)
                        } else if eventRegistrationAttendees.isEmpty {
                            Text(AppStrings.Events.registrationManagementEmpty)
                                .font(AppTheme.secondaryBodyFont)
                                .foregroundStyle(AppTheme.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(eventRegistrationAttendees) { attendee in
                                    eventRegistrationAttendeeRow(attendee)
                                }
                            }
                        }
                    }
                }
                .task(id: event.id) {
                    await loadEventRegistrationAttendeesIfNeeded(for: event)
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

        func engagementCard(for event: Event, scrollProxy: ScrollViewProxy) -> some View {
            detailGlassCard(padding: 9) {
                DetailActionRow {
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
                    }
                } trailingContent: {
                    publisherLine(for: event)
                }
            }
        }

        func focusEventComments(using scrollProxy: ScrollViewProxy) {
            withAnimation(.easeInOut(duration: 0.32)) {
                scrollProxy.scrollTo(commentsSectionID, anchor: .top)
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
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

        func publisherLine(for event: Event) -> some View {
            Label(eventPublisherText(for: event), systemImage: "person.crop.circle")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.86))
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
