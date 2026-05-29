import Combine
import MapKit
import PhotosUI
import SwiftUI

extension OrganizationDetailView {
    var organizationTeamSection: some View {
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

    var communityEmptyState: some View {
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

    var communityLoadMoreButton: some View {
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

    func organizationCommunityRow(_ member: OrganizationCommunityMember) -> some View {
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

    func sectionHeader(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
    }

    func communityAvatar(for profile: PublicUserProfile) -> some View {
        AvatarArtworkView(
            avatarURL: profile.avatarURL,
            initials: communityInitials(for: profile),
            size: 42,
            showsBorder: false,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0,
            initialsFont: .footnote.weight(.bold),
            placeholderFill: AppTheme.glassControlSurface(for: colorScheme)
        )
        .overlay(Circle().strokeBorder(AppTheme.glassBorder(for: colorScheme)))
    }

    func communityInitialsAvatar(for profile: PublicUserProfile) -> some View {
        Circle()
            .fill(AppTheme.glassControlSurface(for: colorScheme))
            .overlay(
                Text(communityInitials(for: profile))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)
            )
    }

    func communityRoleBadge(_ role: OrganizationCommunityRole) -> some View {
        Text(role.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppTheme.accentPrimary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(AppTheme.accentPrimary.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(AppTheme.accentPrimary.opacity(0.22)))
    }

    @MainActor
    func communityLocationText(for profile: PublicUserProfile) -> String? {
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

    func communityInitials(for profile: PublicUserProfile) -> String {
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

    func communityRoleMap(for organization: Organization) -> [String: OrganizationCommunityRole] {
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

    func communityMemberSort(_ lhs: OrganizationCommunityMember, _ rhs: OrganizationCommunityMember) -> Bool {
        if lhs.role.rawValue != rhs.role.rawValue {
            return lhs.role.rawValue < rhs.role.rawValue
        }
        if lhs.role == .subscriber, lhs.followedAt != rhs.followedAt {
            return (lhs.followedAt ?? .distantPast) > (rhs.followedAt ?? .distantPast)
        }
        return lhs.profile.preferredDisplayName.localizedCaseInsensitiveCompare(rhs.profile.preferredDisplayName) == .orderedAscending
    }
}
