import SwiftUI

extension OrganizationDetailView {
    func detailHeader(for organization: Organization) -> some View {
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

    func organizationHeaderBookmarkIcon(for organization: Organization) -> some View {
        Image(systemName: organization.isBookmarked ? "bookmark.fill" : "bookmark")
            .font(AppTheme.buttonLabelFont)
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

    var organizationHeaderShareIcon: some View {
        Image(systemName: "square.and.arrow.up")
            .font(AppTheme.buttonLabelFont)
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

    func organizationShareText(for organization: Organization) -> String {
        var parts = [organization.name]
        if let description = heroDescription(for: organization) {
            parts.append(description)
        }
        if let website = organizationWebsiteDisplayText(for: organization) {
            parts.append(website)
        }
        return parts.joined(separator: "\n")
    }

    func toggleBookmark(for organization: Organization) {
        guard authState.isAuthenticated else {
            guestAccessAction = .bookmarks
            return
        }

        viewModel.toggleBookmark(for: organization.id)
    }

    func organizationHero(for organization: Organization) -> some View {
        DetailCard {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                organizationLogo(for: organization)
                    .frame(width: heroLogoSize, height: heroLogoSize)
                    .layoutPriority(1)

                heroText(for: organization)
                    .frame(minHeight: heroLogoSize, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func organizationLogo(for organization: Organization) -> some View {
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
                            .font(AppTheme.screenTitleFont)
                            .foregroundStyle(AppTheme.accentPrimary)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
        .shadow(color: AppTheme.glassShadow(for: colorScheme).opacity(0.72), radius: 5, y: 2)
        .accessibilityLabel(AppStrings.Organizations.imageSectionTitle)
    }

    func heroText(for organization: Organization) -> some View {
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
                .font(AppTheme.screenTitleFont)
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)

            if let description = heroDescription(for: organization) {
                Text(description)
                    .font(AppTheme.secondaryBodyFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(AppTheme.detailBodyLineSpacing)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func organizationHeroChip(title: String, systemImage: String) -> some View {
        AppInfoChip(
            title: title.uppercased(),
            systemImage: systemImage,
            tint: AppTheme.accentPrimary,
            fill: AppTheme.accentPrimary.opacity(0.14),
            border: AppTheme.accentPrimary.opacity(0.18),
            size: .small
        )
    }

    func heroMetadata(for organization: Organization) -> some View {
        AppHorizontalChipRow(spacing: 6) {
            ForEach(heroMetadataItems(for: organization), id: \.0) { systemImage, text in
                ContentMetadataPill(systemImage: systemImage, text: text)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    @MainActor
    func heroMetadataItems(for organization: Organization) -> [(String, String)] {
        var items: [(String, String)] = [
            ("hand.thumbsup", "\(organization.likeCount)"),
            ("person.2", subscriberCountText(for: organization.subscriberCount))
        ]

        if let location = detailedLocationText(for: organization) {
            items.append(("mappin.and.ellipse", location))
        }

        return items
    }

    func subscriberCountText(for count: Int) -> String {
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

    func compactLocationText(for organization: Organization) -> String? {
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
    func detailedLocationText(for organization: Organization) -> String? {
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

    func heroDescription(for organization: Organization) -> String? {
        let shortDescription = organization.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return shortDescription.isEmpty ? nil : shortDescription
    }
}
