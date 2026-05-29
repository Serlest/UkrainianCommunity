import SwiftUI

struct ProfileHeaderCard: View {
    let sessionState: AuthSessionState
    let user: AppUser?
    let readableFederalState: String?
    let onEditProfile: () -> Void
    let onSignIn: () -> Void
    let onCreateAccount: () -> Void

    var body: some View {
        CommunityCard {
            if let user {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 14) {
                        ProfileAvatarView(user: user)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(user.preferredDisplayName)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            if let fullName = user.preferredFullName {
                                Text(fullName)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    if user.globalRole.authorizationRole != .user {
                                        ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                    }

                                    if let readableFederalState {
                                        ProfileBadge(title: readableFederalState, systemImage: "globe.europe.africa")
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    if user.globalRole.authorizationRole != .user {
                                        ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                    }

                                    if let readableFederalState {
                                        ProfileBadge(title: readableFederalState, systemImage: "globe.europe.africa")
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    if let bio = profileNilIfEmpty(user.bio) {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let city = profileNilIfEmpty(user.city) {
                            ProfileMetadataRow(
                                title: AppStrings.Common.city,
                                value: city,
                                systemImage: "mappin.and.ellipse"
                            )
                        }

                        if let telegramUsername = user.telegramUsername.flatMap(profileNilIfEmpty) {
                            ProfileMetadataRow(
                                title: AppStrings.Profile.telegramUsername,
                                value: "@\(telegramUsername)",
                                systemImage: "paperplane"
                            )
                        }
                    }

                    Button(action: onEditProfile) {
                        Label(AppStrings.Profile.editProfile, systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .appActionButtonStyle(.secondary)
                    .accessibilityIdentifier("profile.edit.button")
                    .accessibilityLabel(AppStrings.Profile.editProfile)
                }
            } else if sessionState == .restoring {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(AppStrings.Profile.loadingUserProfile)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppStrings.Profile.guestTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(AppStrings.Profile.guestMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 8) {
                        Button(AppStrings.Auth.signIn, action: onSignIn)
                            .frame(maxWidth: .infinity)
                            .appActionButtonStyle(.primary)
                            .accessibilityIdentifier("profile.guest.signIn")

                        Button(action: onCreateAccount) {
                            Text(AppStrings.Auth.createAccount)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.accentPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppTheme.surfacePrimary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppTheme.accentPrimary.opacity(0.34), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.guest.createAccount")
                    }
                }
                .accessibilityIdentifier("profile.guest.card")
            }
        }
        .accessibilityIdentifier("profile.account.hero")
    }
}
struct GuestPlatformHeroCard: View {
    let onSignIn: () -> Void
    let onCreateAccount: () -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.Profile.guestWelcomeTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AppStrings.Profile.guestWelcomeSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Button(AppStrings.Auth.signIn, action: onSignIn)
                        .frame(maxWidth: .infinity)
                        .appActionButtonStyle(.primary)
                        .accessibilityIdentifier("profile.guest.signIn")

                    Button(action: onCreateAccount) {
                        Text(AppStrings.Auth.createAccount)
                            .frame(maxWidth: .infinity)
                    }
                    .appActionButtonStyle(.secondary)
                    .accessibilityIdentifier("profile.guest.createAccount")
                }
            }
        }
        .accessibilityIdentifier("profile.guest.card")
    }
}
struct ProfileHeroCard: View {
    let user: AppUser
    let readableFederalState: String?
    let onEditProfile: () -> Void

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

                        if let fullName = user.preferredFullName {
                            Text(fullName)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                ProfileBadge(title: GlobalRole.user.title, systemImage: "person")

                                if user.globalRole.authorizationRole != .user {
                                    ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                }

                                if user.accountStatus != .active {
                                    ProfileBadge(title: user.accountStatus.title, systemImage: "checkmark.seal")
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ProfileBadge(title: GlobalRole.user.title, systemImage: "person")

                                if user.globalRole.authorizationRole != .user {
                                    ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
                                }

                                if user.accountStatus != .active {
                                    ProfileBadge(title: user.accountStatus.title, systemImage: "checkmark.seal")
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                if let bio = profileNilIfEmpty(user.bio) {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(AppStrings.Profile.emptyBioStatus)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    if let city = profileNilIfEmpty(user.city) {
                        ProfileMetadataRow(title: AppStrings.Common.city, value: city, systemImage: "mappin.and.ellipse")
                    }

                    if let readableFederalState {
                        ProfileMetadataRow(title: AppStrings.Profile.region, value: readableFederalState, systemImage: "globe.europe.africa")
                    }

                    ProfileMetadataRow(
                        title: AppStrings.Profile.memberSince,
                        value: LocalizationStore.dateString(from: user.joinedAt, dateStyle: .medium, timeStyle: .none),
                        systemImage: "calendar"
                    )
                }
            }
        }
    }
}
struct ProfileAvatarView: View {
    let user: AppUser

    var body: some View {
        AvatarArtworkView(
            avatarURL: user.avatarURL,
            initials: user.initials,
            size: 72,
            accessibilityLabel: user.preferredDisplayName
        )
    }
}
struct ProfileMetadataRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer(minLength: 8)

                Text(value)
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accentPrimary)
        }
        .font(.subheadline)
    }
}
struct ProfileBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.accentPrimarySoft, in: Capsule())
    }
}

private func profileNilIfEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
