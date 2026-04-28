import FirebaseCore
import Foundation

struct FirebaseConfigurationCheck {
    enum Status: Equatable {
        case configured
        case notConfigured

        var isConfigured: Bool {
            self == .configured
        }
    }

    func status() -> Status {
        FirebaseApp.app() == nil ? .notConfigured : .configured
    }

    func statusMessage() -> String {
        switch status() {
        case .configured:
            "Firebase configured"
        case .notConfigured:
            "Firebase not configured"
        }
    }
}
