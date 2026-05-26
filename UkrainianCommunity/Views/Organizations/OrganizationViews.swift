import Combine
import MapKit
import PhotosUI
import SwiftUI

private struct OrganizationNavigationRoute: Hashable {
    let organizationID: String
}

enum OrganizationPresentationMode {
    case `public`
    case management

    var allowsManagementControls: Bool {
        self == .management
    }
}

private func organizationActivityDateText(for item: OrganizationActivityItem) -> String {
    LocalizationStore.dateString(from: item.publishedAt, dateStyle: .medium, timeStyle: .short)
}

private func organizationActivityEventText(for item: OrganizationActivityItem) -> String? {
    guard let eventStartDate = item.eventStartDate else { return nil }
    return LocalizationStore.dateString(from: eventStartDate, dateStyle: .medium, timeStyle: .short)
}

private func organizationActivityLocationText(for item: OrganizationActivityItem) -> String? {
    if let city = item.city, !city.isEmpty {
        if let venue = item.eventVenue, !venue.isEmpty {
            return "\(city) • \(venue)"
        }
        return city
    }
    return nil
}

private func organizationContactText(for organization: Organization) -> String? {
    let contactEmail = (organization.email ?? organization.contactEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !contactEmail.isEmpty else { return nil }
    return contactEmail
}

private func organizationWebsiteText(for organization: Organization) -> String? {
    guard let website = organization.website?.trimmingCharacters(in: .whitespacesAndNewlines), !website.isEmpty else { return nil }
    return website
}

private func organizationWebsiteDisplayText(for organization: Organization) -> String? {
    guard let website = organizationWebsiteText(for: organization) else { return nil }
    let normalized = website.hasPrefix("http://") || website.hasPrefix("https://") ? website : "https://\(website)"
    guard let url = URL(string: normalized), let host = url.host, !host.isEmpty else {
        return website
    }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

private func organizationWebsiteURL(for organization: Organization) -> URL? {
    guard let website = organizationWebsiteText(for: organization) else { return nil }
    return normalizedOrganizationURL(from: website)
}

private func normalizedOrganizationURL(from value: String?) -> URL? {
    guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else { return nil }
    let normalized = rawValue.hasPrefix("http://") || rawValue.hasPrefix("https://") ? rawValue : "https://\(rawValue)"
    guard let url = URL(string: normalized), url.host?.isEmpty == false else { return nil }
    return url
}

private func cleanURLDisplayText(_ url: URL) -> String {
    guard let host = url.host, !host.isEmpty else {
        return url.absoluteString
    }

    let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    let path = url.path == "/" ? "" : url.path
    return "\(cleanHost)\(path)"
}

private func organizationTelegramURL(for organization: Organization) -> URL? {
    if let explicitURL = normalizedTelegramContactURL(from: organization.telegramURL) {
        return explicitURL
    }

    if let telegramLink = organization.socialLinks.first(where: { key, value in
        key.localizedCaseInsensitiveContains("telegram")
            || value.localizedCaseInsensitiveContains("t.me")
            || value.localizedCaseInsensitiveContains("telegram.me")
    })?.value {
        return normalizedTelegramContactURL(from: telegramLink)
    }

    return nil
}

private func normalizedTelegramContactURL(from value: String?) -> URL? {
    guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else { return nil }

    let lowercaseValue = rawValue.lowercased()
    if rawValue.hasPrefix("@") {
        return URL(string: "https://t.me/\(rawValue.dropFirst())")
    }
    if lowercaseValue.hasPrefix("https://t.me/") || lowercaseValue.hasPrefix("http://t.me/")
        || lowercaseValue.hasPrefix("https://telegram.me/") || lowercaseValue.hasPrefix("http://telegram.me/") {
        return URL(string: rawValue)
    }
    if lowercaseValue.hasPrefix("t.me/") || lowercaseValue.hasPrefix("telegram.me/") {
        return URL(string: "https://\(rawValue)")
    }
    if !rawValue.contains("://"), !rawValue.contains("."), !rawValue.contains("/") {
        return URL(string: "https://t.me/\(rawValue)")
    }
    return normalizedOrganizationURL(from: rawValue)
}

private func organizationSocialURL(for organization: Organization, matching platform: String) -> URL? {
    organization.socialLinks.first { key, value in
        key.localizedCaseInsensitiveContains(platform)
            || value.localizedCaseInsensitiveContains(platform)
    }.flatMap { _, value in
        normalizedSocialContactURL(value, platform: platform)
    }
}

private func normalizedSocialContactURL(_ rawValue: String, platform: String) -> URL? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let lowercasePlatform = platform.lowercased()
    let lowercaseValue = trimmed.lowercased()
    if lowercasePlatform.contains("telegram") || lowercaseValue.hasPrefix("@") || lowercaseValue.contains("t.me/") {
        return normalizedTelegramContactURL(from: trimmed)
    }
    if lowercasePlatform.contains("instagram"), !lowercaseValue.contains("instagram.com") {
        let username = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        return normalizedOrganizationURL(from: "instagram.com/\(username)")
    }
    if lowercasePlatform.contains("facebook"), !lowercaseValue.contains("facebook.com") && !lowercaseValue.contains("fb.com") {
        return normalizedOrganizationURL(from: "facebook.com/\(trimmed)")
    }
    return normalizedOrganizationURL(from: trimmed)
}

private func organizationAddressText(for organization: Organization) -> String? {
    let address = (organization.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)

    if !address.isEmpty, !city.isEmpty, !address.localizedCaseInsensitiveContains(city) {
        return "\(address), \(city)"
    }
    if !address.isEmpty {
        return address
    }
    return nil
}

private func organizationMapURL(for organization: Organization) -> URL? {
    if let latitude = organization.latitude, let longitude = organization.longitude {
        return URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(organization.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
    }

    let address = organizationAddressText(for: organization)
    let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)
    let query = (address ?? city).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty,
          let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
        return nil
    }
    return URL(string: "https://maps.apple.com/?q=\(encodedQuery)")
}

private func emailURL(for email: String) -> URL? {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
        return nil
    }
    return URL(string: "mailto:\(encoded)")
}

private func phoneURL(for phone: String) -> URL? {
    let digits = phone.filter { $0.isNumber || $0 == "+" }
    guard !digits.isEmpty else { return nil }
    return URL(string: "tel:\(digits)")
}

struct OrganizationContactCard: View {
    let organization: Organization
    let allowsEditing: Bool
    let showsManagementActions: Bool
    let onEdit: (() -> Void)?

    private var contactItems: [OrganizationContactItem] {
        var items: [OrganizationContactItem] = []

        if let websiteURL = organizationWebsiteURL(for: organization) {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldWebsite,
                    value: cleanURLDisplayText(websiteURL),
                    systemImage: "globe",
                    destination: websiteURL
                )
            )
        }
        if let telegramURL = organizationTelegramURL(for: organization) {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldTelegram,
                    value: cleanURLDisplayText(telegramURL),
                    systemImage: "paperplane",
                    destination: telegramURL
                )
            )
        }
        if let instagramURL = organizationSocialURL(for: organization, matching: "instagram") {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldInstagram,
                    value: cleanURLDisplayText(instagramURL),
                    systemImage: "camera",
                    destination: instagramURL
                )
            )
        }
        if let facebookURL = organizationSocialURL(for: organization, matching: "facebook") {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldFacebook,
                    value: cleanURLDisplayText(facebookURL),
                    systemImage: "person.2",
                    destination: facebookURL
                )
            )
        }
        if let contactEmail = organizationContactText(for: organization),
           let destination = emailURL(for: contactEmail) {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldEmail,
                    value: contactEmail,
                    systemImage: "envelope",
                    destination: destination
                )
            )
        }
        if let phone = organization.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty,
           let destination = phoneURL(for: phone) {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldPhone,
                    value: phone,
                    systemImage: "phone",
                    destination: destination
                )
            )
        }
        if let address = organizationAddressText(for: organization),
           let destination = organizationMapURL(for: organization) {
            items.append(
                OrganizationContactItem(
                    title: AppStrings.Organizations.fieldLocation,
                    value: address,
                    systemImage: "mappin.and.ellipse",
                    destination: destination,
                    isAddress: true
                )
            )
        }

        return items
    }

    private var contactPerson: String? {
        let value = organization.contactPerson?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private var websiteURL: URL? {
        organizationWebsiteURL(for: organization)
    }

    private var telegramURL: URL? {
        organizationTelegramURL(for: organization)
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        AppEditorSectionTitle(title: AppStrings.Organizations.tabContacts)
                        Text(AppStrings.Organizations.contactsSubtitle)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    if allowsEditing, let onEdit {
                        Button(action: onEdit) {
                            Label(AppStrings.Organizations.contactsEdit, systemImage: "square.and.pencil")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel(AppStrings.Organizations.contactsEdit)
                    }
                }

                if contactItems.isEmpty, contactPerson == nil {
                    contactEmptyState
                } else {
                    if let contactPerson {
                        contactPersonView(contactPerson)
                    }

                    VStack(spacing: 0) {
                        ForEach(contactItems) { item in
                            OrganizationContactRow(item: item, organization: organization)
                            if item.id != contactItems.last?.id {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .background(AppTheme.surfaceControl.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.borderSubtle.opacity(0.75))
                    )

                    if showsManagementActions {
                        contactQuickActions
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contactEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(AppStrings.Organizations.contactsEmptyTitle, systemImage: "person.crop.circle.badge")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.Organizations.contactsEmptyMessage)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)

            if allowsEditing, let onEdit {
                Button(action: onEdit) {
                    Label(AppStrings.Organizations.contactsAdd, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppTheme.accentPrimary)
                .padding(.top, 4)
                .accessibilityLabel(AppStrings.Organizations.contactsAdd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func contactPersonView(_ contactPerson: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentPrimary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(AppStrings.Organizations.fieldContactPersonDisplay)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(contactPerson)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceControl.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.75))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AppStrings.Organizations.fieldContactPersonDisplay): \(contactPerson)")
    }

    @ViewBuilder
    private var contactQuickActions: some View {
        HStack(spacing: 8) {
            if allowsEditing, let onEdit {
                Button(action: onEdit) {
                    Label(AppStrings.Organizations.contactsEdit, systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let websiteURL {
                Link(destination: websiteURL) {
                    Label(AppStrings.Organizations.contactsOpenWebsite, systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(AppStrings.Organizations.contactsOpenWebsite)
            }

            if let telegramURL {
                Link(destination: telegramURL) {
                    Label(AppStrings.Organizations.contactsOpenTelegram, systemImage: "paperplane")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(AppStrings.Organizations.contactsOpenTelegram)
            }
        }
        .font(.caption.weight(.semibold))
    }
}

struct OrganizationReadOnlyDetailContent: View {
    let organization: Organization
    var showsModerationStatus = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            previewHero
            supportCard
            aboutSection
            missionSection
            factsSection
            OrganizationContactCard(
                organization: organization,
                allowsEditing: false,
                showsManagementActions: false,
                onEdit: nil
            )
        }
    }

    private var previewHero: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                if let coverURL = organization.coverURL ?? organization.imageURL {
                    RemoteImageView(
                        imageURL: coverURL,
                        height: 190,
                        cornerRadius: AppTheme.cardRadius,
                        source: "OrganizationReadOnlyDetailContent.cover",
                        placeholderStyle: .glassSkeleton
                    )
                    .overlay(alignment: .bottomLeading) {
                        logoView
                            .frame(width: 92, height: 92)
                            .padding(12)
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    if organization.coverURL == nil && organization.imageURL == nil {
                        logoView
                            .frame(width: 92, height: 92)
                            .layoutPriority(1)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        AppHorizontalChipRow(spacing: 6) {
                            if showsModerationStatus {
                                AppInfoChip(
                                    title: organization.moderationStatus.title,
                                    systemImage: "clock.badge.checkmark",
                                    tint: AppTheme.accentPrimary,
                                    fill: AppTheme.accentPrimary.opacity(0.14),
                                    border: AppTheme.accentPrimary.opacity(0.20),
                                    size: .small
                                )
                            }
                            AppInfoChip(
                                title: organizationTypeTitle,
                                systemImage: "building.2",
                                tint: AppTheme.accentPrimary,
                                fill: AppTheme.accentPrimary.opacity(0.14),
                                border: AppTheme.accentPrimary.opacity(0.18),
                                size: .small
                            )
                        }

                        Text(organization.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppTheme.accentPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let shortDescription = trimmed(organization.shortDescription) {
                            Text(shortDescription)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var logoView: some View {
        Group {
            if let logoURL = organization.logoURL ?? organization.imageURL {
                RemoteImageView(
                    imageURL: logoURL,
                    height: 92,
                    cornerRadius: AppTheme.imageRadius,
                    source: "OrganizationReadOnlyDetailContent.logo",
                    placeholderStyle: .glassSkeleton
                )
            } else {
                RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                    .fill(cardSurface)
                    .overlay(
                        Text(initials(for: organization.name))
                            .font(.title.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimary)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
        .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: 6, y: 3)
    }

    @ViewBuilder
    private var supportCard: some View {
        if let donationURL = trimmed(organization.donationURL) {
            AppEditorSectionCard {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: 36, height: 36)
                        .background(cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.Organizations.supportOrganizationTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(AppStrings.Organizations.supportOrganizationSubtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text(donationURL)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private var aboutSection: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Organizations.aboutSectionTitle)
                Text(trimmed(organization.fullDescription) ?? trimmed(organization.description) ?? AppStrings.Organizations.aboutEmptyMessage)
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var missionSection: some View {
        if let missionStatement = trimmed(organization.missionStatement) {
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    AppEditorSectionTitle(title: AppStrings.Organizations.detailMissionStatementTitle)
                    Text(missionStatement)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var factsSection: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Organizations.mainInformationTitle)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing, alignment: .topLeading),
                        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing, alignment: .topLeading)
                    ],
                    alignment: .leading,
                    spacing: AppTheme.eventsMetadataSpacing
                ) {
                    ForEach(factItems, id: \.title) { item in
                        factTile(systemImage: item.systemImage, title: item.title, value: item.value)
                    }
                }
            }
        }
    }

    private var factItems: [(systemImage: String, title: String, value: String)] {
        var items: [(systemImage: String, title: String, value: String)] = [
            ("building.2", AppStrings.Organizations.categoryTitle, organizationTypeTitle)
        ]

        if !organization.languages.isEmpty {
            items.append(("text.bubble", AppStrings.Organizations.languagesTitle, organization.languages.joined(separator: ", ")))
        }
        if let location = detailedLocationText {
            items.append(("mappin.and.ellipse", AppStrings.Organizations.fieldLocation, location))
        }
        if let foundedText {
            items.append(("calendar", AppStrings.Organizations.foundedTitle, foundedText))
        }
        return items
    }

    private func factTile(systemImage: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(10)
        .background(cardSurface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
    }

    private var detailedLocationText: String? {
        let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let federalState = organization.federalState?.rawValue
        if !city.isEmpty, let federalState {
            return "\(city), \(federalState)"
        }
        if !city.isEmpty {
            return city
        }
        return federalState
    }

    private var organizationTypeTitle: String {
        guard let rawValue = trimmed(organization.organizationType),
              let category = OrganizationEditorCategory(rawValue: rawValue) else {
            return trimmed(organization.organizationType) ?? AppStrings.Organizations.detailBadge
        }
        return category.title
    }

    private var foundedText: String? {
        guard let foundedYear = organization.foundedYear else { return nil }
        if let foundedMonth = organization.foundedMonth {
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.year = foundedYear
            components.month = foundedMonth
            components.day = 1
            if let date = components.date {
                let formatter = DateFormatter()
                formatter.locale = LocalizationStore.locale
                formatter.dateFormat = "LLLL yyyy"
                return formatter.string(from: date)
            }
        }
        return String(foundedYear)
    }

    private var cardSurface: some ShapeStyle {
        reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme)
    }

    private func trimmed(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let initials = String(parts).uppercased()
        return initials.isEmpty ? "UC" : initials
    }
}

private struct OrganizationContactItem: Identifiable {
    let title: String
    let value: String
    let systemImage: String
    let destination: URL
    var isAddress = false

    var id: String {
        "\(title)-\(destination.absoluteString)"
    }
}

private struct OrganizationContactRow: View {
    let item: OrganizationContactItem
    let organization: Organization

    var body: some View {
        Link(destination: item.destination) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: item.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.accentPrimary.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)

                        Text(item.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(item.isAddress ? 2 : 1)
                            .truncationMode(item.isAddress ? .tail : .middle)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)

                if item.isAddress, organization.latitude != nil, organization.longitude != nil {
                    OrganizationContactMapPreview(organization: organization)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title): \(item.value)")
    }
}

private struct OrganizationContactMapPreview: View {
    let organization: Organization

    var body: some View {
        if let latitude = organization.latitude, let longitude = organization.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            )
            Map(initialPosition: .region(region)) {
                Marker(organization.name, coordinate: coordinate)
            }
            .allowsHitTesting(false)
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
        }
    }
}

private enum OrganizationDetailSection: CaseIterable, Identifiable {
    case about
    case news
    case events
    case photos
    case team
    case contacts

    var id: Self { self }

    static var selectableCases: [OrganizationCategoryFilter] {
        [.support, .integration, .culture, .education, .other]
    }

    var title: String {
        switch self {
        case .events:
            AppStrings.Organizations.tabEvents
        case .news:
            AppStrings.Organizations.tabNews
        case .about:
            AppStrings.Organizations.tabAbout
        case .contacts:
            AppStrings.Organizations.tabContacts
        case .team:
            AppStrings.Organizations.tabTeam
        case .photos:
            AppStrings.Organizations.tabPhoto
        }
    }

    var systemImage: String {
        switch self {
        case .events:
            "calendar"
        case .news:
            "newspaper"
        case .about:
            "info.circle"
        case .contacts:
            "person.crop.circle.badge"
        case .team:
            "person.3"
        case .photos:
            "photo.on.rectangle"
        }
    }
}

private enum OrganizationCommunityRole: Int {
    case owner = 0
    case admin = 1
    case moderator = 2
    case subscriber = 3

    var title: String {
        switch self {
        case .owner:
            AppStrings.Organizations.communityOwner
        case .admin:
            AppStrings.Organizations.communityAdmin
        case .moderator:
            AppStrings.Organizations.communityModerator
        case .subscriber:
            AppStrings.Organizations.communityMember
        }
    }
}

private struct OrganizationCommunityMember: Identifiable {
    let profile: PublicUserProfile
    let role: OrganizationCommunityRole
    let followedAt: Date?
    let isPlaceholder: Bool

    var id: String { profile.id }
}

private enum OrganizationCategoryFilter: CaseIterable, Identifiable {
    case all
    case support
    case integration
    case culture
    case education
    case other

    var id: Self { self }

    static var selectableCases: [OrganizationCategoryFilter] {
        [.support, .integration, .culture, .education, .other]
    }

    var title: String {
        switch self {
        case .all:
            AppStrings.Home.filterAll
        case .support:
            AppStrings.Organizations.categorySupport
        case .integration:
            AppStrings.Organizations.categoryIntegration
        case .culture:
            AppStrings.Organizations.categoryCulture
        case .education:
            AppStrings.Organizations.categoryEducation
        case .other:
            AppStrings.Organizations.categoryOther
        }
    }

    var systemImage: String? {
        switch self {
        case .all:
            "square.grid.2x2"
        case .support:
            "hands.sparkles"
        case .integration:
            "person.2"
        case .culture:
            "paintpalette"
        case .education:
            "graduationcap"
        case .other:
            "ellipsis"
        }
    }

    func matches(_ organization: Organization) -> Bool {
        guard !organization.isSystemOrganization else {
            return self == .all
        }

        guard self != .all else { return true }
        return organization.organizationType == categoryRawValue
    }

    private var categoryRawValue: String? {
        switch self {
        case .all:
            nil
        case .support:
            "support"
        case .integration:
            "integration"
        case .culture:
            "culture"
        case .education:
            "education"
        case .other:
            "other"
        }
    }
}

private enum OrganizationSavedFilterMode {
    case none
    case subscribed
    case bookmarked
}

@MainActor
private final class OrganizationActivityViewModel: ObservableObject {
    @Published private(set) var items: [OrganizationActivityItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private let organizationID: String
    private let organizationName: String
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    init(
        organizationID: String,
        organizationName: String,
        newsRepository: NewsRepository,
        eventRepository: EventRepository
    ) {
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
    }

    func loadIfNeeded(for organization: Organization) async {
        guard !hasLoaded else { return }
        await startLoad(for: organization, force: false)
    }

    func refresh(for organization: Organization) async {
        await startLoad(for: organization, force: true)
    }

    private func startLoad(for organization: Organization, force: Bool) async {
        guard force || !hasLoaded else { return }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(for: organization)
        }
        loadTask = task
        await task.value
        self.loadTask = nil
    }

    private func performLoad(for organization: Organization) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let newsLoad = newsRepository.fetchNews()
            async let eventsLoad = eventRepository.fetchEvents()

            let filteredNews = try await newsLoad
                .filter { belongsToOrganization($0.source, organization: organization) }
                .map(OrganizationActivityItem.init(post:))
            let filteredEvents = try await eventsLoad
                .filter { belongsToOrganization($0.source, organization: organization) }
                .map(OrganizationActivityItem.init(event:))

            guard !Task.isCancelled else { return }

            let profileItem = OrganizationActivityItem(profile: organization)
            let activityItems = (filteredNews + filteredEvents)
                .sorted { $0.publishedAt > $1.publishedAt }
            items = [profileItem] + activityItems
            error = nil
            hasLoaded = true
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }

    var isEmptyStateWithoutProfile: Bool {
        items.filter { $0.itemType != .organizationProfile }.isEmpty
    }

    private func belongsToOrganization(_ source: ContentSourceMetadata, organization: Organization) -> Bool {
        if organization.isSystemOrganization {
            return source.sourceType == .app || source.organizationId == Organization.systemOrganizationID
        }
        return source.organizationId == organizationID
    }
}

struct OrganizationsListView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: OrganizationsViewModel
    @StateObject private var heroBannerViewModel: AppHeroBannerViewModel
    let onOrganizationSaved: @MainActor () async -> Void
    let onOrganizationDeleted: @MainActor () -> Void
    let presentationMode: OrganizationPresentationMode
    @State private var pendingDeleteOrganizationID: String?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false
    @State private var selectedCategory: OrganizationCategoryFilter = .all
    @State private var selectedFederalState: AustrianFederalState?
    @State private var savedFilterMode: OrganizationSavedFilterMode = .none
    @State private var didManuallyChangeRegion = false
    @State private var isRegionPickerPresented = false
    @State private var selectedBannerPhoto: PhotosPickerItem?

    init(
        viewModel: OrganizationsViewModel,
        bannerService: HomeBannerServiceProtocol = FirestoreHomeBannerService(),
        onOrganizationSaved: @escaping @MainActor () async -> Void = {},
        onOrganizationDeleted: @escaping @MainActor () -> Void = {},
        presentationMode: OrganizationPresentationMode = .public
    ) {
        self.viewModel = viewModel
        self.onOrganizationSaved = onOrganizationSaved
        self.onOrganizationDeleted = onOrganizationDeleted
        self.presentationMode = presentationMode
        _heroBannerViewModel = StateObject(wrappedValue: AppHeroBannerViewModel(
            section: .organizations,
            bannerService: bannerService
        ))
    }

    private var errorText: String {
        switch viewModel.error {
        case .network:
            AppStrings.Organizations.loadNetworkError
        case .permissionDenied:
            AppStrings.Organizations.loadPermissionError
        case .validationFailed:
            AppStrings.Organizations.loadValidationError
        case .notFound:
            AppStrings.Organizations.empty
        case .unknown:
            AppStrings.Organizations.loadUnknownError
        case nil:
            ""
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.eventsHeaderContentSpacing) {
                organizationsHeader

                organizationsHero

                OrganizationFiltersSection(
                    selectedCategory: selectedCategory,
                    selectedFederalState: selectedFederalState,
                    savedFilterMode: savedFilterMode,
                    onSelectCategory: { selectedCategory = $0 },
                    onSelectRegion: { isRegionPickerPresented = true },
                    onToggleSubscribed: { toggleSavedFilterMode(.subscribed) },
                    onToggleBookmarked: { toggleSavedFilterMode(.bookmarked) }
                )

                AppGroupedContentPlane {
                    organizationsPlaneContent
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.bottom, AppTheme.homeBottomContentPadding)
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: OrganizationNavigationRoute.self) { route in
            OrganizationDetailView(
                viewModel: viewModel,
                organizationID: route.organizationID,
                onOrganizationSaved: onOrganizationSaved,
                onOrganizationDeleted: onOrganizationDeleted
            )
            .environment(\.organizationPresentationMode, presentationMode)
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
                await updateOrganizationsBanner(from: newItem)
                selectedBannerPhoto = nil
            }
        }
        .onChange(of: authState.user?.selectedFederalState) { _, newRegion in
            guard !didManuallyChangeRegion else { return }
            selectedFederalState = newRegion
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .confirmationDialog(AppStrings.Home.regionAllAustria, isPresented: $isRegionPickerPresented, titleVisibility: .visible) {
            Button(AppStrings.Home.regionAllAustria) {
                selectRegion(nil)
            }

            ForEach(AustrianFederalState.organizationFilterOrder, id: \.self) { federalState in
                Button(federalState.organizationFilterDisplayName) {
                    selectRegion(federalState)
                }
            }

            Button(AppStrings.Events.cancel, role: .cancel) {}
        }
        .confirmationDialog(
            AppStrings.Organizations.deleteConfirmation,
            isPresented: Binding(
                get: { pendingDeleteOrganizationID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteOrganizationID = nil
                    }
                }
            )
        ) {
            Button(AppStrings.Organizations.delete, role: .destructive) {
                guard let organizationID = pendingDeleteOrganizationID else { return }
                Task {
                    do {
                        try await viewModel.deleteOrganization(id: organizationID, user: authState.user)
                        viewModel.removeDeletedOrganization(id: organizationID)
                        onOrganizationDeleted()
                    } catch let appError as AppError {
                        deleteErrorMessage = readableOrganizationErrorText(appError)
                        isShowingDeleteError = true
                    } catch {
                        deleteErrorMessage = readableOrganizationErrorText(.unknown)
                        isShowingDeleteError = true
                    }
                    pendingDeleteOrganizationID = nil
                }
            }
            Button(AppStrings.Organizations.cancel, role: .cancel) {
                pendingDeleteOrganizationID = nil
            }
        }
        .alert(AppStrings.Organizations.deleteFailed, isPresented: $isShowingDeleteError) {
            Button(AppStrings.Organizations.dismissError) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? readableOrganizationErrorText(.unknown))
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

    private var organizationsHeader: some View {
        AppBrandHeader {
            HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                AppNotificationBellButton()
            }
        }
    }

    private var organizationsHero: some View {
        ZStack(alignment: .bottomTrailing) {
            AppHeroBanner(
                title: AppStrings.Organizations.heroTitle,
                subtitle: AppStrings.Organizations.heroSubtitle,
                imageSource: heroBannerViewModel.imageSource,
                height: AppTheme.organizationsHeroHeight,
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

    private func updateOrganizationsBanner(from item: PhotosPickerItem?) async {
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
    private var organizationsPlaneContent: some View {
        if viewModel.organizations.isEmpty && viewModel.isLoading {
            LoadingStateCard(title: nil)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.organizations.isEmpty && viewModel.error != nil {
            ErrorStateCard(
                systemImage: "building.2",
                title: AppStrings.Organizations.title,
                message: errorText,
                retryTitle: AppStrings.Organizations.retry
            ) {
                Task {
                    await viewModel.refresh()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.organizations.isEmpty {
            EmptyStateCard(
                systemImage: "building.2",
                title: AppStrings.Organizations.title,
                message: AppStrings.Organizations.empty
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if filteredOrganizations.isEmpty {
            EmptyStateCard(
                systemImage: "line.3.horizontal.decrease.circle",
                title: AppStrings.Organizations.title,
                message: filteredEmptyMessage
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                if viewModel.error != nil {
                    ErrorStateCard(
                        title: AppStrings.Organizations.title,
                        message: errorText,
                        retryTitle: AppStrings.Organizations.retry
                    ) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                }

                DashboardSectionHeader(title: AppStrings.Organizations.popularTitle)

                DashboardFeedContainer(items: filteredOrganizations, spacing: AppTheme.feedRowSpacing) { organization in
                    organizationLink(for: organization)
                }
            }
        }
    }

    private var filteredOrganizations: [Organization] {
        viewModel.organizations.filter { organization in
            selectedCategory.matches(organization)
                && matchesSelectedRegion(organization)
                && matchesSavedFilterMode(organization)
        }
    }

    private var filteredEmptyMessage: String {
        if savedFilterMode == .bookmarked {
            return AppStrings.Organizations.emptyBookmarked
        }
        if savedFilterMode == .subscribed {
            return AppStrings.Home.emptySubscribed
        }
        return AppStrings.Organizations.empty
    }

    private func matchesSelectedRegion(_ organization: Organization) -> Bool {
        guard let selectedFederalState else { return true }
        return organization.federalState == selectedFederalState
    }

    private func matchesSavedFilterMode(_ organization: Organization) -> Bool {
        switch savedFilterMode {
        case .none:
            return true
        case .subscribed:
            guard authState.isAuthenticated else { return false }
            return organization.isSubscribed
        case .bookmarked:
            guard authState.isAuthenticated else { return false }
            return organization.isBookmarked
        }
    }

    private func toggleSavedFilterMode(_ mode: OrganizationSavedFilterMode) {
        savedFilterMode = savedFilterMode == mode ? .none : mode
    }

    private func selectRegion(_ federalState: AustrianFederalState?) {
        selectedFederalState = federalState
        didManuallyChangeRegion = true
    }

    private func applyDefaultRegion() {
        guard !didManuallyChangeRegion else { return }
        selectedFederalState = authState.user?.selectedFederalState
    }

    private func organizationLink(for organization: Organization) -> some View {
        NavigationLink(value: OrganizationNavigationRoute(organizationID: organization.id)) {
            OrganizationCard(organization: organization)
        }
        .buttonStyle(.plain)
        .modifier(OrganizationDeleteSwipeActions(
            isEnabled: presentationMode.allowsManagementControls
                && !organization.isSystemOrganization
                && PermissionService.canDeleteOrganization(user: authState.user),
            onDelete: {
                pendingDeleteOrganizationID = organization.id
            }
        ))
    }
}

private func readableOrganizationErrorText(_ error: AppError?) -> String {
    switch error {
    case .network:
        AppStrings.Organizations.loadNetworkError
    case .permissionDenied:
        AppStrings.Organizations.actionPermissionError
    case .validationFailed:
        AppStrings.Organizations.actionValidationError
    case .notFound:
        AppStrings.Organizations.actionNotFoundError
    case .unknown:
        AppStrings.Organizations.actionUnknownError
    case nil:
        AppStrings.Organizations.actionUnknownError
    }
}

private struct OrganizationCard: View {
    let organization: Organization

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                AppFeedThumbnail(
                    imageURL: organization.imageURL,
                    fallbackSystemImage: "building.2",
                    tint: AppTheme.accentPrimary,
                    fill: AppTheme.badgeBlueFill,
                    size: thumbnailSize,
                    cornerRadius: AppTheme.feedThumbnailRadius,
                    source: "OrganizationCard"
                )
                .frame(width: thumbnailSize, height: thumbnailSize, alignment: .center)

                VStack(alignment: .leading, spacing: 6) {
                    Text(organization.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(organization.shortDescription)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.82))
                        .lineLimit(2)

                    organizationMetadataChips
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var thumbnailSize: CGFloat {
        AppTheme.organizationsThumbnailSize + 12
    }

    private var organizationMetadataChips: some View {
        AppHorizontalChipRow(spacing: 6) {
            ForEach(metadataItems, id: \.title) { item in
                AppInfoChip(
                    title: item.title,
                    systemImage: item.systemImage,
                    tint: AppTheme.textSecondary,
                    fill: AppTheme.surfaceControl.opacity(0.62),
                    size: .small
                )
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var metadataItems: [(title: String, systemImage: String)] {
        var items: [(title: String, systemImage: String)] = []

        if let region = regionText {
            items.append((region, "mappin.and.ellipse"))
        }

        items.append((organizationCategoryText, "building.2"))
        return items
    }

    private var accessibilitySummary: String {
        [
            organization.name,
            organization.shortDescription,
            regionText ?? organization.city,
            organizationCategoryText
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private var regionText: String? {
        if let federalState = organization.federalState {
            return AppStrings.FederalStates.title(for: federalState)
        }

        let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)
        return city.isEmpty ? nil : city
    }

    private var organizationCategoryText: String {
        guard let organizationType = organization.organizationType,
              let category = OrganizationEditorCategory(rawValue: organizationType) else {
            return AppStrings.Organizations.detailBadge
        }

        return category.title
    }

}

private struct OrganizationFiltersSection: View {
    let selectedCategory: OrganizationCategoryFilter
    let selectedFederalState: AustrianFederalState?
    let savedFilterMode: OrganizationSavedFilterMode
    let onSelectCategory: (OrganizationCategoryFilter) -> Void
    let onSelectRegion: () -> Void
    let onToggleSubscribed: () -> Void
    let onToggleBookmarked: () -> Void

    var body: some View {
        AppHorizontalFilterRow {
            Menu {
                ForEach(OrganizationCategoryFilter.allCases) { category in
                    Button {
                        onSelectCategory(category)
                    } label: {
                        Label(category.title, systemImage: category.systemImage ?? "tag")
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
                    title: selectedFederalState?.organizationFilterDisplayName ?? AppStrings.Home.regionAllAustria,
                    systemImage: "mappin.and.ellipse",
                    isSelected: selectedFederalState != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)

            Button(action: onToggleSubscribed) {
                AppFilterChip(
                    title: AppStrings.Home.filterSubscribed,
                    systemImage: "person.2.fill",
                    isSelected: savedFilterMode == .subscribed
                )
            }
            .buttonStyle(.plain)

            Button(action: onToggleBookmarked) {
                AppFilterChip(
                    title: AppStrings.Organizations.filterBookmarks,
                    systemImage: "bookmark",
                    isSelected: savedFilterMode == .bookmarked
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private extension AustrianFederalState {
    static var organizationFilterOrder: [AustrianFederalState] {
        [
            .tirol,
            .wien,
            .niederoesterreich,
            .oberoesterreich,
            .salzburg,
            .steiermark,
            .kaernten,
            .vorarlberg,
            .burgenland
        ]
    }

    var organizationFilterDisplayName: String {
        switch self {
        case .tirol:
            "Tirol"
        case .wien:
            "Wien"
        case .niederoesterreich:
            "Niederösterreich"
        case .oberoesterreich:
            "Oberösterreich"
        case .salzburg:
            "Salzburg"
        case .steiermark:
            "Steiermark"
        case .kaernten:
            "Kärnten"
        case .vorarlberg:
            "Vorarlberg"
        case .burgenland:
            "Burgenland"
        }
    }
}

struct OrganizationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.organizationPresentationMode) private var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: OrganizationsViewModel
    let organizationID: String
    let onOrganizationSaved: @MainActor () async -> Void
    let onOrganizationDeleted: @MainActor () -> Void
    let onNavigateBack: (() -> Void)?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var pendingRemovalOrganizationID: String?
    @State private var guestAccessAction: GuestAccessAction?
    @State private var isAboutExpanded = false
    @State private var selectedSection: OrganizationDetailSection = .about
    @State private var recordedRecentViewKeys = Set<String>()
    @State private var previewPhotos: [OrganizationPhoto] = []
    @State private var loadedPreviewPhotoOrganizationID: String?
    @State private var communityMembers: [OrganizationCommunityMember] = []
    @State private var communitySubscriberReferences: [OrganizationSubscriberReference] = []
    @State private var communitySubscriberCursor: OrganizationSubscriberCursor?
    @State private var hasMoreCommunitySubscribers = false
    @State private var isLoadingCommunityPage = false
    @State private var loadedCommunityOrganizationID: String?
    @State private var commentText = ""
    @State private var editingCommentID: String?
    @State private var pendingCommentDeleteID: String?
    @State private var commentDeleteErrorMessage: String?
    @StateObject private var activityViewModel: OrganizationActivityViewModel
    @StateObject private var newsDetailViewModel: NewsViewModel
    @StateObject private var eventsDetailViewModel: EventsViewModel
    @FocusState private var isCommentFieldFocused: Bool
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let photoRepository: OrganizationPhotoRepository
    private let heroLogoSize: CGFloat = 104
    private let detailCardPadding: CGFloat = 14
    private let detailCardRadius: CGFloat = 18
    private let detailSectionSpacing: CGFloat = 13
    private let communityPageSize = 50

    init(
        viewModel: OrganizationsViewModel,
        organizationID: String,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        photoRepository: OrganizationPhotoRepository = FirestoreOrganizationPhotoRepository(),
        onOrganizationSaved: @escaping @MainActor () async -> Void = {},
        onOrganizationDeleted: @escaping @MainActor () -> Void = {},
        onNavigateBack: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.organizationID = organizationID
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.photoRepository = photoRepository
        self.onOrganizationSaved = onOrganizationSaved
        self.onOrganizationDeleted = onOrganizationDeleted
        self.onNavigateBack = onNavigateBack
        _activityViewModel = StateObject(wrappedValue: OrganizationActivityViewModel(
            organizationID: organizationID,
            organizationName: "",
            newsRepository: newsRepository,
            eventRepository: eventRepository
        ))
        _newsDetailViewModel = StateObject(wrappedValue: NewsViewModel(repository: newsRepository))
        _eventsDetailViewModel = StateObject(wrappedValue: EventsViewModel(repository: eventRepository))
    }

    private var isDeletingCurrentOrganization: Bool {
        viewModel.pendingOrganizationDeleteIDs.contains(organizationID)
    }

    var body: some View {
        Group {
            if let organization = viewModel.organization(for: organizationID) {
                GeometryReader { proxy in
                    let contentHorizontalPadding = AppTheme.pageHorizontal
                    let contentWidth = max(proxy.size.width - (contentHorizontalPadding * 2), 0)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: detailSectionSpacing) {
                            detailHeader(for: organization)

                            organizationHero(for: organization)
                                .onTapGesture { isCommentFieldFocused = false }
                            heroMetadata(for: organization)
                                .onTapGesture { isCommentFieldFocused = false }
                            supportCard(for: organization)
                                .onTapGesture { isCommentFieldFocused = false }
                            organizationSectionTabs
                                .onTapGesture { isCommentFieldFocused = false }
                            selectedSectionContent(for: organization)
                                .onTapGesture { isCommentFieldFocused = false }
                            actionButtons(for: organization)
                                .onTapGesture { isCommentFieldFocused = false }
                            commentsSection(for: organization)
                                .id("organizationCommentsSection")
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(.horizontal, contentHorizontalPadding)
                        .padding(.bottom, AppTheme.homeBottomContentPadding + 160)
                    }
                    .frame(width: proxy.size.width)
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        await refreshOrganizationDetail(for: organization)
                    }
                }
                .task(id: organization.id) {
                    await activityViewModel.loadIfNeeded(for: organization)
                    await newsDetailViewModel.loadIfNeeded()
                    await eventsDetailViewModel.loadIfNeeded()
                    await viewModel.loadComments(for: organization.id)
                    await loadPreviewPhotosIfNeeded(for: organization.id)
                    await loadCommunityMembersIfNeeded(for: organization)
                    recordRecentView(for: organization)
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .background(AppBackgroundView().allowsHitTesting(false))
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppStrings.Common.done) {
                    isCommentFieldFocused = false
                }
            }
        }
        .confirmationDialog(AppStrings.Organizations.deleteConfirmation, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(AppStrings.Organizations.delete, role: .destructive) {
                guard !isDeletingCurrentOrganization else { return }
                Task {
                    await deleteCurrentOrganization()
                }
            }
            Button(AppStrings.Organizations.cancel, role: .cancel) {}
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
            Button(AppStrings.Organizations.cancel, role: .cancel) {
                pendingCommentDeleteID = nil
            }
        }
        .alert(AppStrings.Organizations.deleteFailed, isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button(AppStrings.Organizations.dismissError, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert(AppStrings.Common.deleteCommentFailed, isPresented: Binding(
            get: { commentDeleteErrorMessage != nil },
            set: { if !$0 { commentDeleteErrorMessage = nil } }
        )) {
            Button(AppStrings.Organizations.dismissError, role: .cancel) {}
        } message: {
            Text(commentDeleteErrorMessage ?? readableOrganizationErrorText(.unknown))
        }
        .guestAccessAlert($guestAccessAction)
        .onChange(of: authState.user?.id) { _, _ in
            guard let organization = viewModel.organization(for: organizationID) else { return }
            recordRecentView(for: organization)
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            Task {
                await viewModel.refresh()
                if let organization = viewModel.organization(for: organizationID) {
                    await activityViewModel.refresh(for: organization)
                    await reloadCommunityMembers(for: organization)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            guard let organization = viewModel.organization(for: organizationID) else { return }
            Task {
                await activityViewModel.refresh(for: organization)
                await newsDetailViewModel.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            guard let organization = viewModel.organization(for: organizationID) else { return }
            Task {
                await activityViewModel.refresh(for: organization)
                await eventsDetailViewModel.refresh()
            }
        }
        .onDisappear {
            viewModel.stopListeningComments(for: organizationID)
            guard let pendingRemovalOrganizationID else { return }
            withTransaction(Transaction(animation: nil)) {
                viewModel.removeDeletedOrganization(id: pendingRemovalOrganizationID)
            }
            self.pendingRemovalOrganizationID = nil
        }
    }

    private func recordRecentView(for organization: Organization) {
        guard authState.user != nil else { return }
        let key = "\(organization.id)-\(authState.user?.id ?? "guest")"
        guard !recordedRecentViewKeys.contains(key) else { return }
        recordedRecentViewKeys.insert(key)
        RecentViewRecorder.recordOrganization(organization)
    }

    @MainActor
    private func loadPreviewPhotosIfNeeded(for organizationID: String) async {
        guard loadedPreviewPhotoOrganizationID != organizationID else { return }
        loadedPreviewPhotoOrganizationID = organizationID

        do {
            previewPhotos = try await photoRepository.fetchPhotos(organizationId: organizationID)
        } catch {
            previewPhotos = []
        }
    }

    @MainActor
    private func reloadPreviewPhotos(for organizationID: String) async {
        loadedPreviewPhotoOrganizationID = nil
        previewPhotos = []
        await loadPreviewPhotosIfNeeded(for: organizationID)
    }

    @MainActor
    private func refreshOrganizationDetail(for organization: Organization) async {
        await viewModel.refresh()
        let refreshedOrganization = viewModel.organization(for: organization.id) ?? organization
        await activityViewModel.refresh(for: refreshedOrganization)
        await newsDetailViewModel.refresh()
        await eventsDetailViewModel.refresh()
        await viewModel.loadComments(for: refreshedOrganization.id)
        await reloadPreviewPhotos(for: refreshedOrganization.id)
        await reloadCommunityMembers(for: refreshedOrganization)
    }

    @MainActor
    private func loadCommunityMembersIfNeeded(for organization: Organization) async {
        guard loadedCommunityOrganizationID != organization.id else { return }
        loadedCommunityOrganizationID = organization.id
        communityMembers = []
        communitySubscriberReferences = []
        communitySubscriberCursor = nil
        hasMoreCommunitySubscribers = false
        await loadCommunityMembersPage(for: organization, reset: true)
    }

    @MainActor
    private func reloadCommunityMembers(for organization: Organization) async {
        loadedCommunityOrganizationID = nil
        communityMembers = []
        communitySubscriberReferences = []
        communitySubscriberCursor = nil
        hasMoreCommunitySubscribers = false
        await loadCommunityMembersIfNeeded(for: organization)
    }

    @MainActor
    private func loadCommunityMembersPage(for organization: Organization, reset: Bool) async {
        guard !isLoadingCommunityPage else { return }
        isLoadingCommunityPage = true
        defer { isLoadingCommunityPage = false }

        let roleByUserID = communityRoleMap(for: organization)
        let roleUserIDs = Array(roleByUserID.keys)

        do {
            let page = try await organizationRepository.fetchOrganizationSubscriberPage(
                organizationID: organization.id,
                limit: communityPageSize,
                after: reset ? nil : communitySubscriberCursor
            )
            communitySubscriberCursor = page.nextCursor
            hasMoreCommunitySubscribers = page.hasMore
            mergeCommunitySubscriberReferences(page.items, reset: reset)
        } catch {
            if reset {
                communitySubscriberReferences = []
                communitySubscriberCursor = nil
                hasMoreCommunitySubscribers = false
            }
        }

        let followedAtByUserID = Dictionary(uniqueKeysWithValues: communitySubscriberReferences.map { ($0.userID, $0.followedAt) })
        let userIDs = Array(Set(roleUserIDs + communitySubscriberReferences.map(\.userID)))

        do {
            let profiles = try await organizationRepository.fetchPublicUserProfiles(userIDs: userIDs)
            var loadedProfileIDs = Set<String>()
            var members: [OrganizationCommunityMember] = []
            for profile in profiles {
                loadedProfileIDs.insert(profile.id)
                members.append(OrganizationCommunityMember(
                    profile: profile,
                    role: roleByUserID[profile.id] ?? .subscriber,
                    followedAt: followedAtByUserID[profile.id] ?? nil,
                    isPlaceholder: false
                ))
            }

            let missingRoleMembers = roleByUserID
                .filter { userID, _ in !loadedProfileIDs.contains(userID) }
                .map { userID, role in
                    OrganizationCommunityMember(
                        profile: PublicUserProfile(
                            id: userID,
                            displayName: AppStrings.Organizations.communityProfileUnavailable,
                            avatarURL: nil,
                            city: "",
                            federalState: nil,
                            updatedAt: nil
                        ),
                        role: role,
                        followedAt: followedAtByUserID[userID] ?? nil,
                        isPlaceholder: true
                    )
                }

            members.append(contentsOf: missingRoleMembers)
            communityMembers = members.sorted(by: communityMemberSort)
        } catch {
            communityMembers = roleByUserID.map { userID, role in
                OrganizationCommunityMember(
                    profile: PublicUserProfile(
                        id: userID,
                        displayName: AppStrings.Organizations.communityProfileUnavailable,
                        avatarURL: nil,
                        city: "",
                        federalState: nil,
                        updatedAt: nil
                    ),
                    role: role,
                    followedAt: nil,
                    isPlaceholder: true
                )
            }
            .sorted(by: communityMemberSort)
        }
    }

    @MainActor
    private func mergeCommunitySubscriberReferences(_ references: [OrganizationSubscriberReference], reset: Bool) {
        if reset {
            communitySubscriberReferences = []
        }

        var seenUserIDs = Set(communitySubscriberReferences.map(\.userID))
        let newReferences = references.filter { reference in
            seenUserIDs.insert(reference.userID).inserted
        }
        communitySubscriberReferences.append(contentsOf: newReferences)
    }

    private func detailHeader(for organization: Organization) -> some View {
        AppCenteredBrandHeader {
            AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                if let onNavigateBack {
                    onNavigateBack()
                } else {
                    dismiss()
                }
            }
        } trailingContent: {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                Button {
                    toggleBookmark(for: organization)
                } label: {
                    organizationHeaderBookmarkIcon(for: organization)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.pendingOrganizationBookmarkIDs.contains(organization.id))
                .accessibilityLabel(organization.isBookmarked ? AppStrings.Organizations.removeBookmark : AppStrings.Organizations.addBookmark)

                ShareLink(item: organizationShareText(for: organization)) {
                    organizationHeaderShareIcon
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.Action.share)
            }
        }
    }

    private func organizationHeaderBookmarkIcon(for organization: Organization) -> some View {
        Image(systemName: organization.isBookmarked ? "bookmark.fill" : "bookmark")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
            .frame(width: AppTheme.iconButtonSize, height: AppTheme.iconButtonSize)
            .background(
                reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
            )
            .background {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
            )
            .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: 5, y: 2)
    }

    private var organizationHeaderShareIcon: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
            .frame(width: AppTheme.iconButtonSize, height: AppTheme.iconButtonSize)
            .background(
                reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
            )
            .background {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
            )
            .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: 5, y: 2)
    }

    private func organizationShareText(for organization: Organization) -> String {
        var parts = [organization.name]
        if let description = heroDescription(for: organization) {
            parts.append(description)
        }
        if let website = organizationWebsiteDisplayText(for: organization) {
            parts.append(website)
        }
        return parts.joined(separator: "\n")
    }

    private func toggleBookmark(for organization: Organization) {
        guard authState.isAuthenticated else {
            guestAccessAction = .bookmarks
            return
        }

        viewModel.toggleBookmark(for: organization.id)
    }

    private func organizationHero(for organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                organizationLogo(for: organization)
                    .frame(width: heroLogoSize, height: heroLogoSize)
                    .layoutPriority(1)

                heroText(for: organization)
                    .frame(minHeight: heroLogoSize, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func organizationLogo(for organization: Organization) -> some View {
        Group {
            if let logoURL = organization.logoURL ?? organization.imageURL {
                RemoteImageView(
                    imageURL: logoURL,
                    height: heroLogoSize,
                    cornerRadius: AppTheme.imageRadius,
                    source: "OrganizationDetailView",
                    placeholderStyle: .glassSkeleton
                )
            } else {
                RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                    .fill(AppTheme.glassControlSurface(for: colorScheme))
                    .overlay(
                        Text(organizationInitials(for: organization))
                            .font(.title.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimary)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
        .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: 6, y: 3)
        .accessibilityLabel(AppStrings.Organizations.imageSectionTitle)
    }

    private func heroText(for organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    if organization.isSystemOrganization {
                        organizationHeroChip(title: AppStrings.Organizations.officialBadge, systemImage: "checkmark.seal.fill")
                    }
                    organizationHeroChip(title: organizationTypeTitle(for: organization), systemImage: "building.2")
                }

                VStack(alignment: .leading, spacing: 6) {
                    if organization.isSystemOrganization {
                        organizationHeroChip(title: AppStrings.Organizations.officialBadge, systemImage: "checkmark.seal.fill")
                    }
                    organizationHeroChip(title: organizationTypeTitle(for: organization), systemImage: "building.2")
                }
            }

            Text(organization.name)
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(AppTheme.accentPrimary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            if let description = heroDescription(for: organization) {
                Text(description)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func organizationHeroChip(title: String, systemImage: String) -> some View {
        AppInfoChip(
            title: title.uppercased(),
            systemImage: systemImage,
            tint: AppTheme.accentPrimary,
            fill: AppTheme.accentPrimary.opacity(0.14),
            border: AppTheme.accentPrimary.opacity(0.18),
            size: .small
        )
    }

    private func heroMetadata(for organization: Organization) -> some View {
        AppHorizontalChipRow(spacing: 6) {
            ForEach(heroMetadataItems(for: organization), id: \.0) { systemImage, text in
                ContentMetadataPill(systemImage: systemImage, text: text)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    @MainActor
    private func heroMetadataItems(for organization: Organization) -> [(String, String)] {
        var items: [(String, String)] = [
            ("hand.thumbsup", "\(organization.likeCount)"),
            ("person.2", subscriberCountText(for: organization.subscriberCount))
        ]

        if let location = detailedLocationText(for: organization) {
            items.append(("mappin.and.ellipse", location))
        }

        return items
    }

    private func subscriberCountText(for count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        let suffix: String

        if mod10 == 1 && mod100 != 11 {
            suffix = AppStrings.Home.subscriberSuffixOne
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            suffix = AppStrings.Home.subscriberSuffixFew
        } else {
            suffix = AppStrings.Home.subscriberSuffixMany
        }

        return "\(count) \(suffix)"
    }

    private func compactLocationText(for organization: Organization) -> String? {
        let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)
        if !city.isEmpty {
            return city
        }

        if let federalState = organization.federalState {
            return AppStrings.FederalStates.title(for: federalState)
        }

        return nil
    }

    @MainActor
    private func detailedLocationText(for organization: Organization) -> String? {
        let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let federalState = organization.federalState.map(AppStrings.FederalStates.title(for:))

        if !city.isEmpty, let federalState {
            return "\(city), \(federalState)"
        }
        if !city.isEmpty {
            return city
        }
        return federalState
    }

    private func heroDescription(for organization: Organization) -> String? {
        let shortDescription = organization.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return shortDescription.isEmpty ? nil : shortDescription
    }

    private func actionButtons(for organization: Organization) -> some View {
        detailGlassCard(padding: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    engagementMetrics(for: organization)
                    Spacer(minLength: 0)
                    subscribeButton(for: organization)
                }

                VStack(alignment: .leading, spacing: 10) {
                    engagementMetrics(for: organization)
                    subscribeButton(for: organization)
                }
            }
        }
    }

    @ViewBuilder
    private func supportCard(for organization: Organization) -> some View {
        if let donationURL = normalizedOrganizationURL(from: organization.donationURL) {
            detailGlassCard(padding: 12) {
                Link(destination: donationURL) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimary)
                            .frame(width: 36, height: 36)
                            .background(
                                reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(AppStrings.Organizations.supportOrganizationTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text(AppStrings.Organizations.supportOrganizationSubtitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.Organizations.supportOrganizationTitle)
            }
        }
    }

    private func engagementMetrics(for organization: Organization) -> some View {
        HStack(spacing: 8) {
            detailMetricButton(
                systemImage: organization.likeState.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                count: organization.likeCount,
                accessibilityLabel: organization.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like,
                isSelected: organization.likeState.isLiked
            ) {
                toggleLike(for: organization)
            }
            .disabled(viewModel.pendingOrganizationLikeIDs.contains(organization.id))

            detailMetricButton(
                systemImage: "bubble.left",
                count: viewModel.comments(for: organization.id).count,
                accessibilityLabel: AppStrings.Common.comments
            ) {
                isCommentFieldFocused = true
            }
        }
    }

    private func subscribeButton(for organization: Organization) -> some View {
        organizationActionButton(
            title: organization.isSubscribed ? AppStrings.Organizations.unfollow : AppStrings.Organizations.follow,
            systemImage: organization.isSubscribed ? "person.2.fill" : "person.2.badge.plus",
            isPrimary: true,
            isDestructive: organization.isSubscribed,
            isDisabled: viewModel.pendingOrganizationSubscriptionIDs.contains(organization.id)
        ) {
            toggleSubscription(for: organization)
        }
        .frame(maxWidth: 180)
    }

    private func toggleLike(for organization: Organization) {
        guard authState.isAuthenticated else {
            guestAccessAction = .likes
            return
        }

        viewModel.toggleLike(for: organization.id)
    }

    private func toggleSubscription(for organization: Organization) {
        guard authState.isAuthenticated else {
            guestAccessAction = .likes
            return
        }

        viewModel.toggleSubscription(for: organization.id)
    }

    private func detailMetricButton(
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

    private func organizationLinkButton(title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.dashboardSpacing)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.iconButtonSize)
                .background(
                    reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                )
                .background {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func organizationActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool = false,
        isDestructive: Bool = false,
        isPlaceholder: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void = {}
    ) -> some View {
        let isInteractionDisabled = isPlaceholder || isDisabled
        let foregroundColor: Color = {
            if isDestructive {
                return AppTheme.accentDestructive
            }
            return isPrimary ? .white : AppTheme.textPrimary
        }()
        let backgroundColor: Color = {
            if isDestructive {
                return AppTheme.badgeRedFill.opacity(isInteractionDisabled ? 0.62 : 1)
            }
            if isPrimary {
                return AppTheme.accentPrimary.opacity(isInteractionDisabled ? 0.78 : 1)
            }
            return reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme)
        }()
        let borderColor: Color = {
            if isDestructive {
                return AppTheme.accentDestructive.opacity(isInteractionDisabled ? 0.24 : 0.38)
            }
            return isPrimary ? Color.white.opacity(0.18) : AppTheme.glassBorder(for: colorScheme)
        }()

        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, AppTheme.dashboardSpacing)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.iconButtonSize)
                .background(
                    backgroundColor,
                    in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                )
                .background {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .strokeBorder(borderColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(isInteractionDisabled)
        .accessibilityHint(isPlaceholder ? AppStrings.Action.comingSoon : "")
    }

    private var organizationSectionTabs: some View {
        AppHorizontalFilterRow {
            ForEach(OrganizationDetailSection.allCases) { section in
                Button {
                    withAnimation(.snappy) {
                        selectedSection = section
                    }
                } label: {
                    AppFilterChip(
                        title: section.title,
                        systemImage: section.systemImage,
                        isSelected: selectedSection == section
                    )
                    .frame(height: AppTheme.iconButtonSize)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func selectedSectionContent(for organization: Organization) -> some View {
        switch selectedSection {
        case .events:
            organizationActivityList(
                title: AppStrings.Organizations.tabEvents,
                items: upcomingOrganizationEvents,
                emptySystemImage: "calendar",
                emptyMessage: AppStrings.Organizations.emptyOrganizationEvents,
                sortAscending: true
            )
        case .news:
            organizationActivityList(
                title: AppStrings.Organizations.tabNews,
                items: organizationNewsItems,
                emptySystemImage: "newspaper",
                emptyMessage: AppStrings.Organizations.emptyOrganizationNews,
                sortAscending: false
            )
        case .about:
            aboutCard(for: organization)
        case .contacts:
            contactCard(for: organization)
        case .team:
            organizationTeamSection
        case .photos:
            OrganizationPhotoGallerySection(
                organizationId: organization.id,
                canManage: false,
                currentUser: authState.user
            )
        }
    }

    private var upcomingOrganizationEvents: [OrganizationActivityItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return organizationEventItems
            .filter { ($0.eventStartDate ?? $0.publishedAt) >= today }
            .sorted { ($0.eventStartDate ?? $0.publishedAt) < ($1.eventStartDate ?? $1.publishedAt) }
    }

    private var organizationEventItems: [OrganizationActivityItem] {
        activityViewModel.items
            .filter { $0.itemType == .event }
            .sorted { ($0.eventStartDate ?? $0.publishedAt) < ($1.eventStartDate ?? $1.publishedAt) }
    }

    private var organizationNewsItems: [OrganizationActivityItem] {
        activityViewModel.items
            .filter { $0.itemType == .news }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    private func organizationActivityList(
        title: String,
        items: [OrganizationActivityItem],
        emptySystemImage: String,
        emptyMessage: String,
        sortAscending: Bool
    ) -> some View {
        Group {
            if activityViewModel.isLoading && activityViewModel.items.isEmpty {
                LoadingStateCard(title: nil)
            } else if activityViewModel.items.isEmpty && activityViewModel.error != nil {
                ErrorStateCard(
                    systemImage: "building.2",
                    title: AppStrings.Organizations.activityTitle,
                    message: readableOrganizationErrorText(activityViewModel.error),
                    retryTitle: AppStrings.Organizations.retry
                ) {
                    Task {
                        if let organization = viewModel.organization(for: organizationID) {
                            await activityViewModel.refresh(for: organization)
                        }
                    }
                }
            } else if items.isEmpty {
                organizationCompactPlaceholder(
                    systemImage: emptySystemImage,
                    title: title,
                    message: emptyMessage
                )
            } else {
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                        AppEditorSectionTitle(title: title)

                        ForEach(items) { item in
                            if let destination = item.destination {
                                NavigationLink {
                                    activityDestinationView(for: destination)
                                } label: {
                                    OrganizationActivityCompactCard(item: item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                OrganizationActivityCompactCard(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var organizationTeamSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
            detailGlassCard(padding: detailCardPadding) {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    sectionHeader(title: AppStrings.Organizations.tabTeam, systemImage: "person.3")

                    if communityMembers.isEmpty {
                        communityEmptyState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(communityMembers) { member in
                                organizationCommunityRow(member)

                                if member.id != communityMembers.last?.id {
                                    Divider()
                                        .overlay(AppTheme.borderSubtle.opacity(0.55))
                                        .padding(.leading, 54)
                                }
                            }
                        }

                        if hasMoreCommunitySubscribers || isLoadingCommunityPage {
                            communityLoadMoreButton
                        }
                    }

                }
            }
        }
    }

    private var communityEmptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 36, height: 36)
                .background(AppTheme.glassControlSurface(for: colorScheme), in: Circle())

            Text(AppStrings.Organizations.communityEmpty)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var communityLoadMoreButton: some View {
        Button {
            guard let organization = viewModel.organization(for: organizationID) else { return }
            Task {
                await loadCommunityMembersPage(for: organization, reset: false)
            }
        } label: {
            HStack(spacing: 8) {
                if isLoadingCommunityPage {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }

                Text(AppStrings.Organizations.communityLoadMore)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(AppTheme.accentPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.iconButtonSize)
            .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoadingCommunityPage)
        .padding(.top, 10)
    }

    private func organizationCommunityRow(_ member: OrganizationCommunityMember) -> some View {
        HStack(spacing: 12) {
            communityAvatar(for: member.profile)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.profile.preferredDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(member.isPlaceholder ? AppTheme.textSecondary : AppTheme.textPrimary)
                    .lineLimit(1)

                if member.isPlaceholder {
                    Text(AppStrings.Organizations.communityPlaceholderProfileMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                } else if let location = communityLocationText(for: member.profile) {
                    Text(location)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            communityRoleBadge(member.role)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func sectionHeader(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
    }

    private func communityAvatar(for profile: PublicUserProfile) -> some View {
        Group {
            if let avatarURL = profile.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        communityInitialsAvatar(for: profile)
                    }
                }
            } else {
                communityInitialsAvatar(for: profile)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(AppTheme.glassBorder(for: colorScheme)))
    }

    private func communityInitialsAvatar(for profile: PublicUserProfile) -> some View {
        Circle()
            .fill(AppTheme.glassControlSurface(for: colorScheme))
            .overlay(
                Text(communityInitials(for: profile))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)
            )
    }

    private func communityRoleBadge(_ role: OrganizationCommunityRole) -> some View {
        Text(role.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppTheme.accentPrimary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(AppTheme.accentPrimary.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(AppTheme.accentPrimary.opacity(0.22)))
    }

    @MainActor
    private func communityLocationText(for profile: PublicUserProfile) -> String? {
        let city = profile.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = profile.federalState.map(AppStrings.FederalStates.title(for:))

        if !city.isEmpty, let region {
            return "\(city), \(region)"
        }
        if !city.isEmpty {
            return city
        }
        return region
    }

    private func communityInitials(for profile: PublicUserProfile) -> String {
        if profile.displayName == AppStrings.Organizations.communityProfileUnavailable {
            return "?"
        }

        let source = profile.preferredDisplayName
        let parts = source
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let initials = String(parts).uppercased()
        return initials.isEmpty ? "?" : initials
    }

    private func communityRoleMap(for organization: Organization) -> [String: OrganizationCommunityRole] {
        var roles: [String: OrganizationCommunityRole] = [:]

        func assign(_ userID: String?, role: OrganizationCommunityRole) {
            guard let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty else { return }
            guard let existingRole = roles[userID] else {
                roles[userID] = role
                return
            }
            if role.rawValue < existingRole.rawValue {
                roles[userID] = role
            }
        }

        assign(organization.ownerId, role: .owner)
        organization.adminIds.forEach { assign($0, role: .admin) }
        organization.moderatorIds.forEach { assign($0, role: .moderator) }

        return roles
    }

    private func communityMemberSort(_ lhs: OrganizationCommunityMember, _ rhs: OrganizationCommunityMember) -> Bool {
        if lhs.role.rawValue != rhs.role.rawValue {
            return lhs.role.rawValue < rhs.role.rawValue
        }
        if lhs.role == .subscriber, lhs.followedAt != rhs.followedAt {
            return (lhs.followedAt ?? .distantPast) > (rhs.followedAt ?? .distantPast)
        }
        return lhs.profile.preferredDisplayName.localizedCaseInsensitiveCompare(rhs.profile.preferredDisplayName) == .orderedAscending
    }

    private func organizationCompactPlaceholder(systemImage: String, title: String, message: String, badge: String? = nil) -> some View {
        UnifiedEmptyStateCard(systemImage: systemImage, title: title, message: message) {
            if let badge {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(AppTheme.surfaceControl.opacity(0.34), in: Capsule())
                    .overlay(Capsule().strokeBorder(AppTheme.borderSubtle))
            }
        }
    }

    private func aboutCard(for organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
            AppEditorSectionCard {
                aboutTextBlock(for: organization)
            }

            if let missionStatement = organization.missionStatement?.trimmingCharacters(in: .whitespacesAndNewlines), !missionStatement.isEmpty {
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        AppEditorSectionTitle(title: AppStrings.Organizations.detailMissionStatementTitle)
                        Text(missionStatement)
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if hasCommunityHighlights(for: organization) {
                communityHighlightsBlock(for: organization)
            }

            AppEditorSectionCard {
                organizationFactsBlock(for: organization)
            }
        }
    }

    private func hasCommunityHighlights(for organization: Organization) -> Bool {
        highlightedEvent(for: organization) != nil ||
            !highlightedNewsItems(for: organization).isEmpty ||
            !previewPhotos.isEmpty
    }

    private func communityHighlightsBlock(for organization: Organization) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.Organizations.communityHighlightsTitle)

                if let event = highlightedEvent(for: organization) {
                    highlightedEventSection(event)
                }

                let newsItems = highlightedNewsItems(for: organization)
                if !newsItems.isEmpty {
                    highlightedNewsSection(newsItems, organization: organization)
                }

                if !previewPhotos.isEmpty {
                    highlightedPhotosSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func highlightedEventSection(_ item: OrganizationActivityItem) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            organizationHighlightHeader(title: AppStrings.Organizations.nearestEventTitle, actionTitle: AppStrings.Organizations.viewAction) {
                if let destination = item.destination {
                    NavigationLink {
                        activityDestinationView(for: destination)
                    } label: {
                        highlightActionLabel(AppStrings.Organizations.viewAction)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let destination = item.destination {
                NavigationLink {
                    activityDestinationView(for: destination)
                } label: {
                    OrganizationActivityCompactCard(item: item)
                }
                .buttonStyle(.plain)
            } else {
                OrganizationActivityCompactCard(item: item)
            }
        }
    }

    private func highlightedNewsSection(_ items: [OrganizationActivityItem], organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            organizationHighlightHeader(title: AppStrings.Organizations.latestNewsTitle, actionTitle: AppStrings.Organizations.allNewsAction) {
                Button {
                    switchToSection(.news)
                } label: {
                    highlightActionLabel(AppStrings.Organizations.allNewsAction)
                }
                .buttonStyle(.plain)
            }

            ForEach(items) { item in
                if let destination = item.destination {
                    NavigationLink {
                        activityDestinationView(for: destination)
                    } label: {
                        OrganizationActivityCompactCard(item: item, isPinned: isPinnedNews(item, for: organization))
                    }
                    .buttonStyle(.plain)
                } else {
                    OrganizationActivityCompactCard(item: item, isPinned: isPinnedNews(item, for: organization))
                }
            }
        }
    }

    private var highlightedPhotosSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            organizationHighlightHeader(title: AppStrings.Organizations.latestPhotosTitle, actionTitle: AppStrings.Organizations.tabPhoto) {
                Button {
                    switchToSection(.photos)
                } label: {
                    highlightActionLabel(AppStrings.Organizations.tabPhoto)
                }
                .buttonStyle(.plain)
            }

            AppHorizontalChipRow {
                ForEach(Array(previewPhotos.prefix(5))) { photo in
                    Button {
                        switchToSection(.photos)
                    } label: {
                        highlightPhotoTile(photo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func organizationHighlightHeader<Content: View>(
        title: String,
        actionTitle: String,
        @ViewBuilder action: () -> Content
    ) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            action()
                .accessibilityLabel(actionTitle)
        }
    }

    private func highlightActionLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.accentPrimary)
    }

    private func highlightPhotoTile(_ photo: OrganizationPhoto) -> some View {
        AsyncImage(url: URL(string: photo.imageURL)) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                AppTheme.surfaceControl.opacity(0.65)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    )
            default:
                AppTheme.surfaceControl.opacity(0.65)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(width: 86, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.65))
        )
        .accessibilityLabel(photo.caption ?? AppStrings.Organizations.tabPhoto)
    }

    private func switchToSection(_ section: OrganizationDetailSection) {
        withAnimation(.snappy) {
            selectedSection = section
        }
    }

    private func highlightedEvent(for organization: Organization) -> OrganizationActivityItem? {
        if let pinnedEventId = organization.pinnedEventId,
           let pinnedEvent = organizationEventItems.first(where: { destinationID(for: $0) == pinnedEventId }) {
            return pinnedEvent
        }

        return upcomingOrganizationEvents.first
    }

    private func highlightedNewsItems(for organization: Organization) -> [OrganizationActivityItem] {
        var selected: [OrganizationActivityItem] = []

        if let pinnedNewsId = organization.pinnedNewsId,
           let pinnedNews = organizationNewsItems.first(where: { destinationID(for: $0) == pinnedNewsId }) {
            selected.append(pinnedNews)
        }

        for item in organizationNewsItems where selected.count < 2 && !selected.contains(where: { $0.id == item.id }) {
            selected.append(item)
        }

        return selected
    }

    private func isPinnedNews(_ item: OrganizationActivityItem, for organization: Organization) -> Bool {
        guard let pinnedNewsId = organization.pinnedNewsId else { return false }
        return destinationID(for: item) == pinnedNewsId
    }

    private func destinationID(for item: OrganizationActivityItem) -> String? {
        guard let destination = item.destination else { return nil }
        switch destination {
        case let .news(id), let .event(id), let .organization(id):
            return id
        }
    }

    private func aboutTextBlock(for organization: Organization) -> some View {
        let text = meaningfulAboutText(for: organization)

        return VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
            AppEditorSectionTitle(title: AppStrings.Organizations.aboutSectionTitle)

            if let text {
                let collapsedLineLimit = 4
                let isLongText = text.count > 180

                Text(text)
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(4)
                    .lineLimit(isAboutExpanded || !isLongText ? nil : collapsedLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.snappy, value: isAboutExpanded)

                if isLongText {
                    Button {
                        withAnimation(.snappy) {
                            isAboutExpanded.toggle()
                        }
                    } label: {
                        Label(
                            isAboutExpanded ? AppStrings.Organizations.showLess : AppStrings.Organizations.showMore,
                            systemImage: isAboutExpanded ? "chevron.up" : "chevron.down"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(AppStrings.Organizations.aboutEmptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func organizationFactsBlock(for organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
            AppEditorSectionTitle(title: AppStrings.Organizations.mainInformationTitle)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing, alignment: .topLeading),
                    GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing, alignment: .topLeading)
                ],
                alignment: .leading,
                spacing: AppTheme.eventsMetadataSpacing
            ) {
                ForEach(organizationFactItems(for: organization), id: \.title) { item in
                    organizationFactTile(systemImage: item.systemImage, title: item.title, value: item.value)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func organizationFactItems(for organization: Organization) -> [(systemImage: String, title: String, value: String)] {
        var items: [(systemImage: String, title: String, value: String)] = [
            ("building.2", AppStrings.Organizations.categoryTitle, organizationTypeTitle(for: organization))
        ]

        if !organization.languages.isEmpty {
            items.append(("text.bubble", AppStrings.Organizations.languagesTitle, organization.languages.joined(separator: ", ")))
        }

        if let location = detailedLocationText(for: organization) {
            items.append(("mappin.and.ellipse", AppStrings.Organizations.fieldLocation, location))
        }

        if let foundedText = foundedDateText(for: organization) {
            items.append(("calendar", AppStrings.Organizations.foundedTitle, foundedText))
        }

        return items
    }

    private func organizationFactTile(systemImage: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(10)
        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
    }

    @ViewBuilder
    private func contactCard(for organization: Organization) -> some View {
        OrganizationContactCard(
            organization: organization,
            allowsEditing: false,
            showsManagementActions: false,
            onEdit: nil
        )
    }

    private func hasContactInfo(for organization: Organization) -> Bool {
        organizationAddressText(for: organization) != nil ||
            organizationWebsiteDisplayText(for: organization) != nil ||
            organizationContactText(for: organization) != nil ||
            !(organization.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            organizationTelegramURL(for: organization) != nil ||
            organizationSocialURL(for: organization, matching: "instagram") != nil ||
            organizationSocialURL(for: organization, matching: "facebook") != nil
    }

    private func organizationAddressText(for organization: Organization) -> String? {
        let address = (organization.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)

        if !address.isEmpty, !city.isEmpty, !address.localizedCaseInsensitiveContains(city) {
            return "\(address), \(city)"
        }
        if !address.isEmpty {
            return address
        }
        return nil
    }

    private func visibleSocialLinks(for organization: Organization) -> [(key: String, value: String)] {
        organization.socialLinks
            .filter { key, value in
                !key.localizedCaseInsensitiveContains("telegram") &&
                    !value.localizedCaseInsensitiveContains("t.me")
            }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }

    private func organizationMapURL(for organization: Organization) -> URL? {
        let address = organizationAddressText(for: organization)
        let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = (address ?? city).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://maps.apple.com/?q=\(encodedQuery)")
    }

    private func organizationInfoRow(
        systemImage: String,
        title: String,
        value: String,
        lineLimit: Int = 3,
        truncatesMiddle: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.replacingOccurrences(of: " *", with: ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(lineLimit)
                    .truncationMode(truncatesMiddle ? .middle : .tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func organizationInfoLinkRow(systemImage: String, title: String, value: String, destination: URL) -> some View {
        Link(destination: destination) {
            organizationInfoRow(systemImage: systemImage, title: title, value: value, lineLimit: 1, truncatesMiddle: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(value)")
    }

    private func cleanURLDisplayText(_ url: URL) -> String {
        guard let host = url.host, !host.isEmpty else {
            return url.absoluteString
        }

        let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path == "/" ? "" : url.path
        return "\(cleanHost)\(path)"
    }

    private func emailURL(for email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "mailto:\(encoded)")
    }

    private func phoneURL(for phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private func disabledInfoRow(systemImage: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            Text(AppStrings.Organizations.comingSoon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(AppTheme.surfaceControl.opacity(0.34), in: Capsule())
                .overlay(Capsule().strokeBorder(AppTheme.borderSubtle))
        }
        .padding(.vertical, 4)
        .opacity(0.72)
    }

    private func meaningfulAboutText(for organization: Organization) -> String? {
        let fullDescription = organization.fullDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortDescription = organization.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullDescription.isEmpty {
            return fullDescription
        }
        if !shortDescription.isEmpty {
            return shortDescription
        }
        return nil
    }

    private func foundedDateText(for organization: Organization) -> String? {
        guard let foundedYear = organization.foundedYear else { return nil }
        guard let foundedMonth = organization.foundedMonth else {
            return String(foundedYear)
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = foundedYear
        components.month = foundedMonth
        components.day = 1

        guard let date = components.date else {
            return String(foundedYear)
        }

        let formatter = DateFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: date)
    }

    private func organizationTypeTitle(for organization: Organization) -> String {
        guard let organizationType = organization.organizationType,
              let category = OrganizationEditorCategory(rawValue: organizationType) else {
            return AppStrings.Organizations.detailBadge
        }
        return category.title
    }

    @ViewBuilder
    private func commentsSection(for organization: Organization) -> some View {
        detailGlassCard(padding: detailCardPadding) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.Common.comments)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)

                commentComposer(parentID: organization.id)

                let comments = viewModel.comments(for: organization.id)
                if comments.isEmpty {
                    Text(AppStrings.Common.noCommentsYet)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                            commentRow(comment, organization: organization)

                            if index < comments.count - 1 {
                                Divider()
                                    .padding(.vertical, AppTheme.eventsControlGroupSpacing)
                            }
                        }
                    }
                }
            }
        }
    }

    private func commentComposer(parentID: String) -> some View {
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
                        submitComment(parentID: parentID)
                    } label: {
                        Image(systemName: editingCommentID == nil ? "paperplane.fill" : "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.accentPrimary, in: Circle())
                    }
                    .disabled(trimmedCommentText.isEmpty || viewModel.pendingOrganizationCommentIDs.contains(parentID))
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

    private func commentRow(_ comment: Comment, organization: Organization) -> some View {
        HStack(alignment: .top, spacing: 10) {
            commentAvatar(comment)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Text(sanitizedAuthorName(comment.authorName))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Text(LocalizationStore.dateString(from: comment.createdAt, dateStyle: .short, timeStyle: .short))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    if canEditComment(comment) || canDeleteComment(comment, organization: organization) {
                        commentActionMenu(for: comment)
                    }
                }

                Text(comment.text)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentActionMenu(for comment: Comment) -> some View {
        Menu {
            if canEditComment(comment) {
                Button(AppStrings.Action.edit, systemImage: "pencil") {
                    editingCommentID = comment.id
                    commentText = comment.text
                    isCommentFieldFocused = true
                }
            }
            Button(AppStrings.Action.delete, systemImage: "trash", role: .destructive) {
                pendingCommentDeleteID = comment.id
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

    private var trimmedCommentText: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitComment(parentID: String) {
        guard let user = authState.user else {
            guestAccessAction = .comments
            return
        }
        let text = String(trimmedCommentText.prefix(1000))
        guard !text.isEmpty else { return }
        let editingID = editingCommentID
        Task {
            if let editingID {
                await viewModel.updateComment(organizationID: parentID, commentID: editingID, text: text)
            } else {
                await viewModel.addComment(to: parentID, text: text, author: user)
            }
            await MainActor.run {
                commentText = ""
                editingCommentID = nil
                isCommentFieldFocused = false
            }
        }
    }

    @MainActor
    private func deleteComment(commentID: String) async {
        await viewModel.deleteComment(organizationID: organizationID, commentID: commentID)
        pendingCommentDeleteID = nil
    }

    private func commentAvatar(_ comment: Comment) -> some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentPrimarySoft)
            if let authorPhotoURL = comment.authorPhotoURL, !authorPhotoURL.isEmpty {
                AsyncImage(url: URL(string: authorPhotoURL)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Text(commentInitials(comment))
                            .font(.caption.weight(.bold))
                    }
                }
            } else {
                Text(commentInitials(comment))
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(AppTheme.accentPrimary)
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }

    private func commentInitials(_ comment: Comment) -> String {
        let name = sanitizedAuthorName(comment.authorName)
        return String(name.prefix(1)).uppercased()
    }

    private func sanitizedAuthorName(_ authorName: String) -> String {
        let trimmed = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppStrings.Organizations.userFallback : trimmed
    }

    private func canEditComment(_ comment: Comment) -> Bool {
        guard let user = authState.user else { return false }
        return comment.authorId == user.id
    }

    private func canDeleteComment(_ comment: Comment, organization: Organization) -> Bool {
        guard let user = authState.user else { return false }
        if comment.authorId == user.id {
            return true
        }
        return PermissionService.canModerateOrganizationContent(organization, user: user)
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

    private func activitySection(for organization: Organization) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                HStack {
                    AppEditorSectionTitle(title: AppStrings.Organizations.upcomingEventsTitle)

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                }

                if activityViewModel.isLoading && activityViewModel.items.isEmpty {
                    LoadingStateCard(title: nil)
                } else if activityViewModel.items.isEmpty && activityViewModel.error != nil {
                    ErrorStateCard(
                        systemImage: "building.2",
                        title: AppStrings.Organizations.activityTitle,
                        message: readableOrganizationErrorText(activityViewModel.error),
                        retryTitle: AppStrings.Organizations.retry
                    ) {
                        Task {
                            await activityViewModel.refresh(for: organization)
                        }
                    }
                } else {
                    let eventItems = activityViewModel.items.filter { $0.itemType == .event }

                    if eventItems.isEmpty {
                        EmptyStateCard(
                            systemImage: "calendar",
                            title: AppStrings.Organizations.upcomingEventsTitle,
                            message: AppStrings.Organizations.empty
                        )
                    } else {
                        ForEach(eventItems) { item in
                            if let destination = item.destination {
                                NavigationLink {
                                    activityDestinationView(for: destination)
                                } label: {
                                    OrganizationActivityCard(item: item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                OrganizationActivityCard(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    private func organizationInitials(for organization: Organization) -> String {
        let words = organization.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let initials = String(words).uppercased()
        return initials.isEmpty ? "UC" : initials
    }

    @MainActor
    private func deleteCurrentOrganization() async {
        do {
            try await viewModel.deleteOrganization(id: organizationID, user: authState.user)
            pendingRemovalOrganizationID = organizationID
            dismiss()
            onOrganizationDeleted()
        } catch let appError as AppError {
            deleteErrorMessage = readableOrganizationErrorText(appError)
        } catch {
            deleteErrorMessage = readableOrganizationErrorText(.unknown)
        }
    }

    @ViewBuilder
    private func activityDestinationView(for destination: HomeFeedDestinationReference) -> some View {
        switch destination {
        case let .news(id):
            NewsDetailView(
                viewModel: newsDetailViewModel,
                postID: id,
                onNewsDeleted: {}
            )
        case let .event(id):
            EventDetailView(
                viewModel: eventsDetailViewModel,
                eventID: id,
                onEventDeleted: {}
            )
        case let .organization(id):
            OrganizationDetailView(
                viewModel: viewModel,
                organizationID: id,
                onOrganizationSaved: onOrganizationSaved,
                onOrganizationDeleted: onOrganizationDeleted
            )
            .environment(\.organizationPresentationMode, presentationMode)
        }
    }
}

private struct OrganizationActivityCompactCard: View {
    let item: OrganizationActivityItem
    var isPinned = false

    private let thumbnailSize: CGFloat = 58

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                thumbnail

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    metadataRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var thumbnail: some View {
        AppFeedThumbnail(
            imageURL: item.imageURL,
            fallbackSystemImage: itemTypeSystemImage,
            tint: AppTheme.accentPrimary,
            fill: AppTheme.accentPrimary.opacity(0.10),
            size: thumbnailSize,
            cornerRadius: AppTheme.feedThumbnailRadius,
            source: "OrganizationActivityCompactCard"
        )
        .frame(width: thumbnailSize, height: thumbnailSize, alignment: .center)
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            ContentMetadataPill(systemImage: itemTypeSystemImage, text: itemTypeTitle)
                .fixedSize(horizontal: true, vertical: false)

            if let eventText = organizationActivityEventText(for: item) {
                ContentMetadataPill(systemImage: "clock", text: eventText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                ContentMetadataPill(systemImage: "calendar", text: organizationActivityDateText(for: item))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if isPinned {
                ContentMetadataPill(systemImage: "pin.fill", text: AppStrings.Organizations.pinnedLabel)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var itemTypeTitle: String {
        switch item.itemType {
        case .news:
            AppStrings.News.title
        case .event:
            AppStrings.Tabs.events
        case .organizationProfile:
            AppStrings.Tabs.organizations
        }
    }

    private var itemTypeSystemImage: String {
        switch item.itemType {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .organizationProfile:
            "building.2"
        }
    }

    private var accessibilitySummary: String {
        var parts = [itemTypeTitle, item.title, item.summary]

        if let eventText = organizationActivityEventText(for: item) {
            parts.append(eventText)
        }

        if let locationText = organizationActivityLocationText(for: item) {
            parts.append(locationText)
        }

        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private struct OrganizationActivityCard: View {
    let item: OrganizationActivityItem

    var body: some View {
        CommunityCard {
            if item.imageURL != nil {
                RemoteCardImage(imageURL: item.imageURL, height: 160, source: "OrganizationActivityCard", isDecorative: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ContentMetadataPill(systemImage: itemTypeSystemImage, text: itemTypeTitle)
                        ContentMetadataPill(systemImage: "calendar", text: organizationActivityDateText(for: item))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ContentMetadataPill(systemImage: itemTypeSystemImage, text: itemTypeTitle)
                        ContentMetadataPill(systemImage: "calendar", text: organizationActivityDateText(for: item))
                    }
                }

                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let eventText = organizationActivityEventText(for: item) {
                    ContentMetadataPill(systemImage: "clock", text: eventText)
                }

                if let locationText = organizationActivityLocationText(for: item) {
                    ContentMetadataPill(systemImage: "mappin.and.ellipse", text: locationText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var itemTypeTitle: String {
        switch item.itemType {
        case .news:
            AppStrings.News.title
        case .event:
            AppStrings.Tabs.events
        case .organizationProfile:
            AppStrings.Tabs.organizations
        }
    }

    private var itemTypeSystemImage: String {
        switch item.itemType {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .organizationProfile:
            "building.2"
        }
    }

    private var accessibilitySummary: String {
        var parts = [itemTypeTitle, item.title, item.summary, organizationActivityDateText(for: item)]

        if let eventText = organizationActivityEventText(for: item) {
            parts.append(eventText)
        }

        if let locationText = organizationActivityLocationText(for: item) {
            parts.append(locationText)
        }

        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private struct OrganizationDeleteSwipeActions: ViewModifier {
    let isEnabled: Bool
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.swipeActions(edge: .trailing) {
                Button(AppStrings.Organizations.delete, role: .destructive) {
                    onDelete()
                }
            }
        } else {
            content
        }
    }
}

private struct OrganizationPresentationModeKey: EnvironmentKey {
    static let defaultValue: OrganizationPresentationMode = .public
}

extension EnvironmentValues {
    var organizationPresentationMode: OrganizationPresentationMode {
        get { self[OrganizationPresentationModeKey.self] }
        set { self[OrganizationPresentationModeKey.self] = newValue }
    }
}

#Preview("Organizations List") {
    NavigationStack {
        OrganizationsListView(
            viewModel: OrganizationsViewModel(repository: MockOrganizationRepository()),
            presentationMode: .management
        )
    }
    .environmentObject(AuthState())
}

#Preview("Organization Detail") {
    NavigationStack {
        OrganizationDetailView(
            viewModel: OrganizationsViewModel(repository: MockOrganizationRepository()),
            organizationID: MockContentBuilder.organizations().first!.id,
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository()
        )
        .environment(\.organizationPresentationMode, .management)
    }
    .environmentObject(AuthState())
}
