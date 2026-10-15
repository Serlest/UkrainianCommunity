import SwiftUI

struct LegalComplianceView: View {
    let requirement: LegalComplianceRequirement
    let isAccepting: Bool
    let errorMessage: String?
    let accept: () -> Void
    let decline: () -> Void

    @State private var isConfirmingDecline = false
    @State private var reviewedVersions: Set<String> = []

    private var hasReviewedRequiredDocuments: Bool {
        requirement.requiredDocuments.allSatisfy { reviewedVersions.contains(reviewKey(for: $0)) }
    }

    private func reviewKey(for document: LegalDocument) -> String {
        "\(document.type.rawValue):\(document.version)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.sectionSpacing) {
                    AppGlassCard(spacing: 16) {
                        header
                        changedDocumentRows

                        if !hasReviewedRequiredDocuments {
                            Text(AppStrings.LegalCompliance.reviewInstruction)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let errorMessage {
                            InlineMessageCard(style: .error, message: errorMessage)
                        }

                        PrimaryActionButton(
                            title: AppStrings.LegalCompliance.acceptAll,
                            loadingTitle: AppStrings.LegalCompliance.accepting,
                            isEnabled: hasReviewedRequiredDocuments,
                            isLoading: isAccepting,
                            systemImage: "checkmark.circle.fill",
                            action: accept
                        )
                        .accessibilityIdentifier("legal.required.accept")

                        Button(role: .destructive) {
                            isConfirmingDecline = true
                        } label: {
                            Label(AppStrings.LegalCompliance.decline, systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .appActionButtonStyle(.secondary)
                        .disabled(isAccepting)
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.vertical, AppTheme.sectionSpacing)
                .appCenteredContent()
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(AppStrings.LegalCompliance.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: requirement.id) { _, _ in reviewedVersions = [] }
        .interactiveDismissDisabled(true)
        .alert(AppStrings.LegalCompliance.declineConfirmTitle, isPresented: $isConfirmingDecline) {
            Button(AppStrings.Common.cancel, role: .cancel) {}
            Button(AppStrings.LegalCompliance.declineConfirmAction, role: .destructive) {
                decline()
            }
        } message: {
            Text(AppStrings.LegalCompliance.declineConfirmMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: 48, height: 48)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))

            Text(AppStrings.LegalCompliance.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppStrings.LegalCompliance.message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var changedDocumentRows: some View {
        VStack(spacing: 10) {
            ForEach(requirement.requiredDocuments) { document in
                NavigationLink {
                    LegalMarkdownDocumentView(document: document) {
                        reviewedVersions.insert(reviewKey(for: document))
                    }
                } label: {
                    LegalComplianceDocumentRow(
                        document: document,
                        isReviewed: reviewedVersions.contains(reviewKey(for: document))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("legal.required.document.\(document.type.rawValue)")
            }
        }
    }
}

private struct LegalComplianceDocumentRow: View {
    let document: LegalDocument
    let isReviewed: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.type.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(AppStrings.legalVersionLabel(document.version))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                if let summary = document.changeSummary.map({ LegalChangeSummary(raw: $0).localized(AppLanguage.stored.rawValue) }),
                   !summary.isEmpty {
                    Text(AppStrings.LegalCompliance.changeSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            Label(
                isReviewed ? AppStrings.LegalCompliance.reviewComplete : AppStrings.LegalCompliance.readDocument,
                systemImage: isReviewed ? "checkmark.circle.fill" : "chevron.right"
            )
                .labelStyle(.iconOnly)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(12)
        .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var title: String {
        document.content(preferredLocale: AppLanguage.stored.rawValue)?.title ?? document.type.title
    }
}

struct LegalMarkdownDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: LegalDocument
    var onReviewed: (() -> Void)? = nil

    private var content: LegalDocumentLocaleContent {
        document.content(preferredLocale: AppLanguage.stored.rawValue)
            ?? LegalDocumentLocaleContent(
                title: document.type.title,
                contentMarkdown: "",
                contentText: nil,
                contentHash: nil
            )
    }

    var body: some View {
        PushedScreenShell(
            title: content.title,
            subtitle: AppStrings.LegalCompliance.readDocumentSubtitle,
            tabBarHidden: true
        ) {
            AppGroupedContentPlane(spacing: AppTheme.sectionSpacing) {
                AppEditorSectionCard {
                    AppInfoChip(
                        title: AppStrings.legalVersionLabel(document.version),
                        systemImage: "doc.text"
                    )
                }

                AppEditorSectionCard {
                    LegalMarkdownRenderer(
                        markdown: content.contentMarkdown,
                        fallbackText: content.contentText
                    )
                }

                if let onReviewed {
                    PrimaryActionButton(
                        title: AppStrings.LegalCompliance.reviewComplete,
                        loadingTitle: AppStrings.LegalCompliance.reviewComplete,
                        systemImage: "checkmark.circle.fill"
                    ) {
                        onReviewed()
                        dismiss()
                    }
                    .accessibilityIdentifier("legal.document.reviewComplete")
                }
            }
        }
    }

}

private extension LegalDocumentType {
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

    var systemImage: String {
        switch self {
        case .terms: "doc.text.fill"
        case .privacy: "lock.shield.fill"
        case .organizationRules: "building.2.crop.circle.fill"
        }
    }
}
