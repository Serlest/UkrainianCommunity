import SwiftUI

enum GuestAccessAction: String, Identifiable {
    case likes
    case registration
    case feedback
    case profileEditing
    case management
    case bookmarks
    case comments

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
        case .bookmarks:
            AppStrings.Action.save
        case .comments:
            AppStrings.Common.comments
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
        ) { action in
            let dialog = AppGuestAccessDialog(action: action)

            Button(dialog.signInTitle) {
                authState.presentAuthFlow(.login)
            }

            Button(dialog.createAccountTitle) {
                authState.presentAuthFlow(.register)
            }

            Button(dialog.dismissTitle, role: .cancel) {}
        } message: { action in
            Text(AppGuestAccessDialog(action: action).message)
        }
    }
}

extension View {
    func guestAccessAlert(_ action: Binding<GuestAccessAction?>) -> some View {
        modifier(GuestAccessAlertModifier(action: action))
    }
}
