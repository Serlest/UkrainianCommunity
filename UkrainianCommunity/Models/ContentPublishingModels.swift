import Foundation

enum PublishedContentLanguage: String, Codable, CaseIterable, Identifiable {
    case ukrainian = "uk"
    case german = "de"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ukrainian: "Українська"
        case .german: "Deutsch"
        }
    }
}

struct NewsLocalizedContent: Codable, Equatable {
    let title: String
    let subtitle: String
    let body: String
}

struct EventLocalizedContent: Codable, Equatable {
    let title: String
    let summary: String
    let details: String
}

struct OrganizationLocalizedContent: Codable, Equatable {
    let name: String
    let shortDescription: String
    let fullDescription: String
    let missionStatement: String?
    let serviceArea: String?
    let specialHoursNote: String?
    let services: [String]
    let currentOfferTitle: String?
    let currentOfferDetails: String?
}

struct ExternalContentAction: Codable, Equatable {
    let title: String?
    let url: String

    nonisolated init(title: String? = nil, url: String) {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedTitle?.isEmpty == true ? nil : trimmedTitle
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var webURL: URL? {
        guard let parsed = URL(string: url),
              parsed.scheme?.lowercased() == "https",
              parsed.host?.isEmpty == false else {
            return nil
        }
        return parsed
    }
}

struct NewsMediaMetadata: Codable, Equatable {
    let caption: String?
    let alternativeText: String?
    let credit: String?

    nonisolated init(caption: String? = nil, alternativeText: String? = nil, credit: String? = nil) {
        self.caption = Self.trimmed(caption)
        self.alternativeText = Self.trimmed(alternativeText)
        self.credit = Self.trimmed(credit)
    }

    nonisolated private static func trimmed(_ value: String?) -> String? {
        let result = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result?.isEmpty == true ? nil : result
    }
}

enum EventOccurrenceStatus: String, Codable {
    case scheduled
    case cancelled
}

struct EventOccurrence: Codable, Equatable, Identifiable {
    let id: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let status: EventOccurrenceStatus

    nonisolated init(
        id: String = UUID().uuidString,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        status: EventOccurrenceStatus = .scheduled
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.status = status
    }

    nonisolated var isValid: Bool {
        endDate >= startDate
    }
}

enum EventParticipationMode: String, Codable, CaseIterable, Identifiable {
    case none
    case inAppRegistration
    case externalRegistration
    case externalTickets

    var id: String { rawValue }

    nonisolated var usesInAppRegistration: Bool { self == .inAppRegistration }
    nonisolated var requiresExternalURL: Bool {
        self == .externalRegistration || self == .externalTickets
    }
}

enum EventPriceKind: String, Codable, CaseIterable, Identifiable {
    case unspecified
    case free
    case exact
    case startingFrom
    case range

    var id: String { rawValue }
}

struct EventPricing: Codable, Equatable {
    let kind: EventPriceKind
    let amount: Double?
    let maximumAmount: Double?
    let currencyCode: String
    let note: String?

    nonisolated init(
        kind: EventPriceKind = .unspecified,
        amount: Double? = nil,
        maximumAmount: Double? = nil,
        currencyCode: String = "EUR",
        note: String? = nil
    ) {
        self.kind = kind
        self.amount = amount.map { max(0, $0) }
        self.maximumAmount = maximumAmount.map { max(0, $0) }
        self.currencyCode = currencyCode.uppercased()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = trimmedNote?.isEmpty == true ? nil : trimmedNote
    }
}

extension Dictionary where Key == String, Value == NewsLocalizedContent {
    nonisolated func resolved(for language: AppLanguage) -> NewsLocalizedContent? {
        self[language.rawValue] ?? self[PublishedContentLanguage.ukrainian.rawValue] ?? values.first
    }
}

extension Dictionary where Key == String, Value == EventLocalizedContent {
    nonisolated func resolved(for language: AppLanguage) -> EventLocalizedContent? {
        self[language.rawValue] ?? self[PublishedContentLanguage.ukrainian.rawValue] ?? values.first
    }
}

extension Dictionary where Key == String, Value == OrganizationLocalizedContent {
    nonisolated func resolved(for language: AppLanguage) -> OrganizationLocalizedContent? {
        self[language.rawValue] ?? self[PublishedContentLanguage.ukrainian.rawValue] ?? values.first
    }
}
