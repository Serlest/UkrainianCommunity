import AuthenticationServices
import SwiftUI

/// Uses Apple's unmodified official artwork, with the app's selected language.
struct LocalizedAppleSignInButton: View {
    let title: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var height = 50.0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image("AppleSignInLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: height * 31 / 44, height: height)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 16)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 16)
            .background(.black, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

@MainActor
final class AppleCredentialAuthorization: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var controller: ASAuthorizationController?
    private let completion: (Result<ASAuthorization, Error>) -> Void
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor, completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.anchor = anchor
        self.completion = completion
    }

    func start(_ request: ASAuthorizationAppleIDRequest) {
        let controller = ASAuthorizationController(authorizationRequests: [request])
        self.controller = controller
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
        self.controller = nil
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
        self.controller = nil
    }
}
