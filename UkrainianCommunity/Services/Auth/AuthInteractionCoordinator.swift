import Combine
import SwiftUI

/// A UI lease shared by all authentication methods in one navigation flow.
@MainActor
final class AuthInteractionCoordinator: ObservableObject {
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
