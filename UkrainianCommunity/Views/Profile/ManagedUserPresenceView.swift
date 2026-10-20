import SwiftUI

struct ManagedUserPresenceView: View {
    let userID: String
    let actor: AppUser?
    let refreshToken: String
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: ManagedUserPresenceViewModel
    @State private var retry = 0

    private var loadKey: String {
        "\(userID)|\(actor?.id ?? "")|\(PermissionService.canManageUsers(user: actor))|\(scenePhase == .background)|\(retry)|\(refreshToken)"
    }

    var body: some View {
        if PermissionService.canManageUsers(user: actor) {
            VStack(alignment: .leading, spacing: 8) {
                if let snapshot = model.snapshot {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        ManagedUserPresenceStatus(snapshot: snapshot)
                    }
                    if model.failed {
                        Label(AppStrings.UserManagement.presenceStale, systemImage: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("user.presence.stale")
                        Button(AppStrings.UserManagement.retry) { retry += 1 }
                            .font(.caption)
                            .accessibilityHint(AppStrings.UserManagement.presenceUnavailable)
                    }
                } else if model.failed {
                    UserManagementMetadataRow(systemImage: "wifi.exclamationmark", title: AppStrings.UserManagement.presenceTitle,
                                              value: AppStrings.UserManagement.presenceUnavailable)
                    Button(AppStrings.UserManagement.retry) { retry += 1 }
                        .font(.subheadline)
                } else {
                    UserManagementMetadataRow(
                        systemImage: "circle.dotted",
                        title: AppStrings.UserManagement.presenceTitle,
                        value: AppStrings.UserManagement.presenceLoading
                    )
                }
                Text(AppStrings.UserManagement.presenceAccuracy)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("user.presence.section")
            .task(id: loadKey) {
                guard scenePhase != .background else { model.cancelPending(); return }
                repeat {
                    await model.refresh(userID: userID, actor: actor)
                    guard !Task.isCancelled else { return }
                    do { try await Task.sleep(for: model.pollingDelay) } catch { return }
                } while !Task.isCancelled
            }
            .onDisappear { model.cancelPending() }
        }
    }
}

struct ManagedUserPresenceStatus: View {
    let snapshot: ManagedUserPresenceSnapshot
    private let isOnline: Bool

    init(snapshot: ManagedUserPresenceSnapshot) {
        self.snapshot = snapshot
        // Recompute in TimelineView's content closure so expiry changes a stored
        // view input even when no new server response has arrived.
        self.isOnline = snapshot.isOnline()
    }

    var body: some View {
        if isOnline {
            UserManagementMetadataRow(
                systemImage: "circle.fill",
                title: AppStrings.UserManagement.presenceTitle,
                value: AppStrings.UserManagement.presenceOnline,
                tint: AppTheme.accentSuccessForeground
            )
            .accessibilityIdentifier("user.presence.online")
        } else if let date = snapshot.lastSeenAt {
            UserManagementMetadataRow(systemImage: "clock", title: AppStrings.UserManagement.presenceLastSeen,
                value: LocalizationStore.dateString(from: date, dateStyle: .medium, timeStyle: .short))
                .accessibilityIdentifier("user.presence.lastSeen")
        } else {
            UserManagementMetadataRow(systemImage: "clock", title: AppStrings.UserManagement.presenceTitle,
                                      value: AppStrings.UserManagement.presenceUnknown)
                .accessibilityIdentifier("user.presence.unknown")
        }
    }
}
