import AuthenticationServices
import SwiftUI

struct PasskeyManagementView: View {
    let isPrivileged: Bool
    let isTOTPAuthenticated: Bool

    @State private var passkeys: [PasskeyRecord] = []
    @State private var passkeyPendingRemoval: PasskeyRecord?
    @State private var isRegistering = false
    @State private var isRemoving = false
    @State private var message: String?

    private var requiresAuthenticator: Bool { isPrivileged && !isTOTPAuthenticated }

    var body: some View {
        ProfileSectionCard(
            title: AppStrings.AccountSecurity.passkeyTitle,
            subtitle: AppStrings.AccountSecurity.passkeySubtitle
        ) {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                ForEach(passkeys) { passkey in
                    HStack(spacing: AppTheme.dashboardSpacing) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                        Text(passkey.createdAt?.formatted(date: .abbreviated, time: .shortened)
                             ?? AppStrings.AccountSecurity.passkeyTitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        if !requiresAuthenticator {
                            Button(role: .destructive) {
                                passkeyPendingRemoval = passkey
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(isRemoving)
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
                    isEnabled: !requiresAuthenticator && !isRegistering,
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
        .task {
            await reload()
        }
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
        do {
            passkeys = try await PasskeyService.shared.listPasskeys()
        } catch {
            message = AppStrings.AccountSecurity.passkeyLoadFailed
        }
    }

    private func register() {
        isRegistering = true
        message = nil
        Task {
            defer { isRegistering = false }
            do {
                try await PasskeyService.shared.register()
                await reload()
            } catch {
                let nsError = error as NSError
                if nsError.domain == ASAuthorizationError.errorDomain,
                   nsError.code == ASAuthorizationError.canceled.rawValue { return }
                message = AppStrings.AccountSecurity.passkeyAddFailed
            }
        }
    }

    private func remove(_ passkey: PasskeyRecord) async {
        isRemoving = true
        message = nil
        defer { isRemoving = false }
        do {
            try await PasskeyService.shared.remove(passkey)
            passkeys.removeAll { $0.id == passkey.id }
        } catch {
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
                .foregroundStyle(AppTheme.primaryBlue)
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
