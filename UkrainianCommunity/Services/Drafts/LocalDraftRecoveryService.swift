import Foundation

struct NewsCreateDraft: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let updatedAt: Date
    let organizationId: String?
    let organizationName: String?
    let organizationImageURL: String?
    let organizationFederalState: AustrianFederalState?
    let title: String
    let summary: String
    let body: String
    let sourceInput: String
    let tagsInput: String
    let selectedFederalState: AustrianFederalState?

    var hasMeaningfulContent: Bool {
        [title, summary, body, sourceInput, tagsInput]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct EventCreateDraft: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let hasMeaningfulMetadata: Bool?
    let updatedAt: Date
    let organizationId: String?
    let organizationName: String?
    let organizationImageURL: String?
    let organizationFederalState: AustrianFederalState?
    let title: String
    let summary: String
    let details: String
    let city: String
    let venue: String
    let address: String
    let locationNote: String
    let latitude: Double?
    let longitude: Double?
    let eventOrganizerName: String
    let organizerURL: String
    let contactPhone: String
    let contactEmail: String
    let contactURL: String
    let selectedFederalState: AustrianFederalState
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let selectedCategory: EventCategory
    let tags: [String]
    let tagInput: String
    let requiresRegistration: Bool
    let priceText: String
    let capacityText: String

    var hasMeaningfulContent: Bool {
        [
            title,
            summary,
            details,
            city,
            venue,
            address,
            locationNote,
            eventOrganizerName,
            organizerURL,
            contactPhone,
            contactEmail,
            contactURL,
            tagInput,
            priceText,
            capacityText
        ]
        .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        || !tags.isEmpty
        || latitude != nil
        || longitude != nil
        || hasMeaningfulMetadata == true
    }
}

struct OrganizationCreateDraft: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let hasMeaningfulMetadata: Bool?
    let updatedAt: Date
    let name: String
    let shortDescription: String
    let fullDescription: String
    let city: String
    let address: String
    let selectedFederalState: AustrianFederalState?
    let email: String
    let phone: String
    let website: String
    let telegramURL: String
    let donationURL: String
    let facebookURL: String?
    let instagramURL: String?
    let whatsappURL: String?
    let youtubeURL: String?
    let linkedinURL: String?
    let missionStatement: String
    let contactPerson: String
    let organizationType: String
    let foundedYear: String
    let foundedMonth: Int?
    let languages: String
    let socialLinks: String

    var hasMeaningfulContent: Bool {
        [
            name,
            shortDescription,
            fullDescription,
            city,
            address,
            email,
            phone,
            website,
            telegramURL,
            donationURL,
            facebookURL ?? "",
            instagramURL ?? "",
            whatsappURL ?? "",
            youtubeURL ?? "",
            linkedinURL ?? "",
            missionStatement,
            contactPerson,
            foundedYear,
            languages,
            socialLinks
        ]
        .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        || hasMeaningfulMetadata == true
    }
}

@MainActor
final class LocalDraftRecoveryService {
    static let shared = LocalDraftRecoveryService()

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let directoryName = "DraftRecovery"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadNewsCreateDraft(key: String) async throws -> NewsCreateDraft? {
        let url = try draftURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(NewsCreateDraft.self, from: data)
    }

    func saveNewsCreateDraft(_ draft: NewsCreateDraft, key: String) async throws {
        let url = try draftURL(for: key)
        let data = try encoder.encode(draft)
        try data.write(to: url, options: [.atomic])
    }

    func deleteNewsCreateDraft(key: String) async throws {
        let url = try draftURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func loadEventCreateDraft(key: String) async throws -> EventCreateDraft? {
        let url = try draftURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(EventCreateDraft.self, from: data)
    }

    func saveEventCreateDraft(_ draft: EventCreateDraft, key: String) async throws {
        let url = try draftURL(for: key)
        let data = try encoder.encode(draft)
        try data.write(to: url, options: [.atomic])
    }

    func deleteEventCreateDraft(key: String) async throws {
        let url = try draftURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func loadOrganizationCreateDraft(key: String) async throws -> OrganizationCreateDraft? {
        let url = try draftURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(OrganizationCreateDraft.self, from: data)
    }

    func saveOrganizationCreateDraft(_ draft: OrganizationCreateDraft, key: String) async throws {
        let url = try draftURL(for: key)
        let data = try encoder.encode(draft)
        try data.write(to: url, options: [.atomic])
    }

    func deleteOrganizationCreateDraft(key: String) async throws {
        let url = try draftURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func draftURL(for key: String) throws -> URL {
        let directoryURL = try draftsDirectoryURL()
        return directoryURL.appendingPathComponent(sanitizedFileName(for: key), isDirectory: false)
    }

    private func draftsDirectoryURL() throws -> URL {
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = supportURL
            .appendingPathComponent("UkrainianCommunity", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func sanitizedFileName(for key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = key.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scalars) + ".json"
    }
}
