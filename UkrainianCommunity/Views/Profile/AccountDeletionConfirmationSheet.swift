import AuthenticationServices
import FirebaseAuth
import SwiftUI

struct AccountDeletionConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    let currentUser: AppUser
    @State private var confirmationText = ""
    @State private var errorMessage: String?
    @State private var appleNonce: String?
    @State private var appleAuthorization: AppleCredentialAuthorization?
    @State private var isVerifyingAppleAccount = false

    private var canConfirmDeletion: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
            == AppStrings.Profile.deleteAccountConfirmationKeyword
    }

    private var needsAppleRevocation: Bool {
        Auth.auth().currentUser?.providerData.contains { $0.providerID == "apple.com" } == true
    }

    private var isBusy: Bool {
        isVerifyingAppleAccount || viewModel.isDeletingAccount
    }

    private var deletionRestriction: String? {
        if currentUser.globalRole.authorizationRole == .owner {
            return AppStrings.Profile.deleteAccountPlatformOwnerBlocked
        }
        if currentUser.communityMemberships.contains(where: { $0.role == .communityOwner }) {
            return AppStrings.Profile.deleteAccountOrganizationOwnerBlocked
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()
                    .allowsHitTesting(false)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        Text(AppStrings.Profile.deleteAccountConfirmMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        AppEditorSectionCard {
                            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                                Text(AppStrings.Profile.deleteAccountTypePrompt)
                                    .font(AppTheme.buttonLabelFont)
                                    .foregroundStyle(AppTheme.textPrimary)

                                TextField(
                                    AppStrings.Profile.deleteAccountConfirmationKeyword,
                                    text: $confirmationText
                                )
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .appEditorInputStyle()
                                .disabled(isBusy)
                                .accessibilityIdentifier("profile.delete_account.confirmation")

                                if let deletionRestriction {
                                    InlineMessageCard(style: .error, message: deletionRestriction)
                                } else if needsAppleRevocation {
                                    Text(AppStrings.Profile.deleteAccountAppleConfirmation)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    LocalizedAppleSignInButton(title: AppStrings.Auth.continueWithApple, action: startAppleDeletion)
                                    .disabled(!canConfirmDeletion || isBusy)
                                    .accessibilityIdentifier("profile.delete_account.apple")
                                } else {
                                    Button(role: .destructive) {
                                        Task {
                                            await performDeletion()
                                        }
                                    } label: {
                                        if viewModel.isDeletingAccount {
                                            Label(AppStrings.Profile.deleteAccountInProgress, systemImage: "hourglass")
                                        } else {
                                            Label(AppStrings.Profile.deleteAccountFinalAction, systemImage: "trash")
                                        }
                                    }
                                    .appActionButtonStyle(.primary)
                                    .tint(AppTheme.accentDestructive)
                                    .disabled(!canConfirmDeletion || isBusy)
                                    .accessibilityIdentifier("profile.delete_account.confirm")
                                }

                                if isVerifyingAppleAccount { ProgressView() }
                            }
                        }
                    }
                    .padding(AppTheme.pageHorizontal)
                    .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(AppStrings.Profile.deleteAccount)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) {
                        dismiss()
                    }
                    .disabled(isBusy)
                }
            }
            .interactiveDismissDisabled(isBusy)
            .alert(AppStrings.Profile.deleteAccount, isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )) {
                Button(AppStrings.Common.ok, role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .observesKeyboardDismissTaps()
        }
    }

    private func performDeletion() async {
        guard canConfirmDeletion, deletionRestriction == nil, !viewModel.isDeletingAccount else { return }

        if let message = await viewModel.deleteAccount(currentUser: currentUser) {
            errorMessage = message
        } else {
            confirmationText = ""
            dismiss()
        }
    }

    private func startAppleDeletion() {
        guard canConfirmDeletion, deletionRestriction == nil, !isBusy,
              Auth.auth().currentUser?.uid == currentUser.id,
              let anchor = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepareAppleDeletionRequest(request)
        guard appleNonce != nil else { return }
        isVerifyingAppleAccount = true
        let authorization = AppleCredentialAuthorization(anchor: anchor) { result in
            appleAuthorization = nil
            finishAppleDeletionRequest(result)
        }
        appleAuthorization = authorization
        authorization.start(request)
    }

    private func prepareAppleDeletionRequest(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        do {
            appleNonce = try AppleSignInCredentialFactory.prepare(request)
        } catch {
            appleNonce = nil
            errorMessage = AppStrings.Profile.deleteAccountAppleFailed
        }
    }

    private func finishAppleDeletionRequest(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result else {
            appleNonce = nil
            isVerifyingAppleAccount = false
            if case .failure(let error) = result,
               (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = AppStrings.Profile.deleteAccountAppleFailed
            }
            return
        }
        guard let nonce = appleNonce, canConfirmDeletion,
              deletionRestriction == nil, !viewModel.isDeletingAccount else {
            appleNonce = nil
            isVerifyingAppleAccount = false
            return
        }
        appleNonce = nil
        isVerifyingAppleAccount = true

        Task { @MainActor in
            defer { isVerifyingAppleAccount = false }
            do {
                guard let user = Auth.auth().currentUser, user.uid == currentUser.id else {
                    throw AuthVerificationError.noCurrentUser
                }
                let credential = try AppleSignInCredentialFactory.firebaseCredential(
                    from: authorization, nonce: nonce
                )
                let code = try AppleSignInCredentialFactory.authorizationCode(from: authorization)
                let refreshed = try await user.reauthenticate(with: credential)
                guard refreshed.user.uid == currentUser.id,
                      Auth.auth().currentUser?.uid == currentUser.id else {
                    throw AuthSessionTransitionError.backendSessionChanged
                }
                try await Auth.auth().revokeToken(withAuthorizationCode: code)
                await performDeletion()
            } catch {
                errorMessage = AppStrings.Profile.deleteAccountAppleFailed
            }
        }
    }
}
