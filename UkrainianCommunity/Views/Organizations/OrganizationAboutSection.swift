import SwiftUI

extension OrganizationDetailView {
    func aboutCard(for organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            DetailCard {
                aboutTextBlock(for: organization)
            }

            if let missionStatement = organization.missionStatement?.trimmingCharacters(in: .whitespacesAndNewlines), !missionStatement.isEmpty {
                DetailCard {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        Text(AppStrings.Organizations.detailMissionStatementTitle)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(missionStatement)
                            .font(AppTheme.cardSubtitleFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineSpacing(AppTheme.detailBodyLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if hasCommunityHighlights(for: organization) {
                communityHighlightsBlock(for: organization)
            }

            DetailCard {
                organizationFactsBlock(for: organization)
            }
        }
    }

    func aboutTextBlock(for organization: Organization) -> some View {
        let text = meaningfulAboutText(for: organization)

        return VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            Text(AppStrings.Organizations.aboutSectionTitle)
                .font(AppTheme.sectionTitleFont)
                .foregroundStyle(AppTheme.textPrimary)

            if let text {
                let collapsedLineLimit = 4
                let isLongText = text.count > 180

                Text(text)
                    .font(AppTheme.cardSubtitleFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(AppTheme.detailBodyLineSpacing)
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
                        .font(AppTheme.buttonLabelFont)
                        .foregroundStyle(AppTheme.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(AppStrings.Organizations.aboutEmptyMessage)
                    .font(AppTheme.secondaryBodyFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func organizationFactsBlock(for organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            Text(AppStrings.Organizations.mainInformationTitle)
                .font(AppTheme.sectionTitleFont)
                .foregroundStyle(AppTheme.textPrimary)

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

    func organizationFactItems(for organization: Organization) -> [(systemImage: String, title: String, value: String)] {
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

    func organizationFactTile(systemImage: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(AppTheme.metadataStrongFont)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)

            Text(value)
                .font(AppTheme.secondaryBodyFont.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .padding(AppTheme.eventsMetadataSpacing)
        .background(AppTheme.groupedPlaneSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.72))
        )
    }

    @ViewBuilder
    func contactCard(for organization: Organization) -> some View {
        OrganizationContactCard(
            organization: organization,
            allowsEditing: false,
            showsManagementActions: false,
            usesPublicDetailStyle: true,
            onEdit: nil
        )
    }

    func hasContactInfo(for organization: Organization) -> Bool {
        organizationAddressText(for: organization) != nil ||
            organizationWebsiteDisplayText(for: organization) != nil ||
            organizationContactText(for: organization) != nil ||
            !(organization.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            organizationTelegramURL(for: organization) != nil ||
            organizationSocialURL(for: organization, matching: "instagram") != nil ||
            organizationSocialURL(for: organization, matching: "facebook") != nil ||
            organizationSocialURL(for: organization, matching: "whatsapp") != nil ||
            organizationSocialURL(for: organization, matching: "youtube") != nil ||
            organizationSocialURL(for: organization, matching: "linkedin") != nil
    }

    func organizationAddressText(for organization: Organization) -> String? {
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

    func visibleSocialLinks(for organization: Organization) -> [(key: String, value: String)] {
        organization.socialLinks
            .filter { key, value in
                !key.localizedCaseInsensitiveContains("telegram") &&
                    !value.localizedCaseInsensitiveContains("t.me")
            }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }

    func organizationMapURL(for organization: Organization) -> URL? {
        let address = organizationAddressText(for: organization)
        let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = (address ?? city).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://maps.apple.com/?q=\(encodedQuery)")
    }

    func organizationInfoRow(
        systemImage: String,
        title: String,
        value: String,
        lineLimit: Int = 3,
        truncatesMiddle: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: systemImage)
                .font(AppTheme.buttonLabelFont)
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.replacingOccurrences(of: " *", with: ""))
                    .font(AppTheme.metadataStrongFont)
                    .foregroundStyle(AppTheme.textSecondary)

                Text(value)
                    .font(AppTheme.secondaryBodyFont.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(lineLimit)
                    .truncationMode(truncatesMiddle ? .middle : .tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    func organizationInfoLinkRow(systemImage: String, title: String, value: String, destination: URL) -> some View {
        Link(destination: destination) {
            organizationInfoRow(systemImage: systemImage, title: title, value: value, lineLimit: 1, truncatesMiddle: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(value)")
    }

    func cleanURLDisplayText(_ url: URL) -> String {
        guard let host = url.host, !host.isEmpty else {
            return url.absoluteString
        }

        let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path == "/" ? "" : url.path
        return "\(cleanHost)\(path)"
    }

    func emailURL(for email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "mailto:\(encoded)")
    }

    func phoneURL(for phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    func disabledInfoRow(systemImage: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: systemImage)
                .font(AppTheme.buttonLabelFont)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTheme.metadataStrongFont)
                    .foregroundStyle(AppTheme.textSecondary)

                Text(value)
                    .font(AppTheme.secondaryBodyFont.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            Text(AppStrings.Organizations.comingSoon)
                .font(AppTheme.metadataStrongFont)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(AppTheme.surfaceControl.opacity(0.34), in: Capsule())
                .overlay(Capsule().strokeBorder(AppTheme.borderSubtle))
        }
        .padding(.vertical, 4)
        .opacity(0.72)
    }

    func meaningfulAboutText(for organization: Organization) -> String? {
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

    func foundedDateText(for organization: Organization) -> String? {
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

    func organizationTypeTitle(for organization: Organization) -> String {
        guard let organizationType = organization.organizationType,
              let category = OrganizationEditorCategory(rawValue: organizationType) else {
            return AppStrings.Organizations.detailBadge
        }
        return category.title
    }
}
