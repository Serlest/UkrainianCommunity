import SwiftUI

struct FeaturedBannerManagementRow<EditDestination: View>: View {
    let banner: FeaturedBanner
    let isUpdating: Bool
    let canDelete: Bool
    let onActiveChange: (Bool) -> Void
    let onDelete: () -> Void
    private let editDestination: () -> EditDestination

    init(
        banner: FeaturedBanner,
        isUpdating: Bool,
        canDelete: Bool,
        onActiveChange: @escaping (Bool) -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder editDestination: @escaping () -> EditDestination
    ) {
        self.banner = banner
        self.isUpdating = isUpdating
        self.canDelete = canDelete
        self.onActiveChange = onActiveChange
        self.onDelete = onDelete
        self.editDestination = editDestination
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                FeaturedBannerCardView(banner: banner)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(managementTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let publicHeadline = publicHeadlineText {
                            Text(publicHeadline)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 12)

                    statusBadge
                }

                metadataGrid

                if banner.hasUnsupportedLegacyConfiguration {
                    InlineMessageCard(
                        style: .info,
                        message: banner.requiresDataRepair
                            ? AppStrings.FeaturedManagement.dataRepairMessage
                            : AppStrings.FeaturedManagement.migrationRequiredMessage
                    )
                }

                Toggle(isOn: Binding(
                    get: { banner.isActive },
                    set: { onActiveChange($0) }
                )) {
                    Text(AppStrings.FeaturedManagement.activeToggle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .disabled(isUpdating || (banner.hasUnsupportedLegacyConfiguration && !banner.isActive))

                HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                    NavigationLink {
                        editDestination()
                    } label: {
                        Label(editButtonTitle, systemImage: editButtonSystemImage)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isUpdating)

                    if canDelete {
                        Button(role: .destructive, action: onDelete) {
                            Label(AppStrings.FeaturedManagement.deleteBanner, systemImage: "trash")
                                .labelStyle(.iconOnly)
                                .frame(width: AppTheme.iconButtonSize, height: AppTheme.iconButtonSize)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(AppTheme.accentDestructive)
                        .disabled(isUpdating)
                        .accessibilityLabel(AppStrings.FeaturedManagement.deleteBanner)
                    }
                }

                if isUpdating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(AppStrings.FeaturedManagement.updating)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var statusBadge: some View {
        Text(statusTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    private var metadataGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            FeaturedBannerMetadataLine(title: AppStrings.FeaturedManagement.sectionsLabel, value: visibleSectionsText, systemImage: "rectangle.grid.2x2")
            FeaturedBannerMetadataLine(title: AppStrings.FeaturedManagement.regionLabel, value: regionText, systemImage: "globe.europe.africa")
            FeaturedBannerMetadataLine(title: AppStrings.FeaturedManagement.actionLabel, value: actionText, systemImage: "arrow.up.forward.app")
            FeaturedBannerMetadataLine(title: AppStrings.FeaturedManagement.priorityLabel, value: "\(banner.priority)", systemImage: "list.number")
            FeaturedBannerMetadataLine(title: AppStrings.FeaturedManagement.scheduleLabel, value: scheduleText, systemImage: "calendar.badge.clock")
        }
    }

    private var lifecycleState: FeaturedBannerLifecycleState {
        banner.lifecycleState()
    }

    private var editButtonTitle: String {
        guard banner.hasUnsupportedLegacyConfiguration else {
            return AppStrings.FeaturedEditor.editBanner
        }
        return banner.requiresDataRepair
            ? AppStrings.FeaturedEditor.repairBanner
            : AppStrings.FeaturedEditor.migrateBanner
    }

    private var editButtonSystemImage: String {
        banner.hasUnsupportedLegacyConfiguration
            ? "arrow.triangle.2.circlepath"
            : "slider.horizontal.3"
    }

    private var statusTitle: String {
        switch lifecycleState {
        case .migrationRequired:
            return banner.requiresDataRepair
                ? AppStrings.FeaturedManagement.statusRepairRequired
                : AppStrings.FeaturedManagement.statusMigrationRequired
        case .inactive:
            return AppStrings.FeaturedManagement.inactive
        case .scheduled:
            return AppStrings.FeaturedManagement.statusScheduled
        case .live:
            return AppStrings.FeaturedManagement.statusLive
        case .expired:
            return AppStrings.FeaturedManagement.statusExpired
        }
    }

    private var statusColor: Color {
        switch lifecycleState {
        case .migrationRequired, .expired:
            return .orange
        case .inactive:
            return AppTheme.textSecondary
        case .scheduled:
            return .blue
        case .live:
            return AppTheme.accentPrimary
        }
    }

    private var scheduleText: String {
        switch (banner.startsAt, banner.endsAt) {
        case let (startsAt?, endsAt?):
            return "\(startsAt.formatted(date: .abbreviated, time: .shortened)) – \(endsAt.formatted(date: .abbreviated, time: .shortened))"
        case let (startsAt?, nil):
            return AppStrings.FeaturedManagement.scheduleStarts(startsAt)
        case let (nil, endsAt?):
            return AppStrings.FeaturedManagement.scheduleEnds(endsAt)
        case (nil, nil):
            return AppStrings.FeaturedManagement.scheduleAlways
        }
    }

    private var visibleSectionsText: String {
        banner.visibleSections
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.managementTitle)
            .joined(separator: ", ")
    }

    private var regionText: String {
        switch banner.regionScope {
        case .allAustria:
            return AppStrings.Home.regionAllAustria
        case .federalState:
            guard let federalState = banner.federalState else { return AppStrings.FeaturedManagement.missingRegion }
            return AppStrings.FederalStates.title(for: federalState)
        }
    }

    private var actionText: String {
        banner.actionType.managementTitle
    }

    private var managementTitle: String {
        if let internalName = nonEmpty(banner.internalName) {
            return internalName
        }
        if let title = nonEmpty(banner.title) {
            return title
        }
        return AppStrings.FeaturedManagement.fallbackBannerName(banner.id, date: banner.createdAt)
    }

    private var publicHeadlineText: String? {
        let title = nonEmpty(banner.title)
        let subtitle = nonEmpty(banner.subtitle)

        if nonEmpty(banner.internalName) != nil {
            return title ?? subtitle
        }
        return subtitle
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct FeaturedBannerMetadataLine: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            Text("\(title): \(value)")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accentPrimary)
        }
    }
}

extension FeaturedBannerVisibleSection {
    var managementTitle: String {
        switch self {
        case .home:
            return AppStrings.Tabs.home
        case .events:
            return AppStrings.Tabs.events
        case .organizations:
            return AppStrings.Tabs.organizations
        case .unsupportedLegacy:
            return AppStrings.FeaturedManagement.unsupportedLegacy
        }
    }
}

extension FeaturedBannerActionType {
    var managementTitle: String {
        switch self {
        case .none:
            return AppStrings.FeaturedManagement.actionNone
        case .news:
            return AppStrings.News.title
        case .event:
            return AppStrings.Tabs.events
        case .organization:
            return AppStrings.Tabs.organizations
        case .unsupportedLegacy:
            return AppStrings.FeaturedManagement.unsupportedLegacy
        case .externalURL:
            return AppStrings.FeaturedManagement.actionExternalURL
        }
    }
}
