import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Security
import SwiftUI

struct FederatedSignInButtons: View {
    @State private var appleNonce: String?
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        AppEditorSectionCard {
            VStack(spacing: 12) {
                Text(AppStrings.Auth.otherSignInMethods)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if Bundle.main.object(forInfoDictionaryKey: "UACAppleSignInEnabled") as? Bool == true {
                    SignInWithAppleButton(.signIn, onRequest: configureAppleRequest, onCompletion: finishAppleRequest)
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .disabled(isSigningIn)
                        .accessibilityIdentifier("auth.provider.apple")
                }

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

                if isSigningIn { ProgressView() }
                if let errorMessage {
                    InlineMessageCard(style: .error, message: errorMessage)
                }
            }
        }
    }

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    private func finishAppleRequest(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            appleNonce = nil
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = AppStrings.Auth.providerSignInFailed
            }
        case .success(let authorization):
            guard let account = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let token = account.identityToken,
                  let tokenString = String(data: token, encoding: .utf8),
                  let nonce = appleNonce else {
                appleNonce = nil
                errorMessage = AppStrings.Auth.providerSignInFailed
                return
            }
            appleNonce = nil
            let credential = OAuthProvider.appleCredential(
                withIDToken: tokenString,
                rawNonce: nonce,
                fullName: account.fullName
            )
            finishSignIn(with: credential)
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

    private static func randomNonce() -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
