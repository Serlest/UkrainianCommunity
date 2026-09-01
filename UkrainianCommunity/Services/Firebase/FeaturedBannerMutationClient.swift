import Foundation

enum FeaturedBannerSaveFunctionMode: String, Codable, Equatable {
    case create
    case update
}

struct FeaturedBannerMutationPayload: Codable, Equatable {
    let id: String
    let internalName: String?
    let localizations: [String: FeaturedBannerLocalizedContent]
    let title: String?
    let subtitle: String?
    let imageURL: String
    let actionType: String
    let actionTargetID: String?
    let externalURL: String?
    let regionScope: String
    let federalState: String?
    let visibleSections: [String]
    let displayDurationSeconds: Int
    let priority: Int
    let isActive: Bool
    let startsAt: String?
    let endsAt: String?

    init(banner: FeaturedBanner) throws {
        guard let imageURL = Self.nonEmpty(banner.imageURL) else {
            throw AppError.validationFailed
        }

        id = banner.id
        internalName = Self.nonEmpty(banner.internalName)
        localizations = banner.localizations
        title = Self.nonEmpty(banner.title)
        subtitle = Self.nonEmpty(banner.subtitle)
        self.imageURL = imageURL
        actionType = banner.actionType.rawValue
        actionTargetID = Self.nonEmpty(banner.actionTargetID)
        externalURL = Self.nonEmpty(banner.externalURL)
        regionScope = banner.regionScope.rawValue
        federalState = banner.federalState?.rawValue
        visibleSections = banner.visibleSections.map(\.rawValue).sorted()
        displayDurationSeconds = banner.displayDurationSeconds
        priority = banner.priority
        isActive = banner.isActive
        startsAt = banner.startsAt.map(Self.dateFormatter.string(from:))
        endsAt = banner.endsAt.map(Self.dateFormatter.string(from:))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct FeaturedBannerSaveFunctionRequest: Codable, Equatable {
    let mode: FeaturedBannerSaveFunctionMode
    let banner: FeaturedBannerMutationPayload
}

struct FeaturedBannerIDFunctionRequest: Codable, Equatable {
    let id: String
}

struct FeaturedBannerActiveFunctionRequest: Codable, Equatable {
    let id: String
    let isActive: Bool
}

struct FeaturedBannerMutationFunctionResponse: Codable, Equatable {
    let id: String
    let updatedAt: String
}

protocol FeaturedBannerMutationClient {
    func saveFeaturedBanner(
        _ banner: FeaturedBanner,
        mode: FeaturedBannerSaveFunctionMode
    ) async throws
    func setFeaturedBannerActive(id: String, isActive: Bool) async throws
    func deleteFeaturedBanner(id: String) async throws
}

extension CloudFunctionsClient: FeaturedBannerMutationClient {
    func saveFeaturedBanner(
        _ banner: FeaturedBanner,
        mode: FeaturedBannerSaveFunctionMode
    ) async throws {
        let _: FeaturedBannerMutationFunctionResponse = try await call(
            .saveFeaturedBanner,
            request: FeaturedBannerSaveFunctionRequest(
                mode: mode,
                banner: try FeaturedBannerMutationPayload(banner: banner)
            )
        )
    }

    func setFeaturedBannerActive(id: String, isActive: Bool) async throws {
        let _: FeaturedBannerMutationFunctionResponse = try await call(
            .setFeaturedBannerActive,
            request: FeaturedBannerActiveFunctionRequest(id: id, isActive: isActive)
        )
    }

    func deleteFeaturedBanner(id: String) async throws {
        let _: FeaturedBannerMutationFunctionResponse = try await call(
            .deleteFeaturedBanner,
            request: FeaturedBannerIDFunctionRequest(id: id)
        )
    }
}
