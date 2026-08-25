import SwiftUI

struct AccountActionConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let action: UserAdminAction
    let target: AppUser
    let actor: AppUser?
    @ObservedObject var viewModel: UserManagementViewModel

    @State private var reason = ""
    @State private var suspensionDays = 7

    private let suspensionOptions = [1, 7, 14, 30]

    private var canSubmit: Bool {
        actor != nil
            && !viewModel.updatingUserIDs.contains(target.id)
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(
                        title: action.title,
                        subtitle: AppStrings.UserManagement.actionTarget(target.preferredDisplayName)
                    )

                    if action == .suspended {
                        Picker(AppStrings.UserManagement.suspensionDuration, selection: $suspensionDays) {
                            ForEach(suspensionOptions, id: \.self) { days in
                                Text(AppStrings.UserManagement.suspensionDays(days)).tag(days)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Label(action.effectDescription, systemImage: "info.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField(AppStrings.UserManagement.reasonPlaceholder, text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(AppTheme.inputHorizontalPadding)
                        .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))

                    Text(AppStrings.UserManagement.actionAuditNotice)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)

                    PrimaryActionButton(
                        title: action.title,
                        isEnabled: canSubmit,
                        isLoading: viewModel.updatingUserIDs.contains(target.id),
                        systemImage: action.systemImage,
                        action: performAction
                    )
                }
                .padding(AppTheme.pageHorizontal)
            }
            .navigationTitle(AppStrings.UserManagement.actionFallbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func performAction() {
        guard let actor else { return }
        Task {
            await viewModel.perform(action, target: target, actor: actor, reason: reason, suspensionDays: suspensionDays)
            if viewModel.statusMessage == AppStrings.UserManagement.changesSaved { dismiss() }
        }
    }
}

struct PlatformRoleConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let action: PlatformRoleAction
    let target: AppUser
    let actor: AppUser?
    @ObservedObject var viewModel: UserManagementViewModel
    @State private var reason = ""

    var body: some View {
        AdminReasonSheetLayout(
            title: action.title,
            subtitle: AppStrings.UserManagement.actionTarget(target.preferredDisplayName),
            notice: AppStrings.UserManagement.platformRoleAuditNotice,
            effect: action.effectDescription,
            reason: $reason,
            actionTitle: action.title,
            actionImage: action.systemImage,
            isEnabled: canSubmit,
            isLoading: viewModel.updatingUserIDs.contains(target.id),
            onCancel: { dismiss() },
            onConfirm: performAction
        )
    }

    private var canSubmit: Bool {
        actor != nil && !viewModel.updatingUserIDs.contains(target.id)
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func performAction() {
        guard let actor else { return }
        Task {
            await viewModel.performPlatformRoleAction(action, target: target, actor: actor, reason: reason)
            if viewModel.statusMessage == AppStrings.UserManagement.changesSaved { dismiss() }
        }
    }
}

struct OrganizationRoleRemovalSheet: View {
    @Environment(\.dismiss) private var dismiss

    let organization: ManagedOrganization
    let target: AppUser
    let actor: AppUser?
    @ObservedObject var viewModel: UserManagementViewModel
    @State private var reason = ""

    var body: some View {
        AdminReasonSheetLayout(
            title: AppStrings.UserManagement.removeOrganizationRoleTitle,
            subtitle: "\(target.preferredDisplayName) · \(organization.name)",
            notice: AppStrings.UserManagement.removeOwnerRoleWarning,
            effect: nil,
            reason: $reason,
            actionTitle: AppStrings.UserManagement.removeOrganizationRoleButton,
            actionImage: "minus.circle",
            isEnabled: canSubmit,
            isLoading: viewModel.updatingUserIDs.contains(target.id),
            onCancel: { dismiss() },
            onConfirm: performAction
        )
    }

    private var canSubmit: Bool {
        actor != nil && !viewModel.updatingUserIDs.contains(target.id)
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func performAction() {
        guard let actor else { return }
        Task {
            await viewModel.removeRole(in: organization, from: target, actor: actor, reason: reason)
            if viewModel.statusMessage == AppStrings.UserManagement.changesSaved { dismiss() }
        }
    }
}

private struct AdminReasonSheetLayout: View {
    let title: String
    let subtitle: String
    let notice: String
    let effect: String?
    @Binding var reason: String
    let actionTitle: String
    let actionImage: String
    let isEnabled: Bool
    let isLoading: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(title: title, subtitle: subtitle)
                    if let effect {
                        Label(effect, systemImage: "info.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    TextField(AppStrings.UserManagement.reasonPlaceholder, text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(AppTheme.inputHorizontalPadding)
                        .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    PrimaryActionButton(
                        title: actionTitle,
                        isEnabled: isEnabled,
                        isLoading: isLoading,
                        systemImage: actionImage,
                        action: onConfirm
                    )
                }
                .padding(AppTheme.pageHorizontal)
            }
            .navigationTitle(AppStrings.UserManagement.actionFallbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel, action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
