import AuthenticationServices
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import SwiftUI

struct FederatedSignInButtons: View {
    @State private var appleNonce: String?
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private var isAppleAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "UACAppleSignInEnabled") as? Bool == true
    }

    private var isGoogleAvailable: Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "UACGoogleSignInEnabled") as? Bool == true else {
            return false
        }
        #if DEBUG
        return true
        #else
        // App Review 4.8 requires a privacy-preserving alternative alongside Google sign-in.
        return isAppleAvailable
        #endif
    }

    var body: some View {
        if isAppleAvailable || isGoogleAvailable {
            VStack(spacing: 12) {
                Text(AppStrings.Auth.otherSignInMethods)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isAppleAvailable {
                    SignInWithAppleButton(.signIn, onRequest: configureAppleRequest, onCompletion: finishAppleRequest)
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .disabled(isSigningIn)
                        .accessibilityIdentifier("auth.provider.apple")
                }

                if isGoogleAvailable {
                    Button(action: startGoogleSignIn) {
                        HStack(spacing: 10) {
                            Image("GoogleSignInIcon")
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(AppStrings.Auth.continueWithGoogle)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.black.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSigningIn)
                    .accessibilityIdentifier("auth.provider.google")
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
            errorMessage = AppStrings.Auth.providerSignInFailed
        }
    }

    private func finishAppleRequest(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            appleNonce = nil
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = AppStrings.Auth.providerSignInFailed
            }
        case .success(let authorization):
            guard let nonce = appleNonce else {
                appleNonce = nil
                errorMessage = AppStrings.Auth.providerSignInFailed
                return
            }
            appleNonce = nil
            do {
                finishSignIn(with: try AppleSignInCredentialFactory.firebaseCredential(
                    from: authorization, nonce: nonce
                ))
            } catch {
                errorMessage = AppStrings.Auth.providerSignInFailed
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
                    errorMessage = AppStrings.Auth.providerSignInFailed
                }
                return
            }
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                isSigningIn = false
                errorMessage = AppStrings.Auth.providerSignInFailed
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
                try await AuthService.shared.signIn(credential: credential)
            } catch {
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

    private static func presentingViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var current = windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = current?.presentedViewController { current = presented }
        return current
    }
}
