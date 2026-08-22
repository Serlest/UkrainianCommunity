import SwiftUI

struct OrganizationRoleDashboardCard: View {
    let membership: CommunityMembership
    let roleTitle: String
    let user: AppUser
    @ObservedObject var organizationsViewModel: OrganizationsViewModel

    private var organizationTitle: String {
        AppStrings.profileOrganizationID(membership.organizationId)
    }

    private var organizationSubtitle: String {
        AppStrings.profileOrganizationScopedSubtitle(membership.organizationId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "building.2")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(organizationTitle)
                        .font(AppTheme.buttonLabelFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(organizationSubtitle)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                Text(roleTitle)
                    .font(AppTheme.metadataFont)
                    .foregroundStyle(AppTheme.accentPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(minWidth: 92)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: Capsule())
                    .lineLimit(1)
            }

            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                switch membership.role {
                case .communityOwner:
                    ownerActions
                case .communityAdmin:
                    adminActions
                case .communityModerator:
                    moderatorActions
                case .member:
                    EmptyView()
                }
            }
        }
        .padding(AppTheme.eventsMetadataSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
        .accessibilityElement(children: .contain)
    }

    private var ownerActions: some View {
        Group {
            NavigationLink {
                OrganizationManagementHubView(
                    focusedOrganizationID: membership.organizationId,
                    organizationsViewModel: organizationsViewModel
                )
            } label: {
                ProfileModuleRow(title: AppStrings.Profile.organizationEditOrganization, subtitle: organizationSubtitle, systemImage: "pencil", status: .active)
            }
            .buttonStyle(.plain)

            organizationModerationLink(title: AppStrings.Profile.organizationModeration)
        }
    }

    private var adminActions: some View {
        Group {
            NavigationLink {
                OrganizationManagementHubView(
                    focusedOrganizationID: membership.organizationId,
                    organizationsViewModel: organizationsViewModel
                )
            } label: {
                ProfileModuleRow(title: AppStrings.Profile.organizationEditInfo, subtitle: organizationSubtitle, systemImage: "pencil", status: .active)
            }
            .buttonStyle(.plain)

            organizationModerationLink(title: AppStrings.Profile.organizationModeration)
        }
    }

    private var moderatorActions: some View {
        Group {
            organizationModerationLink(title: AppStrings.Profile.moderatorModerationQueue)
        }
    }

    private func organizationModerationLink(title: String) -> some View {
        NavigationLink {
            ModerationToolsView(organizationID: membership.organizationId)
        } label: {
            ProfileModuleRow(
                title: title,
                subtitle: AppStrings.Profile.organizationModerationScopedSubtitle,
                systemImage: "clock.badge.exclamationmark",
                status: .active
            )
        }
        .buttonStyle(.plain)
    }
}
