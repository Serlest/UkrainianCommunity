import SwiftUI

enum GuestAccessAction: String, Identifiable {
    case likes
    case registration
    case feedback
    case profileEditing
    case management

    var id: String { rawValue }

    var capabilityTitle: String {
        switch self {
        case .likes:
            AppStrings.Common.likes
        case .registration:
            AppStrings.Profile.eventRegistration
        case .feedback:
            AppStrings.Feedback.title
        case .profileEditing:
            AppStrings.Profile.editProfile
        case .management:
            AppStrings.Profile.contentManagement
        }
    }
}

private struct GuestAccessAlertModifier: ViewModifier {
    @EnvironmentObject private var authState: AuthState
    @Binding var action: GuestAccessAction?

    func body(content: Content) -> some View {
        content.alert(
            AppStrings.Auth.requiredTitle,
            isPresented: Binding(
                get: { action != nil },
                set: { isPresented in
                    if !isPresented {
                        action = nil
                    }
                }
            ),
            presenting: action
        ) { _ in
            Button(AppStrings.Auth.signIn) {
                authState.presentAuthFlow(.login)
            }

            Button(AppStrings.Auth.createAccount) {
                authState.presentAuthFlow(.register)
            }

            Button(AppStrings.Common.ok, role: .cancel) {}
        } message: { action in
            Text(AppStrings.authRequiredMessage(for: action.capabilityTitle))
        }
    }
}

extension View {
    func guestAccessAlert(_ action: Binding<GuestAccessAction?>) -> some View {
        modifier(GuestAccessAlertModifier(action: action))
    }
}
