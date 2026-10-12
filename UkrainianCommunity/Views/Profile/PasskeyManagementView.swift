import AuthenticationServices
import SwiftUI

struct PasskeyManagementView: View {
    let isTOTPAuthenticated: Bool

    @State private var passkeys: [PasskeyRecord] = []
    @State private var passkeyPendingRemoval: PasskeyRecord?
    @State private var isRegistering = false
    @State private var isRemoving = false
    @State private var message: String?

    var body: some View {
        ProfileSectionCard(
            title: AppStrings.AccountSecurity.passkeyTitle,
            subtitle: AppStrings.AccountSecurity.passkeySubtitle
        ) {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                if !passkeys.isEmpty {
                    InlineMessageCard(style: .success, message: AppStrings.AccountSecurity.passkeyEnabled)
                }

                ForEach(passkeys) { passkey in
                    HStack(spacing: AppTheme.dashboardSpacing) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                        Text(passkey.createdAt?.formatted(date: .abbreviated, time: .shortened)
                             ?? AppStrings.AccountSecurity.passkeyTitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        if isTOTPAuthenticated {
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
                    isEnabled: isTOTPAuthenticated && !isRegistering,
                    isLoading: isRegistering,
                    systemImage: "person.badge.key.fill"
                ) {
                    register()
                }
                .accessibilityIdentifier("accountSecurity.passkey.add")

                if !isTOTPAuthenticated {
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
