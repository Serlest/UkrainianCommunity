import SwiftUI

enum ProfileDashboardMode {
    case owner

    init?(user: AppUser) {
        switch user.globalRole.authorizationRole {
        case .owner:
            self = .owner
        case .user, .topAdmin, .appModerator:
            return nil
        }
    }

    var badgeTitle: String {
        switch self {
        case .owner:
            return AppStrings.Profile.platformOwnerBadge
        }
    }

    var statusText: String {
        switch self {
        case .owner:
            return AppStrings.Profile.ownerHeroStatus
        }
    }

    var accessLevel: String {
        switch self {
        case .owner:
            return AppStrings.Profile.ownerFullAccess
        }
    }

    var badgeSymbol: String {
        switch self {
        case .owner:
            return "crown"
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
