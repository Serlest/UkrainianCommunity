import SwiftUI

struct NotificationDetailView: View {
    let notification: AppNotification
    @ObservedObject var viewModel: NotificationInboxViewModel
    let openDestination: (AppNotification) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false

    private var currentNotification: AppNotification {
        viewModel.notifications.first { $0.id == notification.id } ?? notification
    }

    var body: some View {
        PushedScreenShell(
            title: AppStrings.NotificationInbox.detailTitle,
            showsBackButton: false
        ) {
            AppGlassIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.NotificationInbox.closeDetails) {
                dismiss()
            }
            .accessibilityIdentifier("notificationDetail.close")
        } content: {
            messageCard

            if let error = viewModel.error {
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
            .disabled(isDeleting)
            .accessibilityIdentifier("notificationDetail.delete")

            if isDeleting {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: notification.id) {
            // Viewing is immediate even if the read receipt is waiting for a network.
            await viewModel.markRead(currentNotification)
        }
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

    private var messageCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                Label(currentNotification.localizedDetailContent.title, systemImage: "bell.badge")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("notificationDetail.title")

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
            .disabled(isDeleting)
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
