import Foundation
import FirebaseFunctions
import FirebaseFirestore

enum SystemLogJournalStrings {
    static func text(_ key: String, _ fallback: String) -> String {
        LocalizationStore.localizedString("system_logs.journal." + key, defaultValue: fallback, table: "SystemLogJournal")
    }
    static var notFound: String { text("not_found", "Запис журналу більше не доступний.") }
    static var sessionRequired: String { text("session_required", "Сесію входу не підтверджено. Увійдіть повторно, щоб відкрити журнал.") }
    static var cursorExpired: String { text("cursor_expired", "Ця сторінка історії застаріла. Оновіть журнал, щоб продовжити.") }
    static var requirements: String { text("requirements", "Сервер не підтвердив умови доступу. Перевірте вхід і чинні підтвердження та спробуйте ще раз.") }
    static var adminTitle: String { text("admin_title", "Журнал адміністратора") }
    static var metricsScope: String { text("metrics_scope", "Показники стосуються завантажених результатів. Пошук і фільтри охоплюють увесь журнал.") }
}

/// Callable errors carry stable domain/code values even when their description
/// is localized or omits the English status name.
enum SystemLogFailureKind: Equatable {
    case access, session, requirements, expiredCursor, index, network, other
    var isAccessFailure: Bool { self == .access || self == .session || self == .requirements }
    init(_ error: Error) {
        let ns = error as NSError
        let description = (ns.domain + " " + ns.localizedDescription).lowercased()
        if ns.domain == FunctionsErrorDomain {
            switch FunctionsErrorCode(rawValue: ns.code) {
            case .unauthenticated: self = .session; return
            case .permissionDenied: self = .access; return
            case .aborted: self = .expiredCursor; return
            case .unavailable, .deadlineExceeded: self = .network; return
            case .failedPrecondition:
                if description.contains("index") { self = .index }
                else if description.contains("authenticator-verified session") || description.contains("authentication") { self = .session }
                else { self = .requirements }
                return
            default: break
            }
        }
        if ns.domain == FirestoreErrorDomain {
            switch FirestoreErrorCode.Code(rawValue: ns.code) {
            case .unauthenticated: self = .session; return
            case .permissionDenied: self = .access; return
            case .unavailable, .deadlineExceeded: self = .network; return
            case .failedPrecondition: self = description.contains("index") ? .index : .requirements; return
            default: break
            }
        }
        if ns.domain == NSURLErrorDomain { self = .network; return }
        if description.contains("permission") || description.contains("denied") { self = .access }
        else if description.contains("unauthenticated") { self = .session }
        else if description.contains("network") || description.contains("unavailable") { self = .network }
        else if description.contains("index") || description.contains("failed-precondition") { self = .index }
        else { self = .other }
    }
}
