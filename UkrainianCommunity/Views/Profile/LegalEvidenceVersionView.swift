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
    @State private var requestID = UUID()

    var body: some View {
        ProfileDestinationLayout(title: LegalEvidenceText.versionTitle,
            introSubtitle: AppStrings.legalVersionLabel(event.version ?? "")) {
            if !LegalAccessScope(authState).allowsOwner {
                ErrorStateCard(systemImage: "lock.fill", title: AppStrings.LegalEvidence.permissionTitle,
                               message: AppStrings.LegalEvidence.permissionMessage)
            } else if let document {
                Text(event.contentHash == nil ? LegalEvidenceText.missingHash : LegalEvidenceText.verifiedHash)
                    .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                Picker(AppStrings.LegalManagement.localePicker, selection: $locale) {
                    Text(AppStrings.Settings.german).tag("de")
                    Text(AppStrings.Settings.ukrainian).tag("uk")
                }.pickerStyle(.segmented)
                if let content = document.content(preferredLocale: locale) {
                    AppEditorSectionCard {
                        LegalDocumentText(content: content)
                    }
                }
            } else if failed {
                ErrorStateCard(systemImage: "doc.badge.ellipsis", title: LegalEvidenceText.versionTitle,
                    message: LegalEvidenceText.versionUnavailable, retryTitle: AppStrings.Action.retry) { Task { await load() } }
            } else { LoadingStateCard(title: nil) }
        }
        .task { locale = event.locale == "uk" ? "uk" : "de"; await load() }
        .onChange(of: LegalAccessScope(authState)) { _, _ in requestID = UUID(); document = nil; loading = false; dismiss() }
        .accessibilityIdentifier("screen.legalEvidence.version")
    }

    private func load() async {
        guard !loading, LegalAccessScope(authState).allowsOwner,
              let type = event.documentType, let version = event.version else { failed = true; return }
        let scope = LegalAccessScope(authState), id = UUID()
        requestID = id
        loading = true; failed = false
        defer { if requestID == id { loading = false } }
        do {
            let loaded = try await RefreshRequest.run {
                try await repository.fetchPublishedVersion(type: type, version: version, expectedHash: event.contentHash)
            }
            guard LegalAccessScope(authState) == scope, requestID == id, !Task.isCancelled else { return }
            document = loaded
        } catch is CancellationError { return }
        catch {
            guard LegalAccessScope(authState) == scope, requestID == id else { return }
            document = nil; failed = true
        }
    }
}
