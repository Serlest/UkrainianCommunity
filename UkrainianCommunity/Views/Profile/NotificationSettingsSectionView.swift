import SwiftUI
import UIKit
import UserNotifications

struct NotificationSettingsSectionView: View {
    @Environment(\.openURL) private var openURL
    @State private var systemNotificationsDenied = false
    @ObservedObject var viewModel: ProfileViewModel
    let userID: String?
    let canSendTestNotification: Bool

    var body: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.notificationSettings,
            subtitle: AppStrings.Profile.notificationsSectionSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileSettingsToggleRow(
                    title: AppStrings.Profile.notificationsEnabled,
                    subtitle: AppStrings.Profile.notificationsEnabledSubtitle,
                    systemImage: "bell",
                    isOn: Binding(
                        get: { viewModel.notificationPreferences.notificationsEnabled },
                        set: { newValue in
                            guard let userID else { return }
                            Task {
                                await viewModel.setNotificationsEnabled(newValue, userID: userID)
                            }
                        }
                    )
                )
                .disabled(viewModel.isSavingNotificationPreferences || viewModel.isLoadingNotificationPreferences)

                if systemNotificationsDenied {
                    InlineMessageCard(style: .error, message: AppStrings.Profile.systemNotificationsDenied)
                    Button(AppStrings.Profile.openSystemNotificationSettings) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget)
                    .buttonStyle(.bordered)
                }

                ProfileSettingsToggleRow(
                    title: AppStrings.Profile.eventRemindersEnabled,
                    subtitle: AppStrings.Profile.eventRemindersEnabledSubtitle,
                    systemImage: "calendar.badge.clock",
                    isOn: Binding(
                        get: { viewModel.notificationPreferences.eventRemindersEnabled },
                        set: { newValue in
                            guard let userID else { return }
                            Task {
                                await viewModel.setEventRemindersEnabled(newValue, userID: userID)
                            }
                        }
                    )
                )
                .disabled(
                    !viewModel.notificationPreferences.notificationsEnabled
                        || viewModel.isSavingNotificationPreferences
                        || viewModel.isLoadingNotificationPreferences
                )

                ProfileSettingsPickerRow(
                    title: AppStrings.Profile.reminderLeadTime,
                    subtitle: AppStrings.Profile.reminderLeadTimeSubtitle,
                    systemImage: "clock"
                ) {
                    Picker(
                        AppStrings.Profile.reminderLeadTime,
                        selection: Binding(
                            get: { viewModel.notificationPreferences.reminderLeadMinutes },
                            set: { minutes in
                                guard let userID else { return }
                                Task {
                                    await viewModel.setReminderLeadMinutes(minutes, userID: userID)
                                }
                            }
                        )
                    ) {
                        ForEach([15, 30, 60, 120, 1_440], id: \.self) { minutes in
                            Text(reminderLeadTimeTitle(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .disabled(
                    !viewModel.notificationPreferences.notificationsEnabled
                        || !viewModel.notificationPreferences.eventRemindersEnabled
                        || viewModel.isSavingNotificationPreferences
                        || viewModel.isLoadingNotificationPreferences
                )

                if canSendTestNotification,
                   let userID,
                   viewModel.notificationPreferences.notificationsEnabled {
                    Button {
                        Task { await viewModel.sendTestNotification(userID: userID) }
                    } label: {
                        Label(
                            AppStrings.Profile.notificationTestButton,
                            systemImage: "bell.badge"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AppTheme.minimumInteractiveTarget)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSendingTestNotification)
                    .accessibilityIdentifier("notifications.sendTest")
                }

                if let message = viewModel.notificationPreferencesMessage {
                    InlineMessageCard(
                        style: notificationPreferencesMessageStyle(for: message),
                        message: message
                    )
                }
            }
        }
        .task { await refreshSystemPermission() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshSystemPermission() }
        }
    }

    private func refreshSystemPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        systemNotificationsDenied = settings.authorizationStatus == .denied
    }

    private func reminderLeadTimeTitle(_ minutes: Int) -> String {
        if minutes >= 1_440, minutes.isMultiple(of: 1_440) {
            return AppStrings.profileNotificationReminderDays(minutes / 1_440)
        }
        return AppStrings.profileNotificationReminderMinutes(minutes)
    }

    private func notificationPreferencesMessageStyle(for message: String) -> InlineMessageStyle {
        switch message {
        case AppStrings.Profile.notificationPreferencesSaved,
             AppStrings.Profile.notificationTestSent:
            .success
        default:
            .error
        }
    }
}
