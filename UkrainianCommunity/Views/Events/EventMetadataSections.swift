import MapKit
import SwiftUI

fileprivate struct EventContactRowModel: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let systemImage: String
    let url: URL?
}

extension EventDetailView {
        @ViewBuilder
        func infoCard(for event: Event) -> some View {
            if event.requiresRegistration, let capacity = event.capacity ?? (event.registeredCount > 0 ? event.registeredCount : nil) {
                SoftContentCard(padding: AppTheme.detailCompactCardPadding) {
                    HStack(spacing: AppTheme.dashboardSpacing) {
                        Image(systemName: "info.circle")
                            .font(AppTheme.buttonLabelFont)
                            .foregroundStyle(AppTheme.accentPrimaryForeground)

                        VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
                            Text(AppStrings.Events.expectedParticipants)
                                .font(AppTheme.buttonLabelFont)
                                .foregroundStyle(AppTheme.textPrimary)

                            Text(event.capacity == nil ? "\(event.registeredCount)" : "\(event.registeredCount) / \(capacity)")
                                .font(AppTheme.secondaryBodyFont.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }

        func aboutCard(for event: Event) -> some View {
            DetailCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Events.aboutSectionTitle)
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimaryForeground)

                    Text(event.localizedDetails)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        @ViewBuilder
        func eventTagsCard(for event: Event) -> some View {
            if !event.additionalCategories.isEmpty || !event.tags.isEmpty {
                DetailCard {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        if !event.additionalCategories.isEmpty {
                            Text(AppStrings.Events.additionalCategoriesTitle)
                                .font(AppTheme.sectionTitleFont)
                                .foregroundStyle(AppTheme.accentPrimaryForeground)

                            AppHorizontalChipRow(spacing: 8) {
                                ForEach(event.additionalCategories) { category in
                                    AppInfoChip(title: category.title, systemImage: category.systemImage, size: .small)
                                }
                            }
                        }

                        if !event.tags.isEmpty {
                            Text(AppStrings.Events.tagsSectionTitle)
                                .font(AppTheme.sectionTitleFont)
                                .foregroundStyle(AppTheme.accentPrimaryForeground)

                            AppHorizontalChipRow(spacing: 8) {
                                ForEach(event.tags, id: \.self) { tag in
                                    AppInfoChip(title: tag, systemImage: "tag", size: .small)
                                }
                            }
                        }
                    }
                }
            }
        }

        @ViewBuilder
        func organizerCard(for event: Event) -> some View {
            DetailCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppStrings.Events.publishedBySectionTitle)
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimaryForeground)

                    HStack(spacing: AppTheme.dashboardSpacing) {
                        AppFeedThumbnail(
                            imageURL: event.source.organizationImageURL,
                            fallbackSystemImage: "building.2",
                            tint: AppTheme.accentPrimaryForeground,
                            fill: AppTheme.accentPrimarySoft,
                            size: AppTheme.organizationsThumbnailSize,
                            cornerRadius: AppTheme.feedThumbnailRadius,
                            source: "EventDetailOrganizer"
                        )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(eventSourceName(for: event))
                                .font(AppTheme.cardTitleFont)
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(2)

                            Label(eventPublisherText(for: event), systemImage: "person.crop.circle")
                                .font(AppTheme.cardSubtitleFont)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            AppInfoChip(
                                title: event.source.sourceType == .organization ? AppStrings.Organizations.detailBadge : AppStrings.Home.brandTitle,
                                systemImage: "building.2",
                                tint: AppTheme.accentPrimaryForeground,
                                fill: AppTheme.accentPrimarySoft,
                                size: .small
                            )
                        }

                    }
                }
            }
        }

        @ViewBuilder
        func eventContactCard(for event: Event) -> some View {
            let rows = eventContactRows(for: event)
            if !rows.isEmpty {
                DetailCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppStrings.Events.organizerContactSectionTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.accentPrimaryForeground)

                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(rows) { row in
                                eventContactRow(row)
                            }
                        }
                    }
                }
            }
        }

        fileprivate func eventContactRow(_ row: EventContactRowModel) -> some View {
            Group {
                if let url = row.url {
                    Link(destination: url) {
                        eventContactRowContent(row)
                    }
                    .buttonStyle(.plain)
                } else {
                    eventContactRowContent(row)
                }
            }
        }

        fileprivate func eventContactRowContent(_ row: EventContactRowModel) -> some View {
            HStack(alignment: .center, spacing: AppTheme.eventsMetadataSpacing) {
                Image(systemName: row.systemImage)
                    .font(AppTheme.metadataStrongFont)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)

                    Text(row.value)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(row.url == nil ? AppTheme.textPrimary : AppTheme.accentPrimaryForeground)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                if row.url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(AppTheme.metadataStrongFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }

        fileprivate func displayedOrganizerName(for event: Event) -> String? {
            guard let organizerName = event.organizerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForEventContact else {
                return nil
            }

            let publisherName = eventSourceName(for: event).trimmingCharacters(in: .whitespacesAndNewlines)
            guard organizerName.caseInsensitiveCompare(publisherName) != .orderedSame else {
                return nil
            }

            return organizerName
        }

        fileprivate func eventContactRows(for event: Event) -> [EventContactRowModel] {
            var rows: [EventContactRowModel] = []

            if let organizerName = displayedOrganizerName(for: event) {
                rows.append(EventContactRowModel(
                    title: AppStrings.Events.detailOrganizerSectionTitle,
                    value: organizerName,
                    systemImage: "person.crop.circle",
                    url: normalizedEventURL(event.organizerURL)
                ))
            } else if let organizerURL = normalizedEventURL(event.organizerURL) {
                rows.append(EventContactRowModel(
                    title: AppStrings.Events.organizerURLField,
                    value: event.organizerURL ?? organizerURL.absoluteString,
                    systemImage: "link",
                    url: organizerURL
                ))
            }

            if let phone = event.contactPhone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForEventContact {
                rows.append(EventContactRowModel(
                    title: AppStrings.Events.contactPhoneField,
                    value: phone,
                    systemImage: "phone",
                    url: phoneURL(phone)
                ))
            }

            if let email = event.contactEmail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForEventContact {
                rows.append(EventContactRowModel(
                    title: AppStrings.Events.contactEmailField,
                    value: email,
                    systemImage: "envelope",
                    url: URL(string: "mailto:\(email)")
                ))
            }

            if let contactURL = normalizedEventURL(event.contactURL) {
                rows.append(EventContactRowModel(
                    title: AppStrings.Events.contactURLField,
                    value: event.contactURL ?? contactURL.absoluteString,
                    systemImage: "safari",
                    url: contactURL
                ))
            }

            return rows
        }

        func normalizedEventURL(_ value: String?) -> URL? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }

            if let url = URL(string: trimmed),
               let scheme = url.scheme?.lowercased(),
               ["http", "https"].contains(scheme),
               url.host?.isEmpty == false {
                return url
            }

            guard !trimmed.contains("://"),
                  let url = URL(string: "https://\(trimmed)"),
                  url.host?.isEmpty == false else {
                return nil
            }

            return url
        }

        func phoneURL(_ phone: String) -> URL? {
            let allowed = Set("+0123456789")
            let normalized = phone.filter { allowed.contains($0) }
            guard !normalized.isEmpty else { return nil }
            return URL(string: "tel:\(normalized)")
        }

        func detailsCard(for event: Event) -> some View {
            DetailCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppStrings.Events.detailsSectionTitle)
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                    if event.participationMode != .none {
                        EventDetailRow(systemImage: "tag", title: AppStrings.Events.priceTitle, value: eventPriceText(for: event))
                        if event.participationMode == .inAppRegistration {
                            EventDetailRow(systemImage: "person.2", title: AppStrings.Events.expectedParticipants, value: eventParticipantsText(for: event))
                        }
                        EventDetailRow(systemImage: "checklist", title: ContentPublishingStrings.participation, value: event.participationMode.localizedTitle)
                    } else {
                        EventDetailRow(systemImage: "checkmark.seal", title: AppStrings.Events.requiresRegistrationToggle, value: AppStrings.Events.registrationNotRequired)
                    }
                    EventDetailRow(systemImage: "calendar", title: AppStrings.Events.addedDate, value: LocalizationStore.dateString(from: event.createdAt, dateStyle: .medium, timeStyle: .none))
                }
            }
        }

        func locationCard(for event: Event) -> some View {
            DetailCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Text(AppStrings.Events.locationSectionTitle)
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimaryForeground)

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

        func locationVenueBlock(for event: Event, alignsWithMapPreview: Bool = false) -> some View {
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

        func locationTextBlock(for event: Event) -> some View {
            let locationLines = deduplicatedLocationLines(for: event)

            return VStack(alignment: .leading, spacing: 5) {
                Text(locationLines.title)
                    .font(AppTheme.buttonLabelFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                if let subtitle = locationLines.subtitle {
                    Text(subtitle)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                if let city = locationLines.city {
                    Text(city)
                        .font(AppTheme.detailMetadataFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                if let locationNote = locationNoteText(for: event) {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(AppTheme.metadataStrongFont)
                            .foregroundStyle(AppTheme.accentPrimaryForeground.opacity(0.86))
                            .padding(.top, 1)

                        Text(locationNote)
                            .font(AppTheme.detailMetadataFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(3)
                    }
                    .padding(.top, 2)
                }
            }
        }

        func locationNoteText(for event: Event) -> String? {
            let trimmedLocationNote = event.locationNote?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedLocationNote?.isEmpty == true ? nil : trimmedLocationNote
        }

        func locationMapPreviewBlock(coordinate: CLLocationCoordinate2D) -> some View {
            VStack {
                Spacer(minLength: 0)
                eventMapPreview(coordinate: coordinate)
                    .frame(width: 158, height: 112)
                Spacer(minLength: 0)
            }
            .frame(width: 158, alignment: .center)
            .frame(minHeight: 124, alignment: .center)
        }

        func eventMapPreview(coordinate: CLLocationCoordinate2D) -> some View {
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
        func similarEventsSection(for event: Event) -> some View {
            let similarEvents = similarEvents(for: event)

            if !similarEvents.isEmpty {
                DetailCard {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        Text(AppStrings.Events.similarEvents)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.accentPrimaryForeground)

                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(similarEvents) { relatedEvent in
                                NavigationLink {
                                    EventDetailView(
                                        viewModel: viewModel,
                                        eventID: relatedEvent.id,
                                        onEventDeleted: onEventDeleted
                                    )
                                    .environment(\.eventPresentationMode, presentationMode)
                                } label: {
                                    EventSimilarCard(event: relatedEvent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }

        func similarEvents(for event: Event) -> [Event] {
            let now = Date()
            return viewModel.events
                .filter { $0.id != event.id && $0.nextOccurrence(relativeTo: now) != nil }
                .sorted { lhs, rhs in
                    let lhsScore = similarEventScore(lhs, comparedTo: event)
                    let rhsScore = similarEventScore(rhs, comparedTo: event)
                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }

                    let sourceDate = event.nextOccurrence(relativeTo: now)?.startDate ?? event.startDate
                    let lhsDate = lhs.nextOccurrence(relativeTo: now)?.startDate ?? lhs.startDate
                    let rhsDate = rhs.nextOccurrence(relativeTo: now)?.startDate ?? rhs.startDate
                    let lhsProximity = abs(lhsDate.timeIntervalSince(sourceDate))
                    let rhsProximity = abs(rhsDate.timeIntervalSince(sourceDate))
                    if lhsProximity != rhsProximity {
                        return lhsProximity < rhsProximity
                    }

                    return lhsDate < rhsDate
                }
                .prefix(4)
                .map { $0 }
        }

        func similarEventScore(_ candidate: Event, comparedTo event: Event) -> Int {
            var score = tagOverlap(candidate.tags, event.tags) * 100

            if candidate.category == event.category
                || candidate.additionalCategories.contains(event.category)
                || event.additionalCategories.contains(candidate.category) {
                score += 35
            }

            if let candidateState = candidate.federalState, candidateState == event.federalState {
                score += 25
            } else if candidate.regionScope == event.regionScope {
                score += 8
            }

            if let candidateOrganizationID = candidate.source.organizationId,
               candidateOrganizationID == event.source.organizationId {
                score += 20
            } else if normalizedMatch(candidate.organizerName, event.organizerName) {
                score += 10
            }

            if normalizedMatch(candidate.city, event.city) {
                score += 6
            }

            return score
        }

        func tagOverlap(_ lhs: [String], _ rhs: [String]) -> Int {
            let leftTags = Set(lhs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
            let rightTags = Set(rhs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
            return leftTags.intersection(rightTags).count
        }

        func normalizedMatch(_ lhs: String?, _ rhs: String?) -> Bool {
            let left = lhs?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let right = rhs?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return !left.isEmpty && left == right
        }

        func commentsCard(for event: Event) -> some View {
            ContentCommentsSection(
                comments: event.comments,
                loadState: viewModel.commentLoadStates[event.id] ?? .loading,
                retry: { await viewModel.loadComments(for: event.id, forceRefresh: true) },
                composer: { eventCommentComposer(eventID: event.id) },
                row: { comment in eventCommentRow(comment, parentTitle: event.localizedTitle) }
            )
        }

        func eventCommentComposer(eventID: String) -> some View {
            let author = authState.user
            return ContentCommentComposer(
                accountID: authState.isAuthenticated ? authState.user?.id : nil,
                canComment: PermissionService.isUsableAccount(user: authState.user),
                isPending: viewModel.pendingEventCommentIDs.contains(eventID),
                focus: $isCommentFieldFocused,
                signIn: { guestAccessAction = .comments },
                send: { text in
                    guard let user = author, authState.user?.id == user.id else { return .failure(.permissionDenied) }
                    return await viewModel.addComment(to: eventID, text: text, author: user)
                }
            )
            .id(eventID)
        }

        func eventCommentRow(_ comment: Comment, parentTitle: String) -> some View {
            ContentCommentRow(comment: comment) {
                if canDeleteComment(comment) || canReportComment(comment) || canBlockComment(comment) {
                    eventCommentActionMenu(for: comment, parentTitle: parentTitle)
                }
            }
        }

        func eventCommentActionMenu(for comment: Comment, parentTitle: String) -> some View {
            Menu {
                if canDeleteComment(comment) {
                    Button(AppStrings.Action.delete, systemImage: "trash", role: .destructive) {
                        pendingCommentDeleteID = comment.id
                    }
                }
                if canReportComment(comment),
                   let target = ContentReportTarget.comment(comment, parentTitle: parentTitle, parentType: .event, parentId: eventID) {
                    Button(AppStrings.Safety.reportAction, systemImage: "exclamationmark.bubble") {
                        presentContentReport(target)
                    }
                }
                if canBlockComment(comment), let target = UserBlockTarget.comment(comment) {
                    Button(AppStrings.Safety.blockAction, systemImage: "person.slash", role: .destructive) {
                        userBlockingPresentation.present(target)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(AppTheme.sectionTitleFont)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(
                        width: AppTheme.minimumInteractiveTarget,
                        height: AppTheme.minimumInteractiveTarget
                    )
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.Safety.moreActions)
        }

        func canReportComment(_ comment: Comment) -> Bool {
            !authState.isAuthenticated || comment.authorId != authState.user?.id
        }

        func canBlockComment(_ comment: Comment) -> Bool {
            authState.isAuthenticated && comment.authorId != nil && comment.authorId != authState.user?.id
        }

        func canDeleteComment(_ comment: Comment) -> Bool {
            guard let user = authState.user else { return false }
            if PermissionService.canModerate(section: .comments, user: user) || PermissionService.canModerate(section: .events, user: user) {
                return true
            }
            guard let event = viewModel.event(for: eventID), let organizationId = event.source.organizationId else {
                return false
            }
            if let organization = organizationForPermissions(organizationID: organizationId) {
                return PermissionService.canModerateOrganizationContent(organization, user: user)
            }
            return false
        }

    struct EventSimilarCard: View {
        let event: Event

        var body: some View {
            let occurrence = event.nextOccurrence() ?? event.occurrences.first ?? EventOccurrence(
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay
            )
            SoftContentCard(padding: AppTheme.eventsCardPadding) {
                HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                    AppEventDateBlock(date: occurrence.startDate)

                    VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
                        AppInfoChip(
                            title: event.category.title,
                            systemImage: event.category.systemImage,
                            tint: AppTheme.accentPrimaryForeground,
                            fill: AppTheme.accentPrimarySoft,
                            size: .small
                        )

                        Text(event.localizedTitle)
                            .font(AppTheme.cardTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: AppTheme.eventsMetadataSpacing) {
                            AppMetadataLine(
                                title: LocalizationStore.timeRangeString(startDate: occurrence.startDate, endDate: occurrence.endDate),
                                systemImage: "clock"
                            )
                            AppMetadataLine(
                                title: event.city,
                                systemImage: "mappin.and.ellipse"
                            )
                        }
                        .lineLimit(1)
                    }

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Image(systemName: "chevron.right")
                        .font(AppTheme.metadataStrongFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    struct EventDetailRow: View {
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
                featuredBannerRepository: MockFeaturedBannerRepository(),
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
}

private extension String {
    var nilIfBlankForEventContact: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
