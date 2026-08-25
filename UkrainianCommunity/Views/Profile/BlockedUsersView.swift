import SwiftUI

struct BlockedUsersView: View {
    @ObservedObject var coordinator: UserBlockingCoordinator
    @State private var searchText = ""
    @State private var userPendingUnblock: BlockedUser?

    private var filteredUsers: [BlockedUser] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return coordinator.blockedUsers }
        return coordinator.blockedUsers.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Safety.blockedUsersTitle,
            introSubtitle: AppStrings.Safety.blockedUsersIntro
        ) {
            if !coordinator.blockedUsers.isEmpty {
                blockedUsersSearchField
            }
            content
        }
        .confirmationDialog(
            AppStrings.Safety.unblockConfirmationTitle,
            isPresented: Binding(
                get: { userPendingUnblock != nil },
                set: { if !$0 { userPendingUnblock = nil } }
            ),
            presenting: userPendingUnblock
        ) { user in
            Button(AppStrings.Safety.unblockAction, role: .destructive) {
                Task { await coordinator.unblock(user) }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: { user in
            Text(AppStrings.Safety.unblockConfirmationMessage(user.displayName))
        }
    }

    @ViewBuilder
    private var content: some View {
        if coordinator.isLoading && coordinator.blockedUsers.isEmpty {
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
        } else if filteredUsers.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "magnifyingglass",
                title: AppStrings.Search.noResultsTitle,
                message: AppStrings.Search.noResultsMessage
            )
        } else {
            if let errorMessage = coordinator.loadErrorMessage ?? coordinator.errorMessage {
                InlineMessageCard(style: .error, message: errorMessage)
            }

            AppEditorSectionCard {
                VStack(spacing: 0) {
                    ForEach(Array(filteredUsers.enumerated()), id: \.element.id) { index, user in
                        blockedUserRow(user)

                        if index < filteredUsers.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var blockedUsersSearchField: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.textSecondary)
            TextField(AppStrings.Safety.blockedUsersSearchPlaceholder, text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
            if !searchText.isEmpty {
                AppSearchClearButton { searchText = "" }
            }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(minHeight: AppTheme.searchControlHeight)
        .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
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
                userPendingUnblock = user
            }
            .font(AppTheme.metadataStrongFont)
            .buttonStyle(.bordered)
            .disabled(coordinator.mutatingUserIDs.contains(user.targetUserId))
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}
