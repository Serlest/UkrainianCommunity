import Foundation

struct LegalEvidenceAccount: Identifiable, Equatable {
    let userID: String
    let displayName: String?
    let email: String?
    let createdAt: Date?

    var id: String { userID }

    var title: String {
        normalized(displayName) ?? normalized(email) ?? userID
    }

    private func normalized(_ value: String?) -> String? {
        let result = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return result.isEmpty ? nil : result
    }
}

struct LegalEvidenceAccountCursor: Equatable {
    let userID: String
    let createdAt: Date
    var seconds: Int64? = nil
    var nanoseconds: Int32? = nil
}

struct LegalEvidenceAccountPage: Equatable {
    let accounts: [LegalEvidenceAccount]
    let nextCursor: LegalEvidenceAccountCursor?
    let totalMatches: Int?
}

enum LegalEvidenceEventType: String, CaseIterable, Codable, Identifiable {
    case termsAccepted
    case privacyAcknowledged
    case minimumAgeConfirmed
    case organizationRulesAccepted
    case analyticsGranted
    case analyticsWithdrawn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .termsAccepted: AppStrings.LegalEvidence.termsAccepted
        case .privacyAcknowledged: AppStrings.LegalEvidence.privacyAcknowledged
        case .minimumAgeConfirmed: AppStrings.LegalEvidence.minimumAgeConfirmed
        case .organizationRulesAccepted: AppStrings.LegalEvidence.organizationRulesAccepted
        case .analyticsGranted: AppStrings.LegalEvidence.analyticsGranted
        case .analyticsWithdrawn: AppStrings.LegalEvidence.analyticsWithdrawn
        }
    }

    var systemImage: String {
        switch self {
        case .termsAccepted: "signature"
        case .privacyAcknowledged: "hand.raised.fill"
        case .minimumAgeConfirmed: "person.badge.shield.checkmark.fill"
        case .organizationRulesAccepted: "building.2.crop.circle.fill"
        case .analyticsGranted: "chart.bar.fill"
        case .analyticsWithdrawn: "chart.bar.xaxis"
        }
    }
}

struct LegalEvidenceEvent: Identifiable, Equatable, Codable {
    let id: String
    let userID: String
    let displayName: String?
    let email: String?
    let eventType: LegalEvidenceEventType
    let occurredAt: Date
    let version: String?
    let locale: String?
    let appVersion: String?
    let source: String
    let contentHash: String?
    let organizationID: String?
    let organizationName: String?

    var userTitle: String {
        if let displayName = normalized(displayName) { return displayName }
        if let email = normalized(email) { return email }
        return userID
    }

    func matches(_ query: String) -> Bool {
        let tokens = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return true }
        let haystack = [
            userID,
            displayName ?? "",
            email ?? "",
            version ?? "",
            eventType.title,
            organizationID ?? "",
            organizationName ?? "",
        ]
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return tokens.allSatisfy { haystack.contains($0) }
    }

    private func normalized(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }
}

enum LegalEvidenceFilter: String, CaseIterable, Identifiable {
    case all
    case terms
    case privacy
    case age
    case analytics
    case organizations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppStrings.LegalEvidence.filterAll
        case .terms: AppStrings.LegalEvidence.filterTerms
        case .privacy: AppStrings.LegalEvidence.filterPrivacy
        case .age: AppStrings.LegalEvidence.filterAge
        case .analytics: AppStrings.LegalEvidence.filterAnalytics
        case .organizations: AppStrings.LegalEvidence.filterOrganizations
        }
    }

    func includes(_ type: LegalEvidenceEventType) -> Bool {
        switch self {
        case .all: true
        case .terms: type == .termsAccepted
        case .privacy: type == .privacyAcknowledged
        case .age: type == .minimumAgeConfirmed
        case .analytics: type == .analyticsGranted || type == .analyticsWithdrawn
        case .organizations: type == .organizationRulesAccepted
        }
    }
}
