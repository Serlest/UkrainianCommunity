import SwiftUI

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

                if let message = viewModel.notificationPreferencesMessage {
                    InlineMessageCard(
                        style: notificationPreferencesMessageStyle(for: message),
                        message: message
                    )
                }
            }
        }
    }

    private func notificationPreferencesMessageStyle(for message: String) -> InlineMessageStyle {
        switch message {
        case AppStrings.Profile.notificationPreferencesSaved:
            .success
        default:
            .error
        }
    }
}
