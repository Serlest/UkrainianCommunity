import AuthenticationServices
import FirebaseFunctions
import Foundation
import UIKit

enum PasskeyError: Error {
    case invalidServerResponse
    case unavailable
}

struct PasskeyRecord: Identifiable, Equatable {
    let id: String
    let createdAt: Date?
}

@MainActor
final class PasskeyService {
    static let shared = PasskeyService()

    private let functions = Functions.functions(region: "europe-west3")
    private var authorization: PasskeyAuthorization?

    func register() async throws {
        let begin = try await call("beginPasskeyRegistration", data: [:])
        let requestID = try required(begin, "requestID")
        let challenge = try required(begin, "challenge")
        let userID = try required(begin, "userID")
        let userName = try required(begin, "userName")
        let rpID = try required(begin, "rpID")
        guard let challengeData = Data(base64URL: challenge),
              let userData = Data(base64URL: userID) else {
            throw PasskeyError.invalidServerResponse
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let request = provider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: userName,
            userID: userData
        )
        let credential = try await perform(request)
        guard let registration = credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestation = registration.rawAttestationObject else {
            throw PasskeyError.invalidServerResponse
        }
        let id = registration.credentialID.base64URLString
        _ = try await call("finishPasskeyRegistration", data: [
            "requestID": requestID,
            "credential": [
                "id": id,
                "rawId": id,
                "response": [
                    "attestationObject": attestation.base64URLString,
                    "clientDataJSON": registration.rawClientDataJSON.base64URLString
                ]
            ]
        ])
    }

    func signInToken() async throws -> String {
        let begin = try await call("beginPasskeySignIn", data: [:])
        let requestID = try required(begin, "requestID")
        let challenge = try required(begin, "challenge")
        let rpID = try required(begin, "rpID")
        guard let challengeData = Data(base64URL: challenge) else {
            throw PasskeyError.invalidServerResponse
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let credential = try await perform(provider.createCredentialAssertionRequest(challenge: challengeData))
        guard let assertion = credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion,
              let authenticatorData = assertion.rawAuthenticatorData,
              let signature = assertion.signature else {
            throw PasskeyError.invalidServerResponse
        }
        let id = assertion.credentialID.base64URLString
        var assertionResponse = [
            "clientDataJSON": assertion.rawClientDataJSON.base64URLString,
            "authenticatorData": authenticatorData.base64URLString,
            "signature": signature.base64URLString
        ]
        if let userID = assertion.userID {
            assertionResponse["userHandle"] = userID.base64URLString
        }
        let result = try await call("finishPasskeySignIn", data: [
            "requestID": requestID,
            "credential": [
                "id": id,
                "rawId": id,
                "response": assertionResponse
            ]
        ])
        return try required(result, "token")
    }

    func listPasskeys() async throws -> [PasskeyRecord] {
        let result = try await call("listMyPasskeys", data: [:])
        guard let raw = result["passkeys"] as? [[String: Any]] else {
            throw PasskeyError.invalidServerResponse
        }
        return try raw.map { entry in
            let id = try required(entry, "id")
            let date = (entry["createdAt"] as? String).flatMap(ISO8601DateFormatter().date(from:))
            return PasskeyRecord(id: id, createdAt: date)
        }
    }

    func remove(_ passkey: PasskeyRecord) async throws {
        _ = try await call("removeMyPasskey", data: ["id": passkey.id])
    }

    private func call(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        let result = try await functions.httpsCallable(name).call(data)
        guard let dictionary = result.data as? [String: Any] else {
            throw PasskeyError.invalidServerResponse
        }
        return dictionary
    }

    private func required(_ data: [String: Any], _ key: String) throws -> String {
        guard let value = data[key] as? String, !value.isEmpty else {
            throw PasskeyError.invalidServerResponse
        }
        return value
    }

    private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorizationCredential {
        guard authorization == nil else { throw PasskeyError.unavailable }
        let delegate = PasskeyAuthorization()
        authorization = delegate
        defer { authorization = nil }
        return try await delegate.perform(request)
    }
}

@MainActor
private final class PasskeyAuthorization: NSObject,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationCredential, Error>?
    private var controller: ASAuthorizationController?

    func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorizationCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization.credential)
        continuation = nil
        self.controller = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        self.controller = nil
    }
}

private extension Data {
    var base64URLString: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL: String) {
        let base64 = base64URL.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else { return nil }
        self = data
    }
}
