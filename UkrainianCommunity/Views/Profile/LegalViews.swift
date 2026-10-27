import Combine
import SwiftUI

enum LegalDocumentKind: String, Identifiable {
    case terms
    case privacy
    case organizationRules

    var id: String { rawValue }

    var documentType: LegalDocumentType {
        switch self {
        case .terms:
            .terms
        case .privacy:
            .privacy
        case .organizationRules:
            .organizationRules
        }
    }

    var title: String {
        switch self {
        case .terms:
            AppStrings.Settings.terms
        case .privacy:
            AppStrings.Settings.privacyPolicy
        case .organizationRules:
            AppStrings.OrganizationRules.title
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .terms:
            "legal.terms.screen"
        case .privacy:
            "legal.privacy.screen"
        case .organizationRules:
            "legal.organizationRules.screen"
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocumentKind

    @StateObject private var viewModel: LegalDocumentReaderViewModel

    init(
        document: LegalDocumentKind,
        repository: LegalDocumentRepository = FirestoreLegalDocumentRepository()
    ) {
        self.document = document
        _viewModel = StateObject(
            wrappedValue: LegalDocumentReaderViewModel(
                kind: document,
                repository: repository
            )
        )
    }

    private var displayedDocument: LegalDocument {
        viewModel.document ?? LegalDocument.hardcodedFallback(type: document.documentType)
    }

    private var displayedContent: LegalDocumentLocaleContent {
        displayedDocument.content(preferredLocale: AppLanguage.stored.rawValue)
            ?? LegalDocumentLocaleContent(
                title: document.title,
                contentMarkdown: "",
                contentText: nil,
                contentHash: nil
            )
    }

    private var lastUpdatedText: String? {
        guard let lastUpdated = displayedDocument.publishedAt ?? displayedDocument.updatedAt else {
            return nil
        }

        return AppStrings.legalLastUpdatedLabel(LocalizationStore.dateString(from: lastUpdated))
    }

    var body: some View {
        PushedScreenShell(
            title: displayedContent.title,
            subtitle: AppStrings.Legal.screenIntro,
            tabBarHidden: true
        ) {
            AppGroupedContentPlane {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    if (!viewModel.hasLoaded || viewModel.isLoading), viewModel.document == nil {
                        LoadingStateCard(title: nil)
                    }

                    if let errorMessage = viewModel.errorMessage ?? (viewModel.isUsingBundle ? LegalFlowText.bundleSource : nil) {
                        InlineMessageCard(style: .error, message: errorMessage)
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Label(AppStrings.Action.retry, systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isLoading)
                    }

                    if viewModel.document != nil {
                    AppEditorSectionCard {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                versionChip
                                lastUpdatedChip
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                versionChip
                                lastUpdatedChip
                            }
                        }
                    }

                    AppEditorSectionCard { LegalDocumentText(content: displayedContent) }
                    }
                }
            }
        }
        .accessibilityIdentifier(document.accessibilityIdentifier)
        .task {
            await viewModel.load()
        }
        .appRefreshable {
            await viewModel.load()
        }
    }

    private var versionChip: some View {
        LegalMetadataLabel(
            title: AppStrings.legalVersionLabel(displayedDocument.version),
            systemImage: "doc.text"
        )
    }

    @ViewBuilder
    private var lastUpdatedChip: some View {
        if let lastUpdatedText {
            LegalMetadataLabel(title: lastUpdatedText, systemImage: "calendar")
        }
    }
}

@MainActor
final class LegalDocumentReaderViewModel: ObservableObject {
    @Published private(set) var document: LegalDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var isUsingBundle = false
    @Published private(set) var errorMessage: String?
    private let kind: LegalDocumentKind
    private let repository: LegalDocumentRepository
    private var flight: (UUID, Task<LegalDocument, Error>)?

    init(kind: LegalDocumentKind, repository: LegalDocumentRepository) { self.kind = kind; self.repository = repository }

    func load() async {
        let request: (UUID, Task<LegalDocument, Error>)
        if let flight { request = flight }
        else {
            let repository = repository, kind = kind
            request = (UUID(), Task { @MainActor in
                try await RefreshRequest.run { try await repository.fetchActiveDocumentForReader(type: kind.documentType) }
            })
            flight = request
        }
        isLoading = true; errorMessage = nil
        let result = await request.1.result
        guard !Task.isCancelled else { return }
        guard flight?.0 == request.0 else { return }
        flight = nil; isLoading = false
        hasLoaded = true
        switch result {
        case .success(let loaded): document = loaded; isUsingBundle = false
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            if document == nil { document = LegalDocument.hardcodedFallback(type: kind.documentType); isUsingBundle = true }
            errorMessage = isUsingBundle
                ? LegalReadFailure(error) == .network ? LegalFlowText.offlineBundle : AppStrings.Legal.offlineFallbackNotice
                : LegalFlowText.readerRefreshFailed
        }
    }
}
