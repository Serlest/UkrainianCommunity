import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation
import Security

enum AppleSignInCredentialError: Error {
    case randomUnavailable
    case credentialUnavailable
    case authorizationCodeUnavailable
}

enum AppleSignInCredentialFactory {
    static func prepare(_ request: ASAuthorizationAppleIDRequest) throws -> String {
        let nonce = try randomNonce()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return nonce
    }

    static func firebaseCredential(
        from authorization: ASAuthorization,
        nonce: String
    ) throws -> AuthCredential {
        guard let account = authorization.credential as? ASAuthorizationAppleIDCredential,
              let token = account.identityToken,
              let tokenString = String(data: token, encoding: .utf8) else {
            throw AppleSignInCredentialError.credentialUnavailable
        }
        return OAuthProvider.appleCredential(
            withIDToken: tokenString,
            rawNonce: nonce,
            fullName: account.fullName
        )
    }

    static func authorizationCode(from authorization: ASAuthorization) throws -> String {
        guard let account = authorization.credential as? ASAuthorizationAppleIDCredential,
              let code = account.authorizationCode,
              let codeString = String(data: code, encoding: .utf8) else {
            throw AppleSignInCredentialError.authorizationCodeUnavailable
        }
        return codeString
    }

    private static func randomNonce() throws -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AppleSignInCredentialError.randomUnavailable
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }
}
