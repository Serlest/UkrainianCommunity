import Combine
import SwiftUI

enum LegalDocumentKind: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var documentType: LegalDocumentType {
        switch self {
        case .terms:
            .terms
        case .privacy:
            .privacy
        }
    }

    var title: String {
        switch self {
        case .terms:
            AppStrings.Settings.terms
        case .privacy:
            AppStrings.Settings.privacyPolicy
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .terms:
            "legal.terms.screen"
        case .privacy:
            "legal.privacy.screen"
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
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppGroupedContentPlane {
                        VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                            if viewModel.isLoading, viewModel.document == nil {
                                LoadingStateCard(title: nil)
                            }

                            if let errorMessage = viewModel.errorMessage {
                                InlineMessageCard(style: .error, message: errorMessage)
                            }

                            AppEditorSectionCard {
                                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                                    SectionHeaderBlock(
                                        title: displayedContent.title,
                                        subtitle: AppStrings.Legal.screenIntro
                                    )

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
                            }

                            AppEditorSectionCard {
                                LegalMarkdownRenderer(
                                    markdown: displayedContent.contentMarkdown,
                                    fallbackText: displayedContent.contentText
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
        }
        .navigationTitle(displayedContent.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(document.accessibilityIdentifier)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var versionChip: some View {
        AppInfoChip(
            title: AppStrings.legalVersionLabel(displayedDocument.version),
            systemImage: "doc.text"
        )
    }

    @ViewBuilder
    private var lastUpdatedChip: some View {
        if let lastUpdatedText {
            AppInfoChip(title: lastUpdatedText, systemImage: "calendar")
        }
    }
}

@MainActor
private final class LegalDocumentReaderViewModel: ObservableObject {
    @Published private(set) var document: LegalDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let kind: LegalDocumentKind
    private let repository: LegalDocumentRepository

    init(kind: LegalDocumentKind, repository: LegalDocumentRepository) {
        self.kind = kind
        self.repository = repository
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            document = try await repository.fetchActiveDocument(type: kind.documentType)
        } catch {
            document = LegalDocument.hardcodedFallback(type: kind.documentType)
            errorMessage = AppStrings.LegalManagement.loadFailed
        }

        isLoading = false
    }
}
