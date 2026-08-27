import SwiftUI

extension OrganizationDetailView {
    func directoryProfileCards(for organization: Organization) -> some View {
        OrganizationDirectorySection(profile: organization.localizedDirectoryProfile, moderationStatus: organization.moderationStatus)
    }
}

/// Used by both the public detail page and the moderation preview.
struct OrganizationDirectorySection: View {
    let profile: OrganizationDirectoryProfile?
    let moderationStatus: ModerationStatus
    var usesPublicDetailStyle = true

    var body: some View {
        if let profile {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                directoryIdentityCard(profile)
                verifiedSpecialistCard(profile, moderationStatus: moderationStatus)
                directoryActionCard(profile)
                directoryOfferCard(profile)
                directoryHoursCard(profile)
                directoryServicesCard(profile)
            }
        }
    }

    @ViewBuilder
    private func directoryCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if usesPublicDetailStyle {
            DetailCard(content: content)
        } else {
            AppEditorSectionCard(content: content)
        }
    }

    private func directoryIdentityCard(_ profile: OrganizationDirectoryProfile) -> some View {
        directoryCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                Label(profile.profileKind.title, systemImage: profile.profileKind.systemImage)
                    .font(AppTheme.cardTitleFont)
                    .foregroundStyle(AppTheme.textPrimary)
                if !profile.secondaryCategories.isEmpty {
                    Text(AppStrings.Organizations.categoriesTitle)
                        .font(AppTheme.metadataStrongFont)
                        .foregroundStyle(AppTheme.textSecondary)
                    ForEach(profile.secondaryCategories, id: \.self) { category in
                        Text(OrganizationEditorCategory(rawValue: category)?.title ?? category)
                            .font(AppTheme.secondaryBodyFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func verifiedSpecialistCard(
        _ profile: OrganizationDirectoryProfile,
        moderationStatus: ModerationStatus
    ) -> some View {
        if profile.profileKind == .specialist, moderationStatus == .approved {
            directoryCard {
                Label(AppStrings.Organizations.verifiedSpecialist, systemImage: "checkmark.seal.fill")
                    .font(AppTheme.cardTitleFont)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func directoryActionCard(_ profile: OrganizationDirectoryProfile) -> some View {
        let actions = directoryActions(profile)
        if !actions.isEmpty {
            directoryCard {
                AppAdaptiveGrid(
                    minimumWidth: 140,
                    maximumWidth: 240,
                    spacing: AppTheme.eventsMetadataSpacing
                ) {
                    ForEach(actions, id: \.title) { action in
                        OrganizationDirectoryLink(title: action.title, systemImage: action.systemImage, value: action.value)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.iconButtonSize)
                            .appGlassActionSurface(.prominent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func directoryOfferCard(_ profile: OrganizationDirectoryProfile) -> some View {
        if profile.currentOfferTitle != nil || profile.currentOfferDetails != nil
            || profile.currentOfferURL != nil || profile.currentOfferValidUntil != nil {
            directoryCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Label(AppStrings.Organizations.currentOfferTitle, systemImage: "tag.fill")
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                    if let title = profile.currentOfferTitle {
                        Text(title)
                            .font(AppTheme.cardTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let details = profile.currentOfferDetails {
                        Text(details)
                            .font(AppTheme.cardSubtitleFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let validUntil = profile.currentOfferValidUntil {
                        Text("\(AppStrings.Organizations.offerValidUntil): \(LocalizationStore.dateString(from: validUntil, localizedTemplate: "d MMMM yyyy"))")
                            .font(AppTheme.metadataFont)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    if let value = profile.currentOfferURL {
                        OrganizationDirectoryLink(title: AppStrings.Organizations.currentOfferTitle, systemImage: "arrow.up.right", value: value)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func directoryHoursCard(_ profile: OrganizationDirectoryProfile) -> some View {
        if !profile.regularHours.isEmpty || profile.specialHoursNote != nil {
            directoryCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    HStack {
                        Text(AppStrings.Organizations.openingHoursTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        if let isOpen = isOpenNow(profile) {
                            Text(isOpen ? AppStrings.Organizations.openNow : AppStrings.Organizations.closedNow)
                                .font(AppTheme.metadataStrongFont)
                                .foregroundStyle(isOpen ? AppTheme.accentSuccessForeground : AppTheme.textSecondary)
                        }
                    }

                    ForEach(OrganizationWeekday.allCases) { day in
                        if let hours = profile.regularHours[day.rawValue] {
                            HStack(alignment: .firstTextBaseline) {
                                Text(day.title)
                                    .foregroundStyle(AppTheme.textSecondary)
                                Spacer()
                                Text(hours == "closed" ? AppStrings.Organizations.hoursClosed : hours)
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                            .font(AppTheme.secondaryBodyFont)
                        }
                    }

                    if let note = profile.specialHoursNote {
                        Label(note, systemImage: "calendar.badge.exclamationmark")
                            .font(AppTheme.metadataFont)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func directoryServicesCard(_ profile: OrganizationDirectoryProfile) -> some View {
        if !profile.services.isEmpty || !profile.serviceModes.isEmpty || profile.serviceArea != nil {
            directoryCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Text(AppStrings.Organizations.servicesTitle)
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)

                    if !profile.serviceModes.isEmpty {
                        AppHorizontalChipRow {
                            ForEach(profile.serviceModes) { mode in
                                AppInfoChip(
                                    title: mode.title,
                                    systemImage: mode.systemImage,
                                    tint: AppTheme.accentPrimaryForeground,
                                    fill: AppTheme.badgeBlueFill
                                )
                            }
                        }
                    }

                    ForEach(profile.services, id: \.self) { service in
                        Label(service, systemImage: "checkmark.circle.fill")
                            .font(AppTheme.secondaryBodyFont)
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    if let serviceArea = profile.serviceArea {
                        Label(serviceArea, systemImage: "map")
                            .font(AppTheme.metadataFont)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func directoryActions(_ profile: OrganizationDirectoryProfile) -> [(title: String, systemImage: String, value: String)] {
        var actions: [(String, String, String)] = []
        if let url = profile.orderURL {
            actions.append((AppStrings.Organizations.orderAction, "bag", url))
        }
        if let url = profile.bookingURL {
            actions.append((AppStrings.Organizations.bookingAction, "calendar.badge.plus", url))
        }
        return actions
    }

    private func isOpenNow(_ profile: OrganizationDirectoryProfile, now: Date = Date()) -> Bool? {
        let calendar = Calendar.current
        let weekdayIndex = calendar.component(.weekday, from: now)
        let keys = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        guard keys.indices.contains(weekdayIndex - 1),
              let hours = profile.regularHours[keys[weekdayIndex - 1]] else {
            return nil
        }
        guard hours != "closed" else { return false }
        let parts = hours.replacingOccurrences(of: "–", with: "-").split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let opening = timeMinutes(String(parts[0])),
              let closing = timeMinutes(String(parts[1])) else {
            return nil
        }
        let current = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return opening <= closing
            ? (opening...closing).contains(current)
            : current >= opening || current <= closing
    }

    private func timeMinutes(_ value: String) -> Int? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }
}

private struct OrganizationDirectoryLink: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        if let url = OrganizationWebURL.url(from: value) {
            Link(destination: url) {
                Label(title, systemImage: systemImage)
                    .font(AppTheme.buttonLabelFont)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                    .font(AppTheme.buttonLabelFont)
                Text(value)
                    .font(AppTheme.secondaryBodyFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}
