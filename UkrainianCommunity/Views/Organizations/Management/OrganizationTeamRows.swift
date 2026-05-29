import SwiftUI

struct OrganizationTeamMemberRow: View {
    let member: OrganizationTeamMember
    let canManage: Bool
    let canChangeRole: Bool
    let availableRoles: [OrganizationTeamRole]
    let isUpdating: Bool
    let onAssignRole: (OrganizationTeamRole) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TeamAvatarView(profile: member.profile, fallbackInitials: member.initials)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if let locationText = member.locationText {
                    Text(locationText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                } else if member.profile == nil {
                    Text(member.userID)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            roleBadge

            if isUpdating {
                ProgressView()
                    .controlSize(.small)
            } else if canManage {
                Menu {
                    if canChangeRole {
                        ForEach(availableRoles) { role in
                            Button(AppStrings.profileOrganizationTeamMakeRole(role.title.lowercased())) {
                                onAssignRole(role)
                            }
                        }

                        if member.role != .member {
                            Button(AppStrings.Profile.organizationTeamRemoveRole, role: .destructive) {
                                onRemove()
                            }
                        }
                    } else {
                        Text(AppStrings.Profile.organizationTeamUnavailable)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(canChangeRole ? AppTheme.accentPrimary : AppTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.surfaceControl.opacity(0.55), in: Circle())
                }
                .disabled(!canChangeRole)
                .accessibilityLabel(AppStrings.Profile.organizationTeamRoleActions)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle.opacity(0.55))
        )
    }

    private var roleBadge: some View {
        Text(member.role.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(member.role.tint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(member.role.tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(member.role.tint.opacity(0.22)))
    }
}

struct OrganizationTeamCandidateRow: View {
    let member: OrganizationTeamMember
    let role: OrganizationTeamRole?
    let isOwnerTransfer: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TeamAvatarView(profile: member.profile, fallbackInitials: member.initials)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    if let locationText = member.locationText {
                        Text(locationText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }

                    if let role {
                        Text(role.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(role.tint)
                    } else if isOwnerTransfer {
                        Text(AppStrings.Profile.organizationTeamNoCurrentRole)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isOwnerTransfer ? "person.crop.circle.badge.checkmark" : "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.accentPrimary)
        }
        .padding(.vertical, 4)
    }
}

struct TeamAvatarView: View {
    let profile: PublicUserProfile?
    let fallbackInitials: String

    init(profile: PublicUserProfile?, fallbackInitials: String? = nil) {
        self.profile = profile
        self.fallbackInitials = fallbackInitials ?? "?"
    }

    var body: some View {
        AvatarArtworkView(
            avatarURL: profile?.avatarURL,
            initials: fallbackInitials,
            size: 42,
            showsBorder: false,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0,
            initialsFont: .caption.weight(.bold),
            placeholderFill: AppTheme.accentPrimarySoft
        )
    }
}
