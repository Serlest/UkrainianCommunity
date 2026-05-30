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
                            .foregroundStyle(AppTheme.accentPrimary)

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
                        .foregroundStyle(AppTheme.accentPrimary)

                    Text(event.details)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.accentPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        @ViewBuilder
        func eventTagsCard(for event: Event) -> some View {
            if !event.tags.isEmpty {
                DetailCard {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        Text(AppStrings.Events.tagsSectionTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.accentPrimary)

                        AppHorizontalChipRow(spacing: 8) {
                            ForEach(event.tags, id: \.self) { tag in
                                AppInfoChip(
                                    title: tag,
                                    systemImage: "tag",
                                    size: .small
                                )
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
                    Text(AppStrings.Events.detailOrganizerSectionTitle)
                        .font(AppTheme.sectionTitleFont)
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
                                tint: AppTheme.accentPrimary,
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
                            .foregroundStyle(AppTheme.accentPrimary)

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
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)

                    Text(row.value)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(row.url == nil ? AppTheme.textPrimary : AppTheme.accentPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                if row.url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(AppTheme.metadataStrongFont)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }

        fileprivate func eventContactRows(for event: Event) -> [EventContactRowModel] {
            var rows: [EventContactRowModel] = []

            if let organizerName = event.organizerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForEventContact {
                rows.append(EventContactRowModel(
                    title: AppStrings.Events.organizerNameField,
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
                        .foregroundStyle(AppTheme.accentPrimary)
                    if event.requiresRegistration {
                        EventDetailRow(systemImage: "tag", title: AppStrings.Events.priceTitle, value: eventPriceText(for: event))
                        EventDetailRow(systemImage: "person.2", title: AppStrings.Events.expectedParticipants, value: eventParticipantsText(for: event))
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
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
                        .lineLimit(1)
                }

                if let locationNote = locationNoteText(for: event) {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(AppTheme.metadataStrongFont)
                            .foregroundStyle(AppTheme.accentPrimary.opacity(0.86))
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
                            .foregroundStyle(AppTheme.accentPrimary)

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
                .filter { $0.id != event.id && $0.endDate >= now }
                .sorted { lhs, rhs in
                    let lhsScore = similarEventScore(lhs, comparedTo: event)
                    let rhsScore = similarEventScore(rhs, comparedTo: event)
                    if lhsScore != rhsScore {
                        return lhsScore > rhsScore
                    }

                    let lhsProximity = abs(lhs.startDate.timeIntervalSince(event.startDate))
                    let rhsProximity = abs(rhs.startDate.timeIntervalSince(event.startDate))
                    if lhsProximity != rhsProximity {
                        return lhsProximity < rhsProximity
                    }

                    return lhs.startDate < rhs.startDate
                }
                .prefix(4)
                .map { $0 }
        }

        func similarEventScore(_ candidate: Event, comparedTo event: Event) -> Int {
            var score = tagOverlap(candidate.tags, event.tags) * 100

            if candidate.category == event.category {
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
            DetailCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppStrings.Common.comments)
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimary)

                    eventCommentComposer(eventID: event.id)

                    if event.comments.isEmpty {
                        Text(AppStrings.Common.noCommentsYet)
                            .font(AppTheme.cardSubtitleFont)
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

        func eventCommentComposer(eventID: String) -> some View {
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
                                .font(AppTheme.sectionTitleFont)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(AppTheme.accentPrimary, in: Circle())
                        }
                        .disabled(trimmedCommentText.isEmpty || viewModel.pendingEventCommentIDs.contains(eventID))
                        .opacity(trimmedCommentText.isEmpty ? 0.55 : 1)
                    }

                    Text("\(commentText.count)/1000")
                        .font(AppTheme.metadataFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Button {
                        guestAccessAction = .comments
                    } label: {
                        Label(AppStrings.Common.signInToComment, systemImage: "person.crop.circle.badge.plus")
                            .font(AppTheme.metadataStrongFont)
                            .foregroundStyle(AppTheme.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        func eventCommentRow(_ comment: Comment) -> some View {
            HStack(alignment: .top, spacing: 10) {
                eventCommentAvatar(comment)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: AppTheme.eventsMetadataSpacing) {
                        Text(sanitizedEventCommentAuthorName(comment.authorName))
                            .font(AppTheme.buttonLabelFont)
                            .foregroundStyle(AppTheme.textPrimary)

                        Spacer(minLength: AppTheme.eventsMetadataSpacing)

                        Text(LocalizationStore.dateString(from: comment.createdAt, dateStyle: .short, timeStyle: .short))
                            .font(AppTheme.metadataFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)

                        if canEditComment(comment) || canDeleteComment(comment) {
                            eventCommentActionMenu(for: comment)
                        }
                    }

                    Text(comment.text)
                        .font(AppTheme.secondaryBodyFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        func eventCommentActionMenu(for comment: Comment) -> some View {
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
                    .font(AppTheme.sectionTitleFont)
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
        var managementCard: some View {
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

        func eventManagementButton(title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
            Button(role: role, action: action) {
                Label(title, systemImage: systemImage)
                    .font(AppTheme.metadataStrongFont)
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

        var trimmedCommentText: String {
            commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func submitEventComment(eventID: String) {
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

        func canEditComment(_ comment: Comment) -> Bool {
            guard let user = authState.user else { return false }
            return comment.authorId == user.id
        }

        func canDeleteComment(_ comment: Comment) -> Bool {
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

        func eventCommentAvatar(_ comment: Comment) -> some View {
            let avatarURL = comment.authorPhotoURL.flatMap { URL(string: $0) }
            return AvatarArtworkView(
                avatarURL: avatarURL,
                initials: eventCommentInitials(comment),
                size: 32,
                showsBorder: false,
                shadowOpacity: 0,
                shadowRadius: 0,
                shadowY: 0,
                initialsFont: AppTheme.badgeFont,
                placeholderFill: AppTheme.accentPrimarySoft
            )
        }

        func eventCommentInitials(_ comment: Comment) -> String {
            let name = sanitizedEventCommentAuthorName(comment.authorName)
            return String(name.prefix(1)).uppercased()
        }

    struct EventSimilarCard: View {
        let event: Event

        var body: some View {
            SoftContentCard(padding: AppTheme.eventsCardPadding) {
                HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                    AppEventDateBlock(date: event.startDate)

                    VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
                        AppInfoChip(
                            title: event.category.title,
                            systemImage: event.category.systemImage,
                            tint: AppTheme.accentPrimary,
                            fill: AppTheme.accentPrimarySoft,
                            size: .small
                        )

                        Text(event.title)
                            .font(AppTheme.cardTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: AppTheme.eventsMetadataSpacing) {
                            AppMetadataLine(
                                title: LocalizationStore.timeRangeString(startDate: event.startDate, endDate: event.endDate),
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
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
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
