import SwiftUI

enum OrganizationPresentationMode {
    case `public`
    case management

    var allowsManagementControls: Bool {
        self == .management
    }
}

private struct OrganizationPresentationModeKey: EnvironmentKey {
    static let defaultValue: OrganizationPresentationMode = .public
}

extension EnvironmentValues {
    var organizationPresentationMode: OrganizationPresentationMode {
        get { self[OrganizationPresentationModeKey.self] }
        set { self[OrganizationPresentationModeKey.self] = newValue }
    }
}
