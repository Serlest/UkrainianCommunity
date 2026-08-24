import SwiftUI

struct BlockedUsersView: View {
    @ObservedObject var coordinator: UserBlockingCoordinator

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Safety.blockedUsersTitle,
            introSubtitle: AppStrings.Safety.blockedUsersIntro
        ) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if coordinator.isLoading {
            LoadingStateCard(title: AppStrings.Safety.blockedUsersTitle)
        } else if let errorMessage = coordinator.loadErrorMessage,
                  coordinator.blockedUsers.isEmpty {
            ErrorStateCard(
                title: AppStrings.Safety.blockedUsersLoadFailedTitle,
                message: errorMessage,
                retryTitle: AppStrings.Action.retry
            ) {
                Task { await coordinator.reload() }
            }
        } else if coordinator.blockedUsers.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "person.crop.circle.badge.checkmark",
                title: AppStrings.Safety.blockedUsersEmptyTitle,
                message: AppStrings.Safety.blockedUsersEmptyMessage
            )
        } else {
            AppEditorSectionCard {
                VStack(spacing: 0) {
                    ForEach(Array(coordinator.blockedUsers.enumerated()), id: \.element.id) { index, user in
                        blockedUserRow(user)

                        if index < coordinator.blockedUsers.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func blockedUserRow(_ user: BlockedUser) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.avatarURL) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                }
            }
            .frame(width: 44, height: 44)
            .background(AppTheme.accentPrimary.opacity(0.10), in: Circle())
            .clipShape(Circle())

            Text(user.displayName)
                .font(AppTheme.cardTitleFont)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button(AppStrings.Safety.unblockAction) {
                Task { await coordinator.unblock(user) }
            }
            .font(AppTheme.metadataStrongFont)
            .buttonStyle(.bordered)
            .disabled(coordinator.mutatingUserIDs.contains(user.targetUserId))
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}
