import AuthenticationServices
import SwiftUI
import FirebaseAuth

struct PasskeyManagementView: View {
    @Environment(\.authInteraction) private var interaction
    let userID: String?
    let isPrivileged: Bool
    let isTOTPAuthenticated: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var passkeys: [PasskeyRecord] = []
    @State private var passkeyPendingRemoval: PasskeyRecord?
    @State private var isRegistering = false
    @State private var isRemoving = false
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var loadFailed = false
    @State private var message: String?

    private var requiresAuthenticator: Bool { isPrivileged && !isTOTPAuthenticated }

    var body: some View {
        ProfileSectionCard(
            title: AppStrings.AccountSecurity.passkeyTitle,
            subtitle: AppStrings.AccountSecurity.passkeySubtitle
        ) {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                if isLoading {
                    ProgressView()
                        .accessibilityLabel(AppStrings.Common.loading)
                }
                if loadFailed {
                    InlineMessageCard(style: .error, message: AppStrings.AccountSecurity.passkeyLoadFailed)
                    Button(AppStrings.Action.retry) { Task { await reload() } }
                        .disabled(isLoading)
                        .accessibilityIdentifier("accountSecurity.passkey.retry")
                }
                ForEach(passkeys) { passkey in
                    (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: AppTheme.dashboardSpacing))) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                        Text(passkey.createdAt?.formatted(date: .abbreviated, time: .shortened)
                             ?? AppStrings.AccountSecurity.passkeyTitle)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(AppTheme.textPrimary)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        if !requiresAuthenticator {
                            Button(role: .destructive) {
                                passkeyPendingRemoval = passkey
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(isRemoving || isRegistering || isLoading || loadFailed)
                            .accessibilityLabel(AppStrings.AccountSecurity.passkeyRemove)
                        }
                    }
                    .padding(AppTheme.cardPadding)
                    .background(AppTheme.surfaceSecondary,
                                in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                }

                if let message {
                    InlineMessageCard(style: .error, message: message)
                }

                PrimaryActionButton(
                    title: passkeys.isEmpty
                        ? AppStrings.AccountSecurity.passkeyAdd
                        : AppStrings.AccountSecurity.passkeyAddAnother,
                    loadingTitle: AppStrings.AccountSecurity.passkeyAdding,
                    isEnabled: hasLoaded && !loadFailed && !requiresAuthenticator && !isRegistering && !isRemoving && !isLoading,
                    isLoading: isRegistering,
                    systemImage: "person.badge.key.fill"
                ) {
                    register()
                }
                .accessibilityIdentifier("accountSecurity.passkey.add")

                if requiresAuthenticator {
                    Text(AppStrings.AccountSecurity.passkeyRequiresAuthenticator)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .task(id: userID) { await reload() }
        .alert(item: $passkeyPendingRemoval) { passkey in
            Alert(
                title: Text(AppStrings.AccountSecurity.passkeyRemove),
                message: Text(AppStrings.AccountSecurity.passkeyRemoveConfirm),
                primaryButton: .destructive(Text(AppStrings.AccountSecurity.passkeyRemove)) {
                    Task { await remove(passkey) }
                },
                secondaryButton: .cancel(Text(AppStrings.Common.cancel))
            )
        }
    }

    private func reload() async {
        guard !isLoading, Auth.auth().currentUser?.uid == userID else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let loaded = try await PasskeyService.shared.listPasskeys(expectedUserID: userID)
            guard !Task.isCancelled, Auth.auth().currentUser?.uid == userID else { return }
            passkeys = loaded
            hasLoaded = true
        } catch {
            guard !Task.isCancelled, Auth.auth().currentUser?.uid == userID else { return }
            loadFailed = true
        }
    }

    private func register() {
        guard Auth.auth().currentUser?.uid == userID, !isRegistering, !isRemoving,
              let lease = AuthInteractionCoordinator.begin(in: interaction) else { return }
        isRegistering = true
        message = nil
        Task {
            defer { isRegistering = false; interaction?.finish(lease) }
            do {
                try await PasskeyService.shared.register(expectedUserID: userID)
                guard Auth.auth().currentUser?.uid == userID else { return }
                await reload()
            } catch {
                let nsError = error as NSError
                if nsError.domain == ASAuthorizationError.errorDomain,
                   nsError.code == ASAuthorizationError.canceled.rawValue { return }
                guard Auth.auth().currentUser?.uid == userID else { return }
                message = AppStrings.AccountSecurity.passkeyAddFailed
            }
        }
    }

    private func remove(_ passkey: PasskeyRecord) async {
        guard Auth.auth().currentUser?.uid == userID, !isRemoving, !isRegistering,
              let lease = AuthInteractionCoordinator.begin(in: interaction) else { return }
        defer { interaction?.finish(lease) }
        isRemoving = true
        message = nil
        defer { isRemoving = false }
        do {
            try await PasskeyService.shared.remove(passkey, expectedUserID: userID)
            guard Auth.auth().currentUser?.uid == userID else { return }
            passkeys.removeAll { $0.id == passkey.id }
        } catch {
            guard Auth.auth().currentUser?.uid == userID else { return }
            message = AppStrings.AccountSecurity.passkeyRemoveFailed
        }
    }
}

struct PasskeyEnrollmentOfferView: View {
    let onFinish: () -> Void
    @State private var isRegistering = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            Image(systemName: "person.badge.key.fill")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .accessibilityHidden(true)

            Text(AppStrings.AccountSecurity.passkeyOfferTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.AccountSecurity.passkeyOfferSubtitle)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                InlineMessageCard(style: .error, message: errorMessage)
            }

            PrimaryActionButton(
                title: AppStrings.AccountSecurity.passkeyAdd,
                loadingTitle: AppStrings.AccountSecurity.passkeyAdding,
                isEnabled: !isRegistering,
                isLoading: isRegistering,
                systemImage: "key.fill"
            ) {
                Task {
                    isRegistering = true
                    defer { isRegistering = false }
                    do {
                        try await PasskeyService.shared.register()
                        onFinish()
                    } catch {
                        let nsError = error as NSError
                        if nsError.domain == ASAuthorizationError.errorDomain,
                           nsError.code == ASAuthorizationError.canceled.rawValue { return }
                        errorMessage = AppStrings.AccountSecurity.passkeyAddFailed
                    }
                }
            }

            Button(AppStrings.AccountSecurity.passkeyLater, action: onFinish)
                .accessibilityIdentifier("auth.passkeySuggestion.later")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .disabled(isRegistering)
        }
        .padding(AppTheme.pageHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isRegistering)
    }
}
