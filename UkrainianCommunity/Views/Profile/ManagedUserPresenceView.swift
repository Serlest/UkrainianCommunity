import SwiftUI

struct ManagedUserPresenceView: View {
    let userID: String
    let actor: AppUser?
    let refreshToken: String
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: ManagedUserPresenceViewModel
    @State private var retry = 0

    private var loadKey: String {
        "\(userID)|\(actor?.id ?? "")|\(PermissionService.canManageUsers(user: actor))|\(scenePhase)|\(retry)|\(refreshToken)"
    }

    var body: some View {
        if PermissionService.canManageUsers(user: actor) {
            VStack(alignment: .leading, spacing: 8) {
                if model.failed {
                    UserManagementMetadataRow(systemImage: "wifi.exclamationmark", title: AppStrings.UserManagement.presenceTitle,
                                              value: AppStrings.UserManagement.presenceUnavailable)
                    Button(AppStrings.UserManagement.retry) { retry += 1 }
                        .font(.subheadline)
                } else if let snapshot = model.snapshot {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        ManagedUserPresenceStatus(snapshot: snapshot)
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text(AppStrings.UserManagement.presenceLoading).font(.subheadline)
                    }
                }
            }
            .task(id: loadKey) {
                guard scenePhase == .active else { model.cancelPending(); return }
                repeat {
                    await model.refresh(userID: userID, actor: actor)
                    guard !Task.isCancelled else { return }
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
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
        VStack(alignment: .leading, spacing: 8) {
            if isOnline {
                Label(AppStrings.UserManagement.presenceOnline, systemImage: "circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentSuccessForeground)
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
}
