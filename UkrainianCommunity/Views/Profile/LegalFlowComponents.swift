import SwiftUI

enum LegalFlowText {
    static func text(_ key: String) -> String { LocalizationStore.localizedString("legal_flow." + key, defaultValue: key, table: "LegalFlow") }
    static var sourceText: String { text("sourceText") }
    static var readVersion: String { text("readVersion") }
    static var bundleSource: String { text("bundleSource") }
    static var editorTitle: String { text("editorTitle") }
    static var conflict: String { text("conflict") }
    static var readerRefreshFailed: String { text("readerRefreshFailed") }
    static var offlineBundle: String { text("offlineBundle") }
    static var historyEmpty: String { text("historyEmpty") }
    static var historyContext: String { text("historyContext") }
    static var save: String { text("save") }
    static var activeLoading: String { text("activeLoading") }
}

struct LegalMetadataLabel: View {
    let title: String
    let systemImage: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 14, weight: .semibold)).accessibilityHidden(true)
            Text(title).font(.caption).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppTheme.accentPrimaryForeground)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct LegalActionLabel: View {
    let title: String
    let systemImage: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 18, weight: .semibold)).accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).contentShape(Rectangle())
    }
}

struct LegalDocumentText: View {
    let content: LegalDocumentLocaleContent
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if content.contentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first != "# " + content.title {
                Text(content.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            }
            LegalMarkdownRenderer(markdown: content.contentMarkdown, fallbackText: content.contentText)
        }
    }
}
