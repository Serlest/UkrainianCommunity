import SwiftUI

private let notificationReminderLeadMinuteOptions = [15, 30, 60, 120, 1440]

struct NotificationSettingsSectionView: View {
    @ObservedObject var viewModel: ProfileViewModel
    let userID: String?

    var body: some View {
        ProfileSectionCard(
            title: AppStrings.Profile.notificationSettings,
            subtitle: AppStrings.Profile.notificationsSectionSubtitle
        ) {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ProfileSettingsToggleRow(
                    title: AppStrings.Profile.notificationsEnabled,
                    subtitle: AppStrings.Profile.notificationsEnabledSubtitle,
                    systemImage: "bell.badge",
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
                    systemImage: "clock.badge"
                ) {
                    Picker(
                        AppStrings.Profile.reminderLeadTime,
                        selection: Binding(
                            get: { viewModel.notificationPreferences.reminderLeadMinutes },
                            set: { newValue in
                                guard let userID else { return }
                                Task {
                                    await viewModel.setReminderLeadMinutes(newValue, userID: userID)
                                }
                            }
                        )
                    ) {
                        ForEach(notificationReminderLeadMinuteOptions, id: \.self) { minutes in
                            Text(notificationReminderLeadTimeText(minutes: minutes)).tag(minutes)
                        }
                    }
                    .labelsHidden()
                }
                .disabled(
                    !viewModel.notificationPreferences.notificationsEnabled
                    || !viewModel.notificationPreferences.eventRemindersEnabled
                    || viewModel.isSavingNotificationPreferences
                    || viewModel.isLoadingNotificationPreferences
                )

                if viewModel.notificationPreferences.notificationsEnabled {
                    Button {
                        guard let userID else { return }
                        Task {
                            await viewModel.sendTestNotification(userID: userID)
                        }
                    } label: {
                        Label(AppStrings.Profile.notificationTestButton, systemImage: "paperplane")
                            .frame(maxWidth: .infinity)
                    }
                    .appActionButtonStyle(.secondary)
                    .disabled(viewModel.isSendingTestNotification)
                    .accessibilityIdentifier("profile.notifications.test")
                }

                if let message = viewModel.notificationPreferencesMessage {
                    InlineMessageCard(
                        style: notificationPreferencesMessageStyle(for: message),
                        message: message
                    )
                }
            }
        }
    }

    private func notificationReminderLeadTimeText(minutes: Int) -> String {
        if minutes >= 1440, minutes % 1440 == 0 {
            return AppStrings.profileNotificationReminderDays(minutes / 1440)
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
