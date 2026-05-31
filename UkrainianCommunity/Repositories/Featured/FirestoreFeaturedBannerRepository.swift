import FirebaseFirestore
import Foundation

struct FirestoreFeaturedBannerRepository: FeaturedBannerRepository {
    private enum Field: String {
        case id
        case title
        case subtitle
        case imageURL
        case actionType
        case actionTargetID
        case externalURL
        case regionScope
        case federalState
        case visibleSections
        case displayDurationSeconds
        case priority
        case isActive
        case startsAt
        case endsAt
        case createdAt
        case updatedAt
        case createdBy
        case updatedBy
    }

    private let collection = Firestore.firestore().collection(FeaturedBanner.collectionPath)
    private let validationService = FeaturedBannerValidationService()

    func fetchActiveBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async throws -> [FeaturedBanner] {
        do {
            let snapshot = try await collection
                .whereField(Field.isActive.rawValue, isEqualTo: true)
                .whereField(Field.visibleSections.rawValue, arrayContains: section.rawValue)
                .getDocuments()

            let banners = try snapshot.documents.map(makeBanner)
            return banners.activeFeaturedBanners(for: section, federalState: federalState)
        } catch {
            throw appError(from: error)
        }
    }

    func fetchAllBanners() async throws -> [FeaturedBanner] {
        try await fetchAllBannersForOwner()
    }

    func fetchAllBannersForOwner() async throws -> [FeaturedBanner] {
        do {
            let snapshot = try await collection.getDocuments()
            return try snapshot.documents
                .map(makeBanner)
                .sorted { lhs, rhs in
                    if lhs.priority != rhs.priority {
                        return lhs.priority > rhs.priority
                    }
                    return lhs.updatedAt > rhs.updatedAt
                }
        } catch {
            throw appError(from: error)
        }
    }

    func createBanner(_ banner: FeaturedBanner) async throws {
        do {
            try validationService.validate(banner)
            try await collection.document(banner.id).setData(makeData(from: banner))
        } catch {
            throw appError(from: error)
        }
    }

    func updateBanner(_ banner: FeaturedBanner) async throws {
        do {
            try validationService.validate(banner)
            let document = collection.document(banner.id)
            let snapshot = try await document.getDocument()
            guard snapshot.exists else {
                throw AppError.notFound
            }
            let existingBanner = try makeBanner(id: banner.id, data: snapshot.data() ?? [:])
            let updatedBanner = FeaturedBanner(
                id: banner.id,
                title: banner.title,
                subtitle: banner.subtitle,
                imageURL: banner.imageURL,
                actionType: banner.actionType,
                actionTargetID: banner.actionTargetID,
                externalURL: banner.externalURL,
                regionScope: banner.regionScope,
                federalState: banner.federalState,
                visibleSections: banner.visibleSections,
                displayDurationSeconds: banner.displayDurationSeconds,
                priority: banner.priority,
                isActive: banner.isActive,
                startsAt: banner.startsAt,
                endsAt: banner.endsAt,
                createdAt: existingBanner.createdAt,
                updatedAt: Date(),
                createdBy: existingBanner.createdBy,
                updatedBy: banner.updatedBy
            )
            try validationService.validate(updatedBanner)
            try await document.setData(makeData(from: updatedBanner))
        } catch {
            throw appError(from: error)
        }
    }

    func setBannerActive(id: String, isActive: Bool, updatedBy userID: String) async throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedUserID.isEmpty else {
            throw AppError.validationFailed
        }

        do {
            let document = collection.document(trimmedID)
            let snapshot = try await document.getDocument()
            guard snapshot.exists else {
                throw AppError.notFound
            }
            try await document.updateData([
                Field.isActive.rawValue: isActive,
                Field.updatedAt.rawValue: Timestamp(date: Date()),
                Field.updatedBy.rawValue: trimmedUserID
            ])
        } catch {
            throw appError(from: error)
        }
    }

    func archiveBanner(id: String, updatedBy userID: String) async throws {
        try await setBannerActive(id: id, isActive: false, updatedBy: userID)
    }

    func deleteBanner(id: String) async throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw AppError.validationFailed
        }

        do {
            try await collection.document(trimmedID).delete()
        } catch {
            throw appError(from: error)
        }
    }

    private func makeBanner(from document: QueryDocumentSnapshot) throws -> FeaturedBanner {
        let data = document.data()
        return try makeBanner(id: document.documentID, data: data)
    }

    private func makeBanner(id documentID: String, data: [String: Any]) throws -> FeaturedBanner {
        guard
            let title = data[Field.title.rawValue] as? String,
            let actionTypeValue = data[Field.actionType.rawValue] as? String,
            let actionType = FeaturedBannerActionType(rawValue: actionTypeValue),
            let regionScopeValue = data[Field.regionScope.rawValue] as? String,
            let regionScope = FeaturedBannerRegionScope(rawValue: regionScopeValue),
            let visibleSectionValues = data[Field.visibleSections.rawValue] as? [String],
            let displayDurationSeconds = intValue(data[Field.displayDurationSeconds.rawValue]),
            let priority = intValue(data[Field.priority.rawValue]),
            let isActive = data[Field.isActive.rawValue] as? Bool,
            let createdAt = timestampDate(data[Field.createdAt.rawValue]),
            let updatedAt = timestampDate(data[Field.updatedAt.rawValue]),
            let createdBy = data[Field.createdBy.rawValue] as? String
        else {
            throw AppError.validationFailed
        }

        let visibleSections = Set(visibleSectionValues.compactMap(FeaturedBannerVisibleSection.init(rawValue:)))
        guard visibleSections.count == visibleSectionValues.count else {
            throw AppError.validationFailed
        }

        let federalState = (data[Field.federalState.rawValue] as? String).flatMap(AustrianFederalState.init(rawValue:))
        let banner = FeaturedBanner(
            id: (data[Field.id.rawValue] as? String) ?? documentID,
            title: title,
            subtitle: data[Field.subtitle.rawValue] as? String,
            imageURL: data[Field.imageURL.rawValue] as? String,
            actionType: actionType,
            actionTargetID: data[Field.actionTargetID.rawValue] as? String,
            externalURL: data[Field.externalURL.rawValue] as? String,
            regionScope: regionScope,
            federalState: federalState,
            visibleSections: visibleSections,
            displayDurationSeconds: displayDurationSeconds,
            priority: priority,
            isActive: isActive,
            startsAt: timestampDate(data[Field.startsAt.rawValue]),
            endsAt: timestampDate(data[Field.endsAt.rawValue]),
            createdAt: createdAt,
            updatedAt: updatedAt,
            createdBy: createdBy,
            updatedBy: data[Field.updatedBy.rawValue] as? String
        )
        try validationService.validate(banner)
        return banner
    }

    private func makeData(from banner: FeaturedBanner) -> [String: Any] {
        var data: [String: Any] = [
            Field.id.rawValue: banner.id,
            Field.title.rawValue: banner.title,
            Field.imageURL.rawValue: nonEmpty(banner.imageURL) ?? "",
            Field.actionType.rawValue: banner.actionType.rawValue,
            Field.regionScope.rawValue: banner.regionScope.rawValue,
            Field.visibleSections.rawValue: banner.visibleSections.map(\.rawValue).sorted(),
            Field.displayDurationSeconds.rawValue: banner.displayDurationSeconds,
            Field.priority.rawValue: banner.priority,
            Field.isActive.rawValue: banner.isActive,
            Field.createdAt.rawValue: Timestamp(date: banner.createdAt),
            Field.updatedAt.rawValue: Timestamp(date: banner.updatedAt),
            Field.createdBy.rawValue: banner.createdBy
        ]

        if let subtitle = nonEmpty(banner.subtitle) {
            data[Field.subtitle.rawValue] = subtitle
        }
        if let actionTargetID = nonEmpty(banner.actionTargetID) {
            data[Field.actionTargetID.rawValue] = actionTargetID
        }
        if let externalURL = nonEmpty(banner.externalURL) {
            data[Field.externalURL.rawValue] = externalURL
        }
        if let federalState = banner.federalState {
            data[Field.federalState.rawValue] = federalState.rawValue
        }
        if let startsAt = banner.startsAt {
            data[Field.startsAt.rawValue] = Timestamp(date: startsAt)
        }
        if let endsAt = banner.endsAt {
            data[Field.endsAt.rawValue] = Timestamp(date: endsAt)
        }
        if let updatedBy = nonEmpty(banner.updatedBy) {
            data[Field.updatedBy.rawValue] = updatedBy
        }

        return data
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private func timestampDate(_ value: Any?) -> Date? {
        (value as? Timestamp)?.dateValue()
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func appError(from error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        let nsError = error as NSError
        guard let code = FirestoreErrorCode.Code(rawValue: nsError.code) else {
            return .unknown
        }

        switch code {
        case .permissionDenied:
            return .permissionDenied
        case .notFound:
            return .notFound
        case .unavailable, .deadlineExceeded:
            return .network
        default:
            return .unknown
        }
    }
}
