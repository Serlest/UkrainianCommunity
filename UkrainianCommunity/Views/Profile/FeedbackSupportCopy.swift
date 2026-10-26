import Foundation

nonisolated enum FeedbackSupportCopy {
    static var answeredFilter: String { text("answered_filter", "Answered") }
    static var loadNetworkError: String { text("load_network_error", "Requests could not be loaded. Check your connection and try again.") }
    private static func text(_ key: String, _ fallback: String) -> String {
        LocalizationStore.localizedString("feedback_audit." + key, defaultValue: fallback, table: "FeedbackSupportAudit")
    }
    static var personalSubtitle: String { text("personal_subtitle", "Your requests and replies from the support team.") }
    static var composerSubtitle: String { text("composer_subtitle", "Send a question, suggestion or problem to the support team.") }
    static var caseDetails: String { text("case_details", "Case details") }
    static var loadedScope: String { text("loaded_scope", "Search and filters apply to loaded requests. Load older requests to expand the results.") }
    static var appealReason: String { text("appeal_reason", "Why should this decision be reviewed?") }
    static var conversationTitle: String { text("conversation", "Request") }
    static func status(_ raw: String) -> String {
        switch raw {
        case "open": text("status.open", "Awaiting review")
        case "decided": text("status.decided", "Decision issued")
        case "appealed": text("status.appealed", "Appeal awaiting review")
        case "appealDecided": text("status.appeal_decided", "Appeal reviewed")
        default: text("status.unknown", "Status unavailable")
        }
    }
}
