import Foundation

enum ProjectSupportText {
    nonisolated static func text(_ key: String) -> String {
        LocalizationStore.localizedString("project_support." + key, defaultValue: key, table: "ProjectSupport")
    }
    nonisolated static var title: String { text("title") }
    nonisolated static var savedVisible: String { text("savedVisible") }
    nonisolated static var savedHidden: String { text("savedHidden") }
    nonisolated static var unsaved: String { text("unsaved") }
    nonisolated static var willVisible: String { text("willVisible") }
    nonisolated static var willHidden: String { text("willHidden") }
    nonisolated static var save: String { text("save") }
    nonisolated static var saving: String { text("saving") }
    nonisolated static var openLink: String { text("openLink") }
    nonisolated static var copyLink: String { text("copyLink") }
    nonisolated static var closeTitle: String { text("closeTitle") }
    nonisolated static var closeMessage: String { text("closeMessage") }
    nonisolated static var leave: String { text("leave") }
    nonisolated static var reloadTitle: String { text("reloadTitle") }
    nonisolated static var reloadMessage: String { text("reloadMessage") }
    nonisolated static var reload: String { text("reload") }
    nonisolated static var journalAction: String { text("journalAction") }
    nonisolated static var journalSaved: String { text("journalSaved") }
    nonisolated static var conflictTitle: String { text("conflictTitle") }
    nonisolated static var conflictCause: String { text("conflictCause") }
    nonisolated static var unconfirmedTitle: String { text("unconfirmedTitle") }
    nonisolated static var unconfirmedCause: String { text("unconfirmedCause") }
    nonisolated static var journalNext: String { text("journalNext") }
    nonisolated static var writeStage: String { text("writeStage") }
    nonisolated static var confirmStage: String { text("confirmStage") }
}
