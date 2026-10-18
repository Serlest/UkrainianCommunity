import SwiftUI

struct AppNotificationBellConfiguration {
    var isVisible: Bool
    var unreadCount: Int
    var action: () -> Void

    static let hidden = AppNotificationBellConfiguration(
        isVisible: false,
        unreadCount: 0,
        action: {}
    )
}

private struct AppNotificationBellConfigurationKey: EnvironmentKey {
    static let defaultValue = AppNotificationBellConfiguration.hidden
}

extension EnvironmentValues {
    var appNotificationBellConfiguration: AppNotificationBellConfiguration {
        get { self[AppNotificationBellConfigurationKey.self] }
        set { self[AppNotificationBellConfigurationKey.self] = newValue }
    }
}

struct AppNotificationBellButton: View {
    @Environment(\.appNotificationBellConfiguration) private var configuration
    let action: (() -> Void)?

    init(action: (() -> Void)? = nil) {
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if configuration.isVisible {
            Button(action: action ?? configuration.action) {
                AppGlassIconLabel(systemImage: "bell")
            }
            .appGlassIconControl()
            .overlay(alignment: .topTrailing) {
                if configuration.unreadCount > 0 {
                    Text(badgeText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, configuration.unreadCount > 9 ? 4 : 0)
                        .background(AppTheme.accentDestructive, in: Capsule())
                        .offset(x: 2, y: -2)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(AppStrings.Home.notifications)
            .accessibilityIdentifier("notificationInbox.bell")
            .accessibilityValue(AppStrings.NotificationInbox.unreadCount(configuration.unreadCount))
        }
    }

    private var badgeText: String {
        configuration.unreadCount > 99 ? "99+" : "\(configuration.unreadCount)"
    }
}
