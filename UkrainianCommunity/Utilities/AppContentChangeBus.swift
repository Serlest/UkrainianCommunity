import Foundation

extension Notification.Name {
    static let appContentChanged = Notification.Name("appContentChanged")
    static let newsChanged = Notification.Name("newsChanged")
    static let eventsChanged = Notification.Name("eventsChanged")
    static let organizationsChanged = Notification.Name("organizationsChanged")
    static let guideChanged = Notification.Name("guideChanged")
    static let registrationsChanged = Notification.Name("registrationsChanged")
}

enum AppContentChangeBus {
    private static let organizationIDKey = "organizationID"

    static func postNewsChanged(organizationID: String? = nil) {
        post(name: .newsChanged, organizationID: organizationID)
    }

    static func postEventsChanged(organizationID: String? = nil) {
        post(name: .eventsChanged, organizationID: organizationID)
    }

    static func postOrganizationsChanged(organizationID: String? = nil) {
        post(name: .organizationsChanged, organizationID: organizationID)
    }

    static func postGuideChanged() {
        NotificationCenter.default.post(name: .guideChanged, object: nil)
        NotificationCenter.default.post(name: .appContentChanged, object: nil)
    }

    static func postRegistrationsChanged(organizationID: String? = nil) {
        post(name: .registrationsChanged, organizationID: organizationID)
    }

    static func organizationID(from notification: Notification) -> String? {
        notification.userInfo?[organizationIDKey] as? String
    }

    private static func post(name: Notification.Name, organizationID: String?) {
        var userInfo: [String: String] = [:]
        if let organizationID, !organizationID.isEmpty {
            userInfo[organizationIDKey] = organizationID
        }

        let payload = userInfo.isEmpty ? nil : userInfo
        NotificationCenter.default.post(name: name, object: nil, userInfo: payload)
        NotificationCenter.default.post(name: .appContentChanged, object: nil, userInfo: payload)
    }
}
