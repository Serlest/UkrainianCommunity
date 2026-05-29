import SwiftUI

enum ManagedOrganizationRole {
    case owner
    case platformOwner
    case admin
    case moderator

    var title: String {
        switch self {
        case .owner:
            return AppStrings.Profile.organizationRoleOwner
        case .platformOwner:
            return AppStrings.Profile.organizationRolePlatformOwner
        case .admin:
            return AppStrings.Profile.organizationRoleAdmin
        case .moderator:
            return AppStrings.Profile.organizationRoleModerator
        }
    }

    var tint: Color {
        switch self {
        case .owner:
            return AppTheme.accentPrimary
        case .platformOwner:
            return .indigo
        case .admin:
            return .blue
        case .moderator:
            return .orange
        }
    }
}

struct ManagedOrganizationContentStats {
    let newsCount: Int
    let eventCount: Int
}


struct OrganizationRequestPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let organization: Organization

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppEditorSectionCard {
                    HStack(alignment: .top, spacing: 12) {
                        AppFeedThumbnail(
                            imageURL: organization.imageURL,
                            fallbackSystemImage: "building.2",
                            tint: AppTheme.accentPrimary,
                            fill: AppTheme.accentPrimary.opacity(0.10),
                            size: 56,
                            source: "OrganizationRequestPreviewView"
                        )

                        VStack(alignment: .leading, spacing: 7) {
                            AppEditorSectionTitle(title: organization.name)
                            Text(organization.moderationStatus.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.accentPrimary)
                            Text(organization.shortDescription)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }

                previewSection(title: AppStrings.Organizations.aboutSectionTitle) {
                    previewRow(AppStrings.Moderation.shortDescription, organization.shortDescription)
                    previewRow(AppStrings.Moderation.fullDescription, organization.fullDescription)
                    previewRow(AppStrings.Organizations.fieldMissionStatement, organization.missionStatement)
                }

                previewSection(title: AppStrings.Profile.organizationContactsSection) {
                    previewRow(AppStrings.Organizations.fieldContactEmail, organization.contactEmail ?? organization.email)
                    previewRow(AppStrings.Organizations.phonePlaceholder, organization.phone)
                    previewRow(AppStrings.Common.website, organization.website)
                    previewRow(AppStrings.Organizations.fieldTelegramURL, organization.telegramURL)
                    previewRow(AppStrings.Organizations.fieldDonationURL, organization.donationURL)
                    previewRow(AppStrings.Organizations.fieldAddress, organization.address)
                }

                if let reviewMessage = organization.reviewMessage ?? organization.rejectionReason {
                    InlineMessageCard(style: .info, message: reviewMessage)
                }
            }
            .padding(AppTheme.pageHorizontal)
        }
        .background(AppBackgroundView())
        .navigationTitle(AppStrings.Profile.previewOrganizationRequest)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.Common.done) {
                    dismiss()
                }
            }
        }
    }

    private func previewSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AppEditorSectionTitle(title: title)
                content()
            }
        }
    }

    @ViewBuilder
    private func previewRow(_ title: String, _ value: String?) -> some View {
        if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


struct OrganizationRequestCard: View {
    let organization: Organization
    let previewAction: () -> Void
    let editAction: () -> Void

    private var canEdit: Bool {
        organization.moderationStatus == .needsRevision || organization.moderationStatus == .rejected
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    AppFeedThumbnail(
                        imageURL: organization.imageURL,
                        fallbackSystemImage: "building.2",
                        tint: statusTint,
                        fill: statusTint.opacity(0.10),
                        size: 46,
                        source: "OrganizationRequestCard"
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(organization.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(2)

                            statusBadge
                        }

                        Text(organization.shortDescription)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let reviewMessage = organization.reviewMessage ?? organization.rejectionReason {
                    InlineMessageCard(style: .info, message: reviewMessage)
                }

                if canEdit {
                    Button(action: editAction) {
                        Label(AppStrings.Action.edit, systemImage: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: previewAction) {
                        Label(AppStrings.Profile.previewOrganizationRequest, systemImage: "doc.text.magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statusBadge: some View {
        Text(statusTitle)
            .font(.caption2.weight(.bold))
            .foregroundStyle(statusTint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(statusTint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(statusTint.opacity(0.22)))
    }

    private var statusTitle: String {
        switch organization.moderationStatus {
        case .pendingReview:
            AppStrings.Common.pendingReview
        case .needsRevision:
            AppStrings.Common.needsRevision
        case .rejected:
            AppStrings.Common.rejected
        case .approved:
            AppStrings.Common.approved
        case .draft:
            AppStrings.Common.draft
        case .archived:
            AppStrings.Common.archived
        }
    }

    private var statusTint: Color {
        switch organization.moderationStatus {
        case .pendingReview:
            .orange
        case .needsRevision:
            AppTheme.accentPrimary
        case .rejected:
            AppTheme.accentDestructive
        default:
            AppTheme.textSecondary
        }
    }
}


struct ManagedOrganizationCard: View {
    let organization: Organization
    let role: ManagedOrganizationRole
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    let contentStats: ManagedOrganizationContentStats?
    let isLoadingContentStats: Bool

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    AppFeedThumbnail(
                        imageURL: organization.imageURL,
                        fallbackSystemImage: "building.2",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.accentPrimary.opacity(0.10),
                        size: 46,
                        source: "ManagedOrganizationCard"
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(organization.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(2)

                            roleBadge
                        }

                        Text(organization.shortDescription)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)

                        metadataChips
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                statsRow

                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    NavigationLink {
                        OrganizationDetailView(
                            viewModel: organizationsViewModel,
                            organizationID: organization.id
                        )
                    } label: {
                        managedOrganizationActionLabel(title: AppStrings.Profile.organizationOpen, systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ManagedOrganizationView(
                            organization: organization,
                            organizationsViewModel: organizationsViewModel
                        )
                    } label: {
                        managedOrganizationActionLabel(title: AppStrings.Profile.organizationManage, systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var roleBadge: some View {
        Text(role.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(role.tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(role.tint.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(role.tint.opacity(0.22))
            )
    }

    private var metadataChips: some View {
        AppHorizontalChipRow(spacing: 6) {
            AppInfoChip(
                title: regionText,
                systemImage: "mappin.and.ellipse",
                tint: AppTheme.textSecondary,
                fill: AppTheme.surfaceControl.opacity(0.62),
                size: .small
            )

            AppInfoChip(
                title: categoryText,
                systemImage: "building.2",
                tint: AppTheme.textSecondary,
                fill: AppTheme.surfaceControl.opacity(0.62),
                size: .small
            )
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            managementStat(title: AppStrings.Profile.organizationStatSubscribers, value: "\(organization.subscriberCount)")
            managementStat(title: AppStrings.Profile.organizationStatNews, value: contentStatValue(contentStats?.newsCount))
            managementStat(title: AppStrings.Profile.organizationStatEvents, value: contentStatValue(contentStats?.eventCount))
        }
    }

    private func contentStatValue(_ value: Int?) -> String {
        guard let value else { return isLoadingContentStats ? "..." : "—" }
        return "\(value)"
    }

    private func managementStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceControl.opacity(0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.7))
        )
    }

    private func managedOrganizationActionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.accentPrimary.opacity(0.18))
            )
    }

    @MainActor private var regionText: String {
        let region = organization.federalState.map(AppStrings.FederalStates.title(for:)) ?? organization.city
        if organization.city.isEmpty || organization.city == region {
            return region
        }
        return "\(organization.city), \(region)"
    }

    private var categoryText: String {
        guard let organizationType = organization.organizationType,
              let category = OrganizationEditorCategory(rawValue: organizationType) else {
            return AppStrings.Organizations.detailBadge
        }
        return category.title
    }
}


struct ManagementPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.22)))
    }
}


struct OrganizationManagementRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var isEnabled = true

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.18)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isEnabled ? AppTheme.textPrimary : AppTheme.textSecondary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary.opacity(isEnabled ? 0.75 : 0.35))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 66)
        .background(AppTheme.surfaceSecondary.opacity(isEnabled ? 1 : 0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.55))
        )
    }
}
