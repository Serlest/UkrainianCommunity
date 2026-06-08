import SwiftUI

enum ProfileModuleStatus {
    case available
    case active
    case accountRequired
    case locked

    var title: String? {
        switch self {
        case .available:
            return nil
        case .active:
            return AppStrings.Common.active
        case .accountRequired:
            return AppStrings.Profile.accountRequiredBadge
        case .locked:
            return AppStrings.Profile.accessLocked
        }
    }

    var tint: Color {
        switch self {
        case .available, .active:
            return AppTheme.accentPrimary
        case .accountRequired:
            return AppTheme.textSecondary
        case .locked:
            return AppTheme.accentDestructive
        }
    }

    var isDisabled: Bool {
        switch self {
        case .accountRequired, .locked:
            return true
        case .available, .active:
            return false
        }
    }
}


struct ProfileTextModuleRow: View {
    let title: String
    let subtitle: String?
    let accessory: AppNavigationRowAccessory

    init(
        title: String,
        subtitle: String? = nil,
        accessory: AppNavigationRowAccessory = .chevron
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if accessory == .chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}


struct ProfileModuleRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color?
    let status: ProfileModuleStatus
    let accessory: AppNavigationRowAccessory
    let countBadge: Int?

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color? = nil,
        status: ProfileModuleStatus = .available,
        accessory: AppNavigationRowAccessory = .chevron,
        countBadge: Int? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.status = status
        self.accessory = accessory
        self.countBadge = countBadge
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppNavigationRow(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint ?? status.tint,
                accessory: status.title == nil && !status.isDisabled ? accessory : .none
            )

            if let countBadge, countBadge > 0 {
                OwnerVisibilityCountBadge(count: countBadge, tint: tint ?? status.tint)
            }

            if let statusTitle = status.title {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(status.tint.opacity(0.10), in: Capsule())
                    .lineLimit(1)
                    .frame(minWidth: 82)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .opacity(status.isDisabled ? 0.72 : 1)
        .allowsHitTesting(!status.isDisabled)
        .accessibilityHint(status.isDisabled ? AppStrings.Action.comingSoon : "")
    }
}


struct OwnerVisibilityCountBadge: View {
    let count: Int
    let tint: Color

    private var displayText: String {
        count > 99 ? "99+" : "\(count)"
    }

    var body: some View {
        Text(displayText)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .monospacedDigit()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            )
            .accessibilityLabel(displayText)
    }
}


struct PlatformAccessStrip: View {
    let user: AppUser

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.eventsMetadataSpacing) {
            ProfileBadge(title: user.globalRole.title, systemImage: "person.badge.key")
            ProfileBadge(title: AppStrings.Profile.verifiedAccess, systemImage: "checkmark.seal")

            if PermissionService.hasOwnerRoleForDisplay(user: user) {
                ProfileBadge(title: AppStrings.Profile.systemAccessLevel, systemImage: "lock.shield")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
