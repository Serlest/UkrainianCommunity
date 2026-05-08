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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.legalVersionLabel(document.version))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)

                    Text(lastUpdatedText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(document.accessibilityIdentifier)
    }
}
