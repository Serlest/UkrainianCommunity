import Combine
import SwiftUI

/// A UI lease shared by all authentication methods in one navigation flow.
@MainActor
final class AuthInteractionCoordinator: ObservableObject {
    static let accountSecurity = AuthInteractionCoordinator()
    @Published private(set) var requestID: UUID?
    var isBusy: Bool { requestID != nil }

    func begin() -> UUID? {
        guard requestID == nil else { return nil }
        let request = UUID()
        requestID = request
        return request
    }

    func finish(_ request: UUID) {
        guard requestID == request else { return }
        requestID = nil
    }

    static func begin(in coordinator: AuthInteractionCoordinator?) -> UUID? {
        if let coordinator { return coordinator.begin() }
        return UUID()
    }
}

private struct AuthInteractionKey: EnvironmentKey {
    static let defaultValue: AuthInteractionCoordinator? = nil
}

extension EnvironmentValues {
    var authInteraction: AuthInteractionCoordinator? {
        get { self[AuthInteractionKey.self] }
        set { self[AuthInteractionKey.self] = newValue }
    }
}

struct AccountSecurityInteractionState: ViewModifier {
    @ObservedObject var interaction: AuthInteractionCoordinator
    func body(content: Content) -> some View {
        content.disabled(interaction.isBusy)
            .overlay(alignment: .topTrailing) {
                if interaction.isBusy {
                    ProgressView().padding(16)
                        .accessibilityLabel(AppStrings.Common.loading)
                        .accessibilityIdentifier("accountSecurity.operation.inProgress")
                }
            }
            .environment(\.authInteraction, interaction)
    }
}
