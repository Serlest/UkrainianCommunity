import SwiftUI

struct UserManagementAvatar: View {
    let user: AppUser
    let size: CGFloat

    var body: some View {
        AvatarArtworkView(
            avatarURL: user.avatarURL,
            initials: user.initials,
            size: size,
            showsBorder: false,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0,
            initialsFont: .subheadline.weight(.semibold),
            placeholderFill: AppTheme.accentPrimary.opacity(0.12)
        )
    }
}

struct UserManagementStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }
}

struct UserManagementMetadataRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                label
                Spacer(minLength: 8)
                valueText.multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                label
                valueText.multilineTextAlignment(.leading)
                    .padding(.leading, 28)
            }
        }
    }

    private var label: some View {
        Label {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: 18)
        }
    }

    private var valueText: some View {
        Text(value)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct UserManagementBadgeFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var position = CGPoint.zero
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if position.x > 0, position.x + size.width > maxWidth {
                position.x = 0
                position.y += lineHeight + spacing
                lineHeight = 0
            }
            position.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(
            // Report the width used for wrapping, not the final row's width.
            // Otherwise placement can wrap more rows than were measured.
            width: proposal.width ?? max(0, position.x - spacing),
            height: position.y + lineHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var position = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if position.x > bounds.minX, position.x + size.width > bounds.maxX {
                position.x = bounds.minX
                position.y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: position, proposal: ProposedViewSize(size))
            position.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct UserRolePermissionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let rows: [(String, String, String)] = [
        (AppStrings.UserManagement.roleGuideAppOwner, AppStrings.UserManagement.roleGuideAppOwnerDetail, "crown.fill"),
        (AppStrings.UserManagement.roleGuideAppAdmin, AppStrings.UserManagement.roleGuideAppAdminDetail, "person.badge.key.fill"),
        (AppStrings.UserManagement.roleGuideOrganizationOwner, AppStrings.UserManagement.roleGuideOrganizationOwnerDetail, "building.2.crop.circle.fill"),
        (AppStrings.UserManagement.roleGuideOrganizationAdmin, AppStrings.UserManagement.roleGuideOrganizationAdminDetail, "person.crop.circle.badge.checkmark"),
        (AppStrings.UserManagement.roleGuideOrganizationModerator, AppStrings.UserManagement.roleGuideOrganizationModeratorDetail, "shield.fill")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(
                        title: AppStrings.UserManagement.roleGuideTitle,
                        subtitle: AppStrings.UserManagement.roleGuideSubtitle
                    )

                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        AppEditorSectionCard {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: row.2)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                                    .frame(width: 36, height: 36)
                                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.0)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text(row.1)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(AppTheme.pageHorizontal)
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(AppStrings.UserManagement.roleGuideTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.Common.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct ManagedUserRow: View {
    let user: AppUser
    let organizationRoles: [UserOrganizationRole]

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    UserManagementAvatar(user: user, size: 46)
                    identityText
                }
                badges
                registrationDate
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.preferredDisplayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(secondaryLine)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var badges: some View {
        UserManagementBadgeFlowLayout(spacing: 6) {
            UserManagementStatusBadge(title: user.blockState.title, tint: statusTint)

            if !user.city.isEmpty {
                UserManagementStatusBadge(title: user.city, tint: AppTheme.textSecondary)
            }

            if let primaryOrganizationRole {
                UserManagementStatusBadge(title: primaryOrganizationRole, tint: AppTheme.accentPrimaryForeground)
            }

            if organizationRoles.count > 1 {
                UserManagementStatusBadge(title: AppStrings.UserManagement.organizationRolesAdditionalCount(organizationRoles.count - 1), tint: AppTheme.accentPrimaryForeground)
            }
        }
    }

    private var registrationDate: some View {
        Label(
            LocalizationStore.dateString(from: user.createdAt, dateStyle: .short, timeStyle: .none),
            systemImage: "calendar"
        )
        .font(.caption2)
        .foregroundStyle(AppTheme.textSecondary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var secondaryLine: String {
        if !user.email.isEmpty { return user.email }
        if let telegramUsername = user.telegramUsername, !telegramUsername.isEmpty { return telegramUsername }
        return user.id
    }

    private var statusTint: Color {
        switch user.blockState {
        case .active:
            AppTheme.accentPrimaryForeground
        case .warned:
            AppTheme.accentSupportForeground
        case .suspendedUntil, .blocked, .bannedPermanent, .deactivated:
            AppTheme.accentDestructiveForeground
        }
    }

    private var primaryOrganizationRole: String? {
        if organizationRoles.contains(where: { $0.role == .communityOwner }) { return AppStrings.UserManagement.organizationOwnerRole }
        if organizationRoles.contains(where: { $0.role == .communityAdmin }) { return AppStrings.UserManagement.organizationAdminRole }
        if organizationRoles.contains(where: { $0.role == .communityModerator }) { return AppStrings.UserManagement.organizationModeratorRole }
        return nil
    }
}


/// Presentation only: audit loading and pagination remain owned by the history card.
struct UserManagementAuditRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let date: String
    let reason: String
    let performedBy: String
    let changeSummary: String?

    private var headingLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headingLayout {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }

                Text(date)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(reason)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if !performedBy.isEmpty {
                Text(AppStrings.UserManagement.auditPerformedBy(performedBy))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let changeSummary {
                Text(changeSummary)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
