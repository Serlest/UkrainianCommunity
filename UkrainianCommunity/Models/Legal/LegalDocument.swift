import Foundation

enum LegalDocumentType: String, CaseIterable, Codable, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var legacyVersion: String {
        switch self {
        case .terms:
            AuthService.currentTermsVersion
        case .privacy:
            AuthService.currentPrivacyVersion
        }
    }
}

enum LegalDocumentStatus: String, Codable, Equatable {
    case draft
    case published
    case archived
}

struct LegalDocumentLocaleContent: Codable, Equatable {
    let title: String
    let contentMarkdown: String
    let contentText: String?
    let contentHash: String?
}

struct LegalDocument: Identifiable, Codable, Equatable {
    let id: String
    let type: LegalDocumentType
    let version: String
    let versionNumber: Int
    let locales: [String: LegalDocumentLocaleContent]
    let defaultLocale: String
    let canonicalLocale: String?
    let contentHash: String?
    let changeSummary: String?
    let requiresAcceptance: Bool
    let status: LegalDocumentStatus
    let updatedAt: Date?
    let updatedBy: String?
    let publishedAt: Date?
    let publishedBy: String?

    func content(preferredLocale: String? = nil) -> LegalDocumentLocaleContent? {
        let normalizedPreferredLocale = preferredLocale?.lowercased()
        return normalizedPreferredLocale.flatMap { locales[$0] }
            ?? locales[defaultLocale.lowercased()]
            ?? canonicalLocale.flatMap { locales[$0.lowercased()] }
            ?? locales.values.first
    }

    static func hardcodedFallback(type: LegalDocumentType) -> LegalDocument {
        let sections: [(title: String, body: String)]
        let title: String

        switch type {
        case .terms:
            title = AppStrings.Settings.terms
            sections = [
                (AppStrings.Legal.termsIntroTitle, AppStrings.Legal.termsIntroBody),
                (AppStrings.Legal.termsAccountTitle, AppStrings.Legal.termsAccountBody),
                (AppStrings.Legal.termsContentTitle, AppStrings.Legal.termsContentBody),
                (AppStrings.Legal.termsAvailabilityTitle, AppStrings.Legal.termsAvailabilityBody),
                (AppStrings.Legal.termsLiabilityTitle, AppStrings.Legal.termsLiabilityBody)
            ]
        case .privacy:
            title = AppStrings.Settings.privacyPolicy
            sections = [
                (AppStrings.Legal.privacyIntroTitle, AppStrings.Legal.privacyIntroBody),
                (AppStrings.Legal.privacyUsageTitle, AppStrings.Legal.privacyUsageBody),
                (AppStrings.Legal.privacyStorageTitle, AppStrings.Legal.privacyStorageBody),
                (AppStrings.Legal.privacySharingTitle, AppStrings.Legal.privacySharingBody),
                (AppStrings.Legal.privacyRightsTitle, AppStrings.Legal.privacyRightsBody)
            ]
        }

        let markdown = sections.map { section in
            """
            ## \(section.title)

            \(section.body)
            """
        }
        .joined(separator: "\n\n")

        let plainText = sections.map { section in
            "\(section.title)\n\(section.body)"
        }
        .joined(separator: "\n\n")

        let fallbackContent = LegalDocumentLocaleContent(
            title: title,
            contentMarkdown: markdown,
            contentText: plainText,
            contentHash: nil
        )

        return LegalDocument(
            id: type.rawValue,
            type: type,
            version: type.legacyVersion,
            versionNumber: 1,
            locales: [
                AppLanguage.german.rawValue: fallbackContent,
                AppLanguage.ukrainian.rawValue: fallbackContent
            ],
            defaultLocale: AppLanguage.german.rawValue,
            canonicalLocale: AppLanguage.german.rawValue,
            contentHash: nil,
            changeSummary: nil,
            requiresAcceptance: true,
            status: .published,
            updatedAt: nil,
            updatedBy: nil,
            publishedAt: nil,
            publishedBy: nil
        )
    }
}

struct LegalAcceptanceReceipt: Codable, Equatable {
    let documentType: LegalDocumentType
    let version: String
    let acceptedAt: Date
}

struct LegalDocumentManagementState: Equatable {
    let type: LegalDocumentType
    let activeDocument: LegalDocument
    let draftDocument: LegalDocument?
}

struct LegalDocumentDraft: Equatable {
    let type: LegalDocumentType
    let version: String
    let versionNumber: Int
    var defaultLocale: String
    var canonicalLocale: String
    var locales: [String: LegalDocumentLocaleContent]
    var requiresAcceptance: Bool
    var changeSummary: String?
    var supersedesVersion: String?

    static func from(activeDocument: LegalDocument) -> LegalDocumentDraft {
        let nextVersion = Self.nextVersion(after: activeDocument.version)
        return LegalDocumentDraft(
            type: activeDocument.type,
            version: nextVersion.identifier,
            versionNumber: nextVersion.number,
            defaultLocale: activeDocument.defaultLocale,
            canonicalLocale: activeDocument.canonicalLocale ?? activeDocument.defaultLocale,
            locales: activeDocument.locales,
            requiresAcceptance: activeDocument.requiresAcceptance,
            changeSummary: nil,
            supersedesVersion: activeDocument.version
        )
    }

    private static func nextVersion(after currentVersion: String) -> (identifier: String, number: Int) {
        let parts = currentVersion.split(separator: ".")
        guard
            parts.count >= 2,
            let year = parts.first.flatMap({ Int($0) }),
            let currentMinorVersion = parts.last.flatMap({ Int($0) })
        else {
            let fallbackYear = Calendar.current.component(.year, from: .now)
            return ("\(fallbackYear).1", fallbackYear * 100 + 1)
        }

        let visibleMinorVersion = Self.visibleMinorVersion(
            from: currentMinorVersion,
            year: year
        )
        let nextMinorVersion = visibleMinorVersion + 1
        return ("\(year).\(nextMinorVersion)", year * 100 + nextMinorVersion)
    }

    private static func visibleMinorVersion(from rawMinorVersion: Int, year: Int) -> Int {
        guard rawMinorVersion >= 100 else {
            return rawMinorVersion
        }

        let internalYear = rawMinorVersion / 100
        let internalMinorVersion = rawMinorVersion % 100
        if internalYear == year, internalMinorVersion > 0 {
            return internalMinorVersion
        }

        return 1
    }
}
