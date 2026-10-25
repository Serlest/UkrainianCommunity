import SwiftUI

struct AccountActionConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let action: UserAdminAction
    let target: AppUser
    let actor: AppUser?
    @ObservedObject var viewModel: UserManagementViewModel

    @State private var reason = ""
    @State private var submitting = false
    @State private var suspensionDays = 7

    private let suspensionOptions = [1, 7, 14, 30]

    private var canSubmit: Bool {
        reviewIsCurrent
            && !submitting && !viewModel.updatingUserIDs.contains(target.id)
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reason.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 2000
    }

    private var reviewIsCurrent: Bool {
        guard let actor else { return false }
        return viewModel.isReviewCurrent(target: target, actor: actor, currentActor: authState.user)
            && viewModel.canManage(target: target, actor: actor)
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
                        .modifier(UserActionDurationPickerStyle())
                        .accessibilityIdentifier("user.action.duration")
                        .disabled(submitting || viewModel.updatingUserIDs.contains(target.id))
                    }

                    Label(action.effectDescription, systemImage: "info.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField(AppStrings.UserManagement.reasonPlaceholder, text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("user.action.reason")
                        .disabled(submitting || viewModel.updatingUserIDs.contains(target.id))
                        .padding(AppTheme.inputHorizontalPadding)
                        .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))

                    Text(UserAdministrationCopy.reasonLimit)
                        .font(.caption).foregroundStyle(AppTheme.textSecondary)
                    if !reviewIsCurrent && !submitting && viewModel.statusMessage != AppStrings.UserManagement.changesSaved && viewModel.statusMessage != AppStrings.UserManagement.changesSavedRefreshFailed {
                        InlineMessageCard(style: .info, message: UserAdministrationCopy.reviewChanged)
                    }
                    Text(UserAdministrationCopy.auditNotice)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)

                    if let message = viewModel.statusMessage {
                        UserManagementOperationMessage(message: message)
                    }

                    PrimaryActionButton(
                        title: action.title,
                        isEnabled: canSubmit,
                        isLoading: submitting || viewModel.updatingUserIDs.contains(target.id),
                        systemImage: action.systemImage,
                        action: performAction
                    ).accessibilityIdentifier("user.action.confirm")
                }
                .padding(AppTheme.pageHorizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackgroundView())
            .navigationTitle(AppStrings.UserManagement.actionFallbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) { dismiss() }
                        .disabled(submitting || viewModel.updatingUserIDs.contains(target.id))
                        .accessibilityIdentifier("user.action.cancel")
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .interactiveDismissDisabled(submitting || viewModel.updatingUserIDs.contains(target.id))
        .onAppear { viewModel.statusMessage = nil }
    }

    private func performAction() {
        guard let actor, canSubmit else { return }
        let submittedReason = reason, submittedDays = suspensionDays
        submitting = true
        Task {
            defer { submitting = false }
            await viewModel.perform(action, target: target, actor: actor, reason: submittedReason, suspensionDays: submittedDays)
            if viewModel.statusMessage == AppStrings.UserManagement.changesSaved { dismiss() }
        }
    }
}

struct PlatformRoleConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let action: PlatformRoleAction
    let target: AppUser
    let actor: AppUser?
    @ObservedObject var viewModel: UserManagementViewModel
    @State private var reason = ""
    @State private var submitting = false

    private var reviewIsCurrent: Bool {
        guard let actor else { return false }
        return viewModel.isReviewCurrent(target: target, actor: actor, currentActor: authState.user)
            && viewModel.canManagePlatformRole(target: target, actor: actor)
    }

    var body: some View {
        AdminReasonSheetLayout(
            title: action.title,
            subtitle: AppStrings.UserManagement.actionTarget(target.preferredDisplayName),
            notice: UserAdministrationCopy.auditNotice,
            effect: action.effectDescription,
            reason: $reason,
            actionTitle: action.title,
            actionImage: action.systemImage,
            isEnabled: canSubmit,
            isLoading: submitting || viewModel.updatingUserIDs.contains(target.id),
            message: userAdministrationFeedback(current: reviewIsCurrent, submitting: submitting, message: viewModel.statusMessage),
            onCancel: { dismiss() },
            onConfirm: performAction
        )
        .onAppear { viewModel.statusMessage = nil }
    }

    private var canSubmit: Bool {
        reviewIsCurrent && !submitting && !viewModel.updatingUserIDs.contains(target.id)
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reason.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 2000
    }

    private func performAction() {
        guard let actor, canSubmit else { return }
        let submittedReason = reason
        submitting = true
        Task {
            defer { submitting = false }
            await viewModel.performPlatformRoleAction(action, target: target, actor: actor, reason: submittedReason)
            if viewModel.statusMessage == AppStrings.UserManagement.changesSaved { dismiss() }
        }
    }
}

struct OrganizationRoleRemovalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let organization: ManagedOrganization
    let target: AppUser
    let actor: AppUser?
    @ObservedObject var viewModel: UserManagementViewModel
    @State private var reason = ""
    @State private var submitting = false

    private var reviewIsCurrent: Bool {
        guard let actor else { return false }
        return viewModel.isReviewCurrent(target: target, actor: actor, currentActor: authState.user)
            && viewModel.isOrganizationReviewCurrent(organization)
            && viewModel.canManageOrganizationRoles(in: organization, actor: actor) && organization.ownerId != target.id
    }

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
            isLoading: submitting || viewModel.updatingUserIDs.contains(target.id),
            message: userAdministrationFeedback(current: reviewIsCurrent, submitting: submitting, message: viewModel.statusMessage),
            onCancel: { dismiss() },
            onConfirm: performAction
        )
        .onAppear { viewModel.statusMessage = nil }
    }

    private var canSubmit: Bool {
        reviewIsCurrent && !submitting && !viewModel.updatingUserIDs.contains(target.id)
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && reason.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 2000
    }

    private func performAction() {
        guard let actor, canSubmit else { return }
        let submittedReason = reason
        submitting = true
        Task {
            defer { submitting = false }
            await viewModel.removeRole(in: organization, from: target, actor: actor, reason: submittedReason)
            if viewModel.statusMessage == AppStrings.UserManagement.changesSaved { dismiss() }
        }
    }
}

private struct AdminReasonSheetLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let subtitle: String
    let notice: String
    let effect: String?
    @Binding var reason: String
    let actionTitle: String
    let actionImage: String
    let isEnabled: Bool
    let isLoading: Bool
    let message: String?
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
                        .accessibilityIdentifier("user.action.reason").disabled(isLoading)
                        .padding(AppTheme.inputHorizontalPadding)
                        .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    Text(UserAdministrationCopy.reasonLimit).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    if let message {
                        UserManagementOperationMessage(message: message)
                    }
                    PrimaryActionButton(
                        title: actionTitle,
                        isEnabled: isEnabled,
                        isLoading: isLoading,
                        systemImage: actionImage,
                        action: onConfirm
                    ).accessibilityIdentifier("user.action.confirm")
                }
                .padding(AppTheme.pageHorizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackgroundView())
            .navigationTitle(AppStrings.UserManagement.actionFallbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel, action: onCancel)
                        .disabled(isLoading)
                        .accessibilityIdentifier("user.action.cancel")
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .interactiveDismissDisabled(isLoading)
    }
}

struct UserManagementOperationMessage: View {
    let message: String
    private var style: InlineMessageStyle {
        if message == AppStrings.UserManagement.changesSaved { return .success }
        if message == AppStrings.UserManagement.changesSavedRefreshFailed { return .info }
        return .error
    }
    var body: some View {
        InlineMessageCard(style: style, message: message)
            .accessibilityIdentifier("user.action.result")
    }
}

private struct UserActionDurationPickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    @ViewBuilder func body(content: Content) -> some View {
        if size.isAccessibilitySize { content.pickerStyle(.menu) }
        else { content.pickerStyle(.segmented) }
    }
}

struct UserOwnershipTransferReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    let organization: ManagedOrganization
    let target: AppUser
    let actor: AppUser
    let reason: String
    @ObservedObject var viewModel: UserManagementViewModel
    let onSuccess: () -> Void

    @State private var submitting = false
    private var busy: Bool { submitting || viewModel.updatingUserIDs.contains(target.id) }
    private var canConfirm: Bool {
        guard viewModel.isReviewCurrent(target: target, actor: actor, currentActor: authState.user),
              PermissionService.canInitiateOwnershipTransferWorkflow(user: authState.user),
              viewModel.isOrganizationReviewCurrent(organization) else { return false }
        return !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reason.utf16.count <= 2000
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(title: AppStrings.UserManagement.ownerTransferConfirmationTitle,
                        subtitle: AppStrings.UserManagement.ownerTransferConfirmationMessage(target.preferredDisplayName, organization.name))
                    Text(reason).font(.body).foregroundStyle(AppTheme.textPrimary).textSelection(.enabled)
                    Text(UserAdministrationCopy.auditNotice).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    if !canConfirm && !submitting && viewModel.statusMessage != AppStrings.UserManagement.changesSaved && viewModel.statusMessage != AppStrings.UserManagement.changesSavedRefreshFailed { InlineMessageCard(style: .info, message: UserAdministrationCopy.reviewChanged) }
                    if let message = viewModel.statusMessage { UserManagementOperationMessage(message: message) }
                    PrimaryActionButton(title: AppStrings.UserManagement.changeOwnerButton,
                        isEnabled: canConfirm && !busy, isLoading: busy, systemImage: "person.crop.circle.badge.checkmark") {
                        guard canConfirm, !busy else { return }
                        submitting = true
                        Task {
                            defer { submitting = false }
                            await viewModel.changeOwner(in: organization, to: target, actor: actor, reason: reason)
                            if viewModel.statusMessage == AppStrings.UserManagement.changesSaved { onSuccess(); dismiss() }
                        }
                    }.accessibilityIdentifier("user.ownership.confirm")
                }.padding(AppTheme.pageHorizontal)
            }
            .background(AppBackgroundView())
            .navigationTitle(AppStrings.UserManagement.ownerTransferConfirmationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.Common.cancel) { dismiss() }.disabled(busy).accessibilityIdentifier("user.ownership.cancel")
            } }
        }.interactiveDismissDisabled(busy).onAppear { viewModel.statusMessage = nil }
    }
}

private func userAdministrationFeedback(current: Bool, submitting: Bool, message: String?) -> String? {
    if current || submitting || message == AppStrings.UserManagement.changesSaved || message == AppStrings.UserManagement.changesSavedRefreshFailed { return message }
    return UserAdministrationCopy.reviewChanged
}
