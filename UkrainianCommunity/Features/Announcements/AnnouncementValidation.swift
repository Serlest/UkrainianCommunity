import Foundation
import FirebaseFunctions

extension UserAnnouncement {
    func phase(at milliseconds: Double = Date().timeIntervalSince1970 * 1000) -> String {
        if status == "draft" { return "draft" }
        if status == "cancelled" { return "cancelled" }
        if expiresAt <= milliseconds { return "completed" }
        return startsAt > milliseconds ? "scheduled" : "active"
    }
    var saveIssues: [String] {
        var issues: [String] = []
        if groups.isEmpty && userIds.isEmpty { issues.append(AnnouncementManagementText.value("recipients")) }
        if title.uk.utf16.count > 160 || title.de.utf16.count > 160 || body.uk.utf16.count > 6000 || body.de.utf16.count > 6000 {
            issues.append(AnnouncementManagementText.value("length"))
        }
        if !startsAt.isFinite || !expiresAt.isFinite || expiresAt <= max(startsAt, Date().timeIntervalSince1970 * 1000) || expiresAt - startsAt > 90 * 86400000 {
            issues.append(AnnouncementManagementText.value("period"))
        }
        return issues
    }
    var publicationIssues: [String] {
        var issues = saveIssues
        if [title.uk, title.de, body.uk, body.de].contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(AnnouncementManagementText.value("languages"))
        }
        return issues
    }
}

enum AnnouncementErrorPresentation {
    static func message(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return AnnouncementManagementText.value("network") }
        guard ns.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: ns.code) else { return AnnouncementStrings.error }
        let key: String
        switch code {
        case .unavailable: key = "network"
        case .deadlineExceeded: key = "timeout"
        case .unauthenticated, .permissionDenied: key = "access"
        case .aborted, .alreadyExists: key = "conflict"
        case .invalidArgument: key = "invalid"
        case .failedPrecondition: key = "precondition"
        case .resourceExhausted: key = "quota"
        case .notFound: key = "missing"
        default: return AnnouncementStrings.error
        }
        return AnnouncementManagementText.value(key)
    }
}
