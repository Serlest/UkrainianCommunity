import SwiftUI

struct LegalEvidenceVersionView: View {
    let event: LegalEvidenceEvent
    let repository: LegalDocumentRepository
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var document: LegalDocument?
    @State private var failed = false
    @State private var loading = false
    @State private var locale = "de"

    var body: some View {
        ProfileDestinationLayout(title: LegalEvidenceText.versionTitle,
            introSubtitle: AppStrings.legalVersionLabel(event.version ?? "")) {
            if let document {
                Text(event.contentHash == nil ? LegalEvidenceText.missingHash : LegalEvidenceText.verifiedHash)
                    .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                Picker(AppStrings.LegalManagement.localePicker, selection: $locale) {
                    Text(AppStrings.Settings.german).tag("de")
                    Text(AppStrings.Settings.ukrainian).tag("uk")
                }.pickerStyle(.segmented)
                if let content = document.content(preferredLocale: locale) {
                    AppEditorSectionCard {
                        if content.contentMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                            .components(separatedBy: .newlines).first != "# \(content.title)" {
                            Text(content.title).font(.title2.bold())
                        }
                        LegalMarkdownRenderer(markdown: content.contentMarkdown, fallbackText: content.contentText)
                    }
                }
            } else if failed {
                ErrorStateCard(systemImage: "doc.badge.ellipsis", title: LegalEvidenceText.versionTitle,
                    message: LegalEvidenceText.versionUnavailable, retryTitle: AppStrings.Action.retry) { Task { await load() } }
            } else { LoadingStateCard(title: nil) }
        }
        .task { locale = event.locale == "uk" ? "uk" : "de"; await load() }
        .onChange(of: authState.user?.id) { _, _ in document = nil; dismiss() }
        .accessibilityIdentifier("screen.legalEvidence.version")
    }

    private func load() async {
        guard !loading, PermissionService.isAppOwner(user: authState.user),
              let type = event.documentType, let version = event.version else { failed = true; return }
        let userID = authState.user?.id
        loading = true; failed = false
        defer { loading = false }
        do {
            let loaded = try await repository.fetchPublishedVersion(type: type, version: version, expectedHash: event.contentHash)
            guard authState.user?.id == userID, !Task.isCancelled else { return }
            document = loaded
        } catch { failed = true }
    }
}
