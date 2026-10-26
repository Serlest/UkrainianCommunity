import SwiftUI

struct NotificationDetailView: View {
    let notification: AppNotification
    @ObservedObject var viewModel: NotificationInboxViewModel
    let openDestination: (AppNotification) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false

    private var currentNotification: AppNotification {
        viewModel.notifications.first { $0.id == notification.id } ?? notification
    }
    private var canAct: Bool { viewModel.detailStates[notification.id]?.isReady == true }

    var body: some View {
        PushedScreenShell(
            title: AppStrings.NotificationInbox.detailTitle,
            pinsHeaderAtAccessibilitySizes: true,
            showsBackButton: false
        ) {
            AppGlassIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.NotificationInbox.closeDetails) {
                dismiss()
            }
            .accessibilityIdentifier("notificationDetail.close")
        } content: {
            if viewModel.detailStates[notification.id]?.isUnavailable == true {
                UnifiedEmptyStateCard(systemImage: "bell.slash", title: NotificationAuditCopy.unavailableTitle,
                    message: NotificationAuditCopy.unavailableMessage)
                    .accessibilityIdentifier("notificationDetail.unavailable")
            } else {
            messageCard

            if case .failed(let error)? = viewModel.detailStates[notification.id] {
                InlineMessageCard(style: .error, message: error.localizedDescription)
                PrimaryActionButton(title: AppStrings.Action.retry, systemImage: "arrow.clockwise") {
                    Task { await loadDetail() }
                }.accessibilityIdentifier("notificationDetail.retry")
            } else if !canAct {
                ProgressView().accessibilityIdentifier("notificationDetail.verifying")
            }
            if let error = viewModel.detailActionError(for: notification.id) {
                InlineMessageCard(style: .error, message: error.localizedDescription)
                    .accessibilityIdentifier("notificationDetail.error")
            }

            destinationAction

            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                Label(AppStrings.NotificationInbox.delete, systemImage: "trash")
                    .foregroundStyle(AppTheme.accentDestructiveForeground)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accentDestructive)
            .disabled(!canAct || isDeleting || viewModel.isBusy)
            .accessibilityIdentifier("notificationDetail.delete")

            if isDeleting {
                ProgressView().frame(maxWidth: .infinity)
            }
            }
        }
        .task(id: notification.id) {
            // Viewing is immediate even if the read receipt is waiting for a network.
            await loadDetail()
        }
        .onChange(of: canAct) { _, ready in if !ready { isShowingDeleteConfirmation = false } }
        .alert(
            AppStrings.NotificationInbox.deleteConfirmationTitle,
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button(AppStrings.NotificationInbox.delete, role: .destructive) {
                Task {
                    isDeleting = true
                    let deleted = await viewModel.delete(currentNotification)
                    isDeleting = false
                    if deleted { dismiss() }
                }
            }
            .accessibilityIdentifier("notificationDetail.confirmDelete")
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.NotificationInbox.deleteConfirmationMessage)
        }
    }

    private func loadDetail() async {
        if let fresh = await viewModel.prepareDetail(notificationID: notification.id) {
            await viewModel.markRead(fresh)
        }
    }

    private var messageCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        Image(systemName: "bell.badge")
                            .font(.title2.weight(.semibold))
                            .accessibilityHidden(true)
                        Text(currentNotification.localizedDetailContent.title)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("notificationDetail.title")
                } else {
                    Label(currentNotification.localizedDetailContent.title, systemImage: "bell.badge")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("notificationDetail.title")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        LocalizationStore.dateString(from: notification.createdAt, dateStyle: .long, timeStyle: .short),
                        systemImage: "calendar"
                    )
                    if let sender = currentNotification.detailSender {
                        Label(sender, systemImage: "person.crop.circle")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Text(currentNotification.localizedDetailContent.body)
                    .font(.body)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("notificationDetail.body")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var destinationAction: some View {
        if currentNotification.canOpenDestination {
            PrimaryActionButton(
                title: AppStrings.NotificationInbox.openDestination,
                loadingTitle: AppStrings.NotificationInbox.openDestination,
                isLoading: false,
                systemImage: "arrow.up.forward.app"
            ) {
                openDestination(currentNotification)
                dismiss()
            }
            .disabled(!canAct || isDeleting)
            .accessibilityIdentifier("notificationDetail.openDestination")
        } else {
            Text(currentNotification.actionType == .none
                 ? AppStrings.NotificationInbox.informationOnly
                 : AppStrings.NotificationInbox.destinationUnavailableMessage)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("notificationDetail.noDestination")
        }
    }
}
