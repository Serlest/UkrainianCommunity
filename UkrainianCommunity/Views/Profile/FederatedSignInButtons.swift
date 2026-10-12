import AuthenticationServices
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import SwiftUI

struct FederatedSignInButtons: View {
    var showsHeading = true

    var body: some View {
        FederatedCredentialButtons(showsHeading: showsHeading) { credential in
            try await AuthService.shared.signIn(credential: credential)
        }
    }
}

struct PasskeySignInButton: View {
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: AppTheme.eventsMetadataSpacing) {
            Button {
                isSigningIn = true
                errorMessage = nil
                Task {
                    defer { isSigningIn = false }
                    do {
                        try await AuthService.shared.signInWithPasskey()
                    } catch {
                        let nsError = error as NSError
                        if nsError.domain == ASAuthorizationError.errorDomain,
                           nsError.code == ASAuthorizationError.canceled.rawValue { return }
                        errorMessage = AppStrings.Auth.passkeyFailed
                    }
                }
            } label: {
                AuthMethodButtonLabel(
                    title: AppStrings.Auth.passkeySignIn,
                    icon: .system("person.badge.key.fill")
                )
            }
            .buttonStyle(.plain)
            .disabled(isSigningIn)
            .accessibilityIdentifier("auth.passkey.signIn")

            if isSigningIn { ProgressView() }
            if let errorMessage {
                InlineMessageCard(style: .error, message: errorMessage)
            }
        }
    }
}

struct FederatedCredentialButtons: View {
    var showsHeading = true
    var allowedProviderIDs: Set<String> = ["apple.com", "google.com"]
    var appleButtonEnabled = true
    var isLinking = false
    let onCredential: @MainActor (AuthCredential) async throws -> Void

    @State private var appleNonce: String?
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private var isAppleAvailable: Bool {
        allowedProviderIDs.contains("apple.com")
            && Bundle.main.object(forInfoDictionaryKey: "UACAppleSignInEnabled") as? Bool == true
    }

    private var isGoogleAvailable: Bool {
        guard allowedProviderIDs.contains("google.com"),
              Bundle.main.object(forInfoDictionaryKey: "UACGoogleSignInEnabled") as? Bool == true else {
            return false
        }
        #if DEBUG
        return true
        #else
        // App Review 4.8 requires a privacy-preserving alternative alongside Google sign-in.
        return Bundle.main.object(forInfoDictionaryKey: "UACAppleSignInEnabled") as? Bool == true
        #endif
    }

    var body: some View {
        if isAppleAvailable || isGoogleAvailable {
            VStack(spacing: 12) {
                if showsHeading {
                    Text(AppStrings.Auth.otherSignInMethods)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isAppleAvailable {
                    SignInWithAppleButton(
                        isLinking ? .continue : .signIn,
                        onRequest: configureAppleRequest,
                        onCompletion: finishAppleRequest
                    )
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .disabled(isSigningIn || !appleButtonEnabled)
                        .accessibilityIdentifier(isLinking ? "accountSecurity.provider.apple" : "auth.provider.apple")
                }

                if isGoogleAvailable {
                    Button(action: startGoogleSignIn) {
                        AuthMethodButtonLabel(
                            title: isLinking
                                ? AppStrings.AccountSecurity.linkGoogle
                                : AppStrings.Auth.continueWithGoogle,
                            icon: .asset("GoogleSignInIcon")
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSigningIn)
                    .accessibilityIdentifier(isLinking ? "accountSecurity.provider.google" : "auth.provider.google")
                }

                if isSigningIn { ProgressView() }
                if let errorMessage {
                    InlineMessageCard(style: .error, message: errorMessage)
                }
            }
        }
    }

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        do {
            appleNonce = try AppleSignInCredentialFactory.prepare(request)
        } catch {
            appleNonce = nil
            errorMessage = isLinking
                ? AppStrings.AccountSecurity.linkFailed
                : AppStrings.Auth.providerSignInFailed
        }
    }

    private func finishAppleRequest(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            appleNonce = nil
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = isLinking
                    ? AppStrings.AccountSecurity.linkFailed
                    : AppStrings.Auth.providerSignInFailed
            }
        case .success(let authorization):
            guard let nonce = appleNonce else {
                appleNonce = nil
                errorMessage = isLinking
                    ? AppStrings.AccountSecurity.linkFailed
                    : AppStrings.Auth.providerSignInFailed
                return
            }
            appleNonce = nil
            do {
                finishSignIn(with: try AppleSignInCredentialFactory.firebaseCredential(
                    from: authorization, nonce: nonce
                ))
            } catch {
                errorMessage = isLinking
                    ? AppStrings.AccountSecurity.linkFailed
                    : AppStrings.Auth.providerSignInFailed
            }
        }
    }

    private func startGoogleSignIn() {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              !clientID.isEmpty,
              let presenter = Self.presentingViewController() else {
            errorMessage = AppStrings.Auth.googleConfigurationMissing
            return
        }

        errorMessage = nil
        isSigningIn = true
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
            if let error {
                isSigningIn = false
                let googleError = error as NSError
                if googleError.domain != kGIDSignInErrorDomain || googleError.code != -5 {
                    errorMessage = isLinking
                        ? AppStrings.AccountSecurity.linkFailed
                        : AppStrings.Auth.providerSignInFailed
                }
                return
            }
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                isSigningIn = false
                errorMessage = isLinking
                    ? AppStrings.AccountSecurity.linkFailed
                    : AppStrings.Auth.providerSignInFailed
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            finishSignIn(with: credential)
        }
    }

    private func finishSignIn(with credential: AuthCredential) {
        errorMessage = nil
        isSigningIn = true
        Task { @MainActor in
            defer { isSigningIn = false }
            do {
                try await onCredential(credential)
            } catch {
                if !isLinking,
                   error as? AuthMultiFactorFlowError == .secondFactorRequired {
                    return
                }
                if isLinking {
                    errorMessage = providerLinkErrorMessage(error)
                    return
                }
                if let verification = error as? AuthVerificationError {
                    switch verification {
                    case .emailNotVerified:
                        return
                    case .accountDeletionCompleted:
                        errorMessage = AppStrings.Profile.deleteAccountCompleted
                        return
                    default:
                        break
                    }
                }
                let code = AuthErrorCode(rawValue: (error as NSError).code)
                errorMessage = code == .accountExistsWithDifferentCredential
                    ? AppStrings.Auth.accountUsesAnotherSignInMethod
                    : AppStrings.Auth.providerSignInFailed
            }
        }
    }

    private func providerLinkErrorMessage(_ error: Error) -> String {
        if let linkError = error as? AccountProviderLinkError {
            switch linkError {
            case .protectedSessionRequired:
                return AppStrings.AccountSecurity.linkTOTPRequired
            case .recentSignInRequired:
                return AppStrings.AccountSecurity.linkRecentSignInRequired
            case .alreadyLinked:
                return AppStrings.AccountSecurity.linkAlreadyConnected
            case .sessionChanged, .unavailable:
                return AppStrings.AccountSecurity.linkSessionChanged
            case .emailNotVerified:
                return AppStrings.Auth.emailVerificationStillPending
            case .unsupportedProvider, .linkNotConfirmed:
                return AppStrings.AccountSecurity.linkFailed
            }
        }
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .credentialAlreadyInUse, .emailAlreadyInUse, .accountExistsWithDifferentCredential:
            return AppStrings.AccountSecurity.linkBelongsToAnotherAccount
        case .providerAlreadyLinked:
            return AppStrings.AccountSecurity.linkAlreadyConnected
        case .requiresRecentLogin:
            return AppStrings.AccountSecurity.linkRecentSignInRequired
        default:
            return AppStrings.AccountSecurity.linkFailed
        }
    }

    private static func presentingViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var current = windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = current?.presentedViewController { current = presented }
        return current
    }
}
