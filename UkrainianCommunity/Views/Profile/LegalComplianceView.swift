import SwiftUI

struct LegalComplianceView: View {
    let requirement: LegalComplianceRequirement
    let isAccepting: Bool
    let errorMessage: String?
    let accept: () -> Void
    let decline: () -> Void

    @State private var isConfirmingDecline = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.sectionSpacing) {
                    AppGlassCard(spacing: 16) {
                        header
                        changedDocumentRows

                        if let errorMessage {
                            InlineMessageCard(style: .error, message: errorMessage)
                        }

                        PrimaryActionButton(
                            title: AppStrings.LegalCompliance.acceptAll,
                            loadingTitle: AppStrings.LegalCompliance.accepting,
                            isLoading: isAccepting,
                            systemImage: "checkmark.circle.fill",
                            action: accept
                        )

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
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(AppStrings.LegalCompliance.title)
            .navigationBarTitleDisplayMode(.inline)
        }
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
                .foregroundStyle(AppTheme.accentPrimary)
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
                    LegalMarkdownDocumentView(document: document)
                } label: {
                    LegalComplianceDocumentRow(document: document)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LegalComplianceDocumentRow: View {
    let document: LegalDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.type == .terms ? "doc.text.fill" : "lock.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(AppStrings.legalVersionLabel(document.version))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 0)

            Label(AppStrings.LegalCompliance.readDocument, systemImage: "chevron.right")
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

private struct LegalMarkdownDocumentView: View {
    let document: LegalDocument

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
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                        SectionHeaderBlock(
                            title: content.title,
                            subtitle: AppStrings.LegalCompliance.readDocumentSubtitle
                        )

                        AppInfoChip(
                            title: AppStrings.legalVersionLabel(document.version),
                            systemImage: "doc.text"
                        )
                    }
                }

                AppEditorSectionCard {
                    markdownText
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.vertical, AppTheme.sectionSpacing)
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var markdownText: Text {
        if let attributed = try? AttributedString(markdown: content.contentMarkdown) {
            return Text(attributed)
        }

        return Text(content.contentText ?? content.contentMarkdown)
    }
}

private extension LegalDocumentType {
    var title: String {
        switch self {
        case .terms:
            AppStrings.Settings.terms
        case .privacy:
            AppStrings.Settings.privacyPolicy
        }
    }
}
