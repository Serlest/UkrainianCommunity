import SwiftUI

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
