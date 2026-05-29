import SwiftUI

enum EventPresentationMode {
    case `public`
    case management

    var allowsManagementControls: Bool {
        self == .management
    }
}

private struct EventPresentationModeKey: EnvironmentKey {
    static let defaultValue: EventPresentationMode = .public
}

extension EnvironmentValues {
    var eventPresentationMode: EventPresentationMode {
        get { self[EventPresentationModeKey.self] }
        set { self[EventPresentationModeKey.self] = newValue }
    }
}
