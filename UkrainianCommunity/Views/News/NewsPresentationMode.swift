import SwiftUI

enum NewsPresentationMode {
    case `public`
    case management

    var allowsManagementControls: Bool {
        self == .management
    }
}

private struct NewsPresentationModeKey: EnvironmentKey {
    static let defaultValue: NewsPresentationMode = .public
}

extension EnvironmentValues {
    var newsPresentationMode: NewsPresentationMode {
        get { self[NewsPresentationModeKey.self] }
        set { self[NewsPresentationModeKey.self] = newValue }
    }
}
