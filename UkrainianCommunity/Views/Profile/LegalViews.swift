import SwiftUI

enum LegalDocumentKind: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms:
            AppStrings.Settings.terms
        case .privacy:
            AppStrings.Settings.privacyPolicy
        }
    }

    var version: String {
        switch self {
        case .terms:
            AuthService.currentTermsVersion
        case .privacy:
            AuthService.currentPrivacyVersion
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

    var sections: [(title: String, body: String)] {
        switch self {
        case .terms:
            return [
                (AppStrings.Legal.termsIntroTitle, AppStrings.Legal.termsIntroBody),
                (AppStrings.Legal.termsAccountTitle, AppStrings.Legal.termsAccountBody),
                (AppStrings.Legal.termsContentTitle, AppStrings.Legal.termsContentBody),
                (AppStrings.Legal.termsAvailabilityTitle, AppStrings.Legal.termsAvailabilityBody),
                (AppStrings.Legal.termsLiabilityTitle, AppStrings.Legal.termsLiabilityBody)
            ]
        case .privacy:
            return [
                (AppStrings.Legal.privacyIntroTitle, AppStrings.Legal.privacyIntroBody),
                (AppStrings.Legal.privacyUsageTitle, AppStrings.Legal.privacyUsageBody),
                (AppStrings.Legal.privacyStorageTitle, AppStrings.Legal.privacyStorageBody),
                (AppStrings.Legal.privacySharingTitle, AppStrings.Legal.privacySharingBody),
                (AppStrings.Legal.privacyRightsTitle, AppStrings.Legal.privacyRightsBody)
            ]
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocumentKind

    private var lastUpdatedText: String {
        let updatedAt = Date(timeIntervalSince1970: 1_767_225_600) // January 1, 2026 UTC
        return AppStrings.legalLastUpdatedLabel(LocalizationStore.dateString(from: updatedAt))
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppBrandHeader {
                        AppNotificationBellButton()
                    }

                    AppGroupedContentPlane {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            AppEditorSectionCard {
                                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                                    SectionHeaderBlock(
                                        title: document.title,
                                        subtitle: AppStrings.Legal.screenIntro
                                    )

                                    ViewThatFits(in: .horizontal) {
                                        HStack(spacing: 8) {
                                            AppInfoChip(title: AppStrings.legalVersionLabel(document.version), systemImage: "doc.text")
                                            AppInfoChip(title: lastUpdatedText, systemImage: "calendar")
                                        }

                                        VStack(alignment: .leading, spacing: 8) {
                                            AppInfoChip(title: AppStrings.legalVersionLabel(document.version), systemImage: "doc.text")
                                            AppInfoChip(title: lastUpdatedText, systemImage: "calendar")
                                        }
                                    }
                                }
                            }

                            ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                                AppEditorSectionCard {
                                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                                        Text(section.title)
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)

                                        Text(section.body)
                                            .font(.subheadline)
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(document.accessibilityIdentifier)
    }
}
