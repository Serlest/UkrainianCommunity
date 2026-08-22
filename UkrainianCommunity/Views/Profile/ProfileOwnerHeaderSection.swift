import SwiftUI

enum ProfileDashboardMode {
    case owner
    case admin
    case moderator
    case guideEditor

    init?(user: AppUser) {
        switch user.globalRole.authorizationRole {
        case .owner:
            self = .owner
        case .admin:
            self = .admin
        case .moderator:
            self = .moderator
        case .user, .topAdmin, .appModerator:
            guard user.canManageGuide else { return nil }
            self = .guideEditor
        }
    }

    var badgeTitle: String {
        switch self {
        case .owner:
            return AppStrings.Profile.platformOwnerBadge
        case .admin:
            return AppStrings.Profile.platformAdminBadge
        case .moderator:
            return AppStrings.Profile.platformModeratorBadge
        case .guideEditor:
            return AppStrings.Profile.guideEditorBadge
        }
    }

    var statusText: String {
        switch self {
        case .owner:
            return AppStrings.Profile.ownerHeroStatus
        case .admin:
            return AppStrings.Profile.adminHeroStatus
        case .moderator:
            return AppStrings.Profile.moderatorHeroStatus
        case .guideEditor:
            return AppStrings.Profile.guideEditorHeroStatus
        }
    }

    var accessLevel: String {
        switch self {
        case .owner:
            return AppStrings.Profile.ownerFullAccess
        case .admin:
            return AppStrings.Profile.adminOperationalAccess
        case .moderator:
            return AppStrings.Profile.moderatorContentAccess
        case .guideEditor:
            return AppStrings.Profile.guideEditorAccess
        }
    }

    var badgeSymbol: String {
        switch self {
        case .owner:
            return "crown"
        case .admin:
            return "person.badge.key"
        case .moderator:
            return "shield"
        case .guideEditor:
            return "book.closed"
        }
    }
}

struct OwnerHeroCard: View {
    let user: AppUser
    let readableFederalState: String?
    let mode: ProfileDashboardMode

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 14) {
                    ProfileAvatarView(user: user)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.preferredDisplayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(mode.statusText)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                ProfileBadge(title: mode.badgeTitle, systemImage: mode.badgeSymbol)
                                ProfileBadge(title: user.accountStatus.title, systemImage: "checkmark.seal")
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ProfileBadge(title: mode.badgeTitle, systemImage: mode.badgeSymbol)
                                ProfileBadge(title: user.accountStatus.title, systemImage: "checkmark.seal")
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    if let city = profileOwnerNilIfEmpty(user.city) {
                        ProfileMetadataRow(title: AppStrings.Common.city, value: city, systemImage: "mappin.and.ellipse")
                    }

                    if let readableFederalState {
                        ProfileMetadataRow(title: AppStrings.Profile.region, value: readableFederalState, systemImage: "globe.europe.africa")
                    }

                    ProfileMetadataRow(title: AppStrings.Profile.systemAccessLevel, value: mode.accessLevel, systemImage: "lock.shield")
                }
            }
        }
    }
}

private func profileOwnerNilIfEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
