import Combine
import SwiftUI

/// Routes within one authentication flow. Switching account modes replaces the
/// current branch rather than stacking Login -> Register -> Login indefinitely.
enum AuthEntryRoute: Hashable {
    case methods
    case login(email: String)
    case registration(email: String, emailMethod: Bool)
    case passwordReset(email: String)
}

@MainActor
final class AuthEntryNavigation: ObservableObject {
    @Published var path: [AuthEntryRoute] = []
    var resumedLoginEmail: String?
    let root: AuthFlowDestination

    init(root: AuthFlowDestination) { self.root = root }

    func switchMode(to route: AuthEntryRoute) {
        if case .login(let email) = route, root == .login { resumedLoginEmail = email }
        switch (root, route) {
        case (.landing, .methods), (.login, .login), (.register, .registration(_, false)):
            path = []
        default:
            path = [route]
        }
    }
}

private struct AuthEntryNavigationKey: EnvironmentKey {
    static let defaultValue: AuthEntryNavigation? = nil
}
extension EnvironmentValues {
    var authEntryNavigation: AuthEntryNavigation? {
        get { self[AuthEntryNavigationKey.self] }
        set { self[AuthEntryNavigationKey.self] = newValue }
    }
}

struct AuthModeLink: View {
    @Environment(\.authEntryNavigation) private var navigation
    let title: String
    let route: AuthEntryRoute

    var body: some View {
        Button(title) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation { navigation?.switchMode(to: route) }
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}
