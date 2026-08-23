import FirebaseFunctions
import FirebaseFirestore
import Foundation

struct FirestoreFeaturedBannerRepository: FeaturedBannerRepository {
    private enum Field: String, CaseIterable {
        case id
        case internalName
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
    private let mutationClient: any FeaturedBannerMutationClient

    init(mutationClient: any FeaturedBannerMutationClient = CloudFunctionsClient.shared) {
        self.mutationClient = mutationClient
    }

    func fetchActiveBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async throws -> [FeaturedBanner] {
        guard section.isSupported else {
            throw AppError.validationFailed
        }

        do {
            let snapshot = try await collection
                .whereField(Field.isActive.rawValue, isEqualTo: true)
                .whereField(
                    Field.actionType.rawValue,
                    in: FeaturedBannerActionType.supportedCases.map(\.rawValue)
                )
                .whereField(Field.visibleSections.rawValue, arrayContains: section.rawValue)
                .getDocuments()

            var banners: [FeaturedBanner] = []
            var malformedDocumentCount = 0
            for document in snapshot.documents {
                do {
                    banners.append(try makeBanner(from: document, allowsUnsupportedLegacy: true))
                } catch {
                    malformedDocumentCount += 1
                }
            }

            if banners.isEmpty, malformedDocumentCount > 0 {
                throw AppError.validationFailed
            }
            return banners.activeFeaturedBanners(for: section, federalState: federalState)
        } catch {
            throw appError(from: error)
        }
    }

    func fetchAllBannersForOwner() async throws -> [FeaturedBanner] {
        do {
            let snapshot = try await collection.getDocuments()
            var banners: [FeaturedBanner] = []
            for document in snapshot.documents {
                do {
                    banners.append(try makeBanner(from: document, allowsUnsupportedLegacy: true))
                } catch {
                    banners.append(makeRecoverableOwnerBanner(from: document))
                    await SystemTechnicalErrorLoggingService.shared.logFailure(
                        error,
                        context: SystemTechnicalErrorContext(
                            moduleName: "FeaturedBanners",
                            operationName: "decodeOwnerBanner",
                            targetType: .systemConfiguration,
                            targetId: document.documentID,
                            metadata: ["recoveryMode": "managementPlaceholder"]
                        )
                    )
                }
            }

            return banners.sorted { lhs, rhs in
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
        try validationService.validate(banner)
        do {
            try await mutationClient.saveFeaturedBanner(banner, mode: .create)
        } catch {
            throw appError(from: error)
        }

        await SystemAuditLoggingService.shared.logSuccess(
            SystemAuditLogContext(
                moduleName: "FeaturedBanners",
                operationName: "createBanner",
                eventType: .contentCreated,
                targetType: .systemConfiguration,
                targetId: banner.id,
                targetTitle: banner.title,
                summary: "Featured banner created"
            )
        )
    }

    func updateBanner(_ banner: FeaturedBanner) async throws {
        try validationService.validate(banner)
        do {
            try await mutationClient.saveFeaturedBanner(banner, mode: .update)
        } catch {
            throw appError(from: error)
        }

        await SystemAuditLoggingService.shared.logSuccess(
            SystemAuditLogContext(
                moduleName: "FeaturedBanners",
                operationName: "updateBanner",
                eventType: .contentUpdated,
                targetType: .systemConfiguration,
                targetId: banner.id,
                targetTitle: banner.title,
                summary: "Featured banner updated"
            )
        )
    }

    func setBannerActive(id: String, isActive: Bool, updatedBy userID: String) async throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedUserID.isEmpty else {
            throw AppError.validationFailed
        }

        do {
            try await mutationClient.setFeaturedBannerActive(id: trimmedID, isActive: isActive)
        } catch {
            throw appError(from: error)
        }
    }

    func deleteBanner(id: String) async throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw AppError.validationFailed
        }

        do {
            try await mutationClient.deleteFeaturedBanner(id: trimmedID)
        } catch {
            throw appError(from: error)
        }

        await SystemAuditLoggingService.shared.logSuccess(
            SystemAuditLogContext(
                moduleName: "FeaturedBanners",
                operationName: "deleteBanner",
                eventType: .contentDeleted,
                targetType: .systemConfiguration,
                targetId: trimmedID,
                summary: "Featured banner deleted"
            )
        )
    }

    private func makeBanner(
        from document: QueryDocumentSnapshot,
        allowsUnsupportedLegacy: Bool = false
    ) throws -> FeaturedBanner {
        let data = document.data()
        return try makeBanner(
            id: document.documentID,
            data: data,
            allowsUnsupportedLegacy: allowsUnsupportedLegacy
        )
    }

    private func makeBanner(
        id documentID: String,
        data: [String: Any],
        allowsUnsupportedLegacy: Bool = false
    ) throws -> FeaturedBanner {
        guard
            let actionTypeValue = data[Field.actionType.rawValue] as? String,
            let actionType = FeaturedBannerActionType.normalized(from: actionTypeValue),
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
        let storedID = data[Field.id.rawValue] as? String
        let hasUnknownFields = !Set(data.keys).isSubset(of: Set(Field.allCases.map(\.rawValue)))
        let banner = FeaturedBanner(
            id: documentID,
            internalName: data[Field.internalName.rawValue] as? String,
            title: data[Field.title.rawValue] as? String ?? "",
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
            updatedBy: data[Field.updatedBy.rawValue] as? String,
            requiresDataRepair: actionTypeValue != actionType.rawValue
                || storedID != documentID
                || hasUnknownFields
        )
        try validationService.validate(banner, allowsUnsupportedLegacy: allowsUnsupportedLegacy)
        return banner
    }

    private func makeRecoverableOwnerBanner(from document: QueryDocumentSnapshot) -> FeaturedBanner {
        makeRecoverableOwnerBanner(id: document.documentID, data: document.data())
    }

    private func makeRecoverableOwnerBanner(id documentID: String, data: [String: Any]) -> FeaturedBanner {
        let rawSections = data[Field.visibleSections.rawValue] as? [String] ?? []
        var visibleSections = Set(rawSections.compactMap(FeaturedBannerVisibleSection.init(rawValue:)))
        if visibleSections.isEmpty || visibleSections.count != rawSections.count {
            visibleSections.insert(.unsupportedLegacy)
        }

        let rawAction = data[Field.actionType.rawValue] as? String ?? ""
        let actionType = FeaturedBannerActionType.normalized(from: rawAction) ?? .unsupportedLegacy
        let rawRegionScope = data[Field.regionScope.rawValue] as? String ?? ""
        let regionScope = FeaturedBannerRegionScope(rawValue: rawRegionScope) ?? .allAustria
        let createdAt = timestampDate(data[Field.createdAt.rawValue]) ?? .distantPast
        let updatedAt = timestampDate(data[Field.updatedAt.rawValue]) ?? createdAt

        return FeaturedBanner(
            id: documentID,
            internalName: data[Field.internalName.rawValue] as? String,
            title: data[Field.title.rawValue] as? String ?? "",
            subtitle: data[Field.subtitle.rawValue] as? String,
            imageURL: data[Field.imageURL.rawValue] as? String,
            actionType: actionType,
            actionTargetID: data[Field.actionTargetID.rawValue] as? String,
            externalURL: data[Field.externalURL.rawValue] as? String,
            regionScope: regionScope,
            federalState: (data[Field.federalState.rawValue] as? String).flatMap(AustrianFederalState.init(rawValue:)),
            visibleSections: visibleSections,
            displayDurationSeconds: min(
                max(intValue(data[Field.displayDurationSeconds.rawValue]) ?? 6, FeaturedBannerValidationService.displayDurationBounds.lowerBound),
                FeaturedBannerValidationService.displayDurationBounds.upperBound
            ),
            priority: min(
                max(intValue(data[Field.priority.rawValue]) ?? 0, FeaturedBannerValidationService.priorityBounds.lowerBound),
                FeaturedBannerValidationService.priorityBounds.upperBound
            ),
            isActive: data[Field.isActive.rawValue] as? Bool ?? false,
            startsAt: timestampDate(data[Field.startsAt.rawValue]),
            endsAt: timestampDate(data[Field.endsAt.rawValue]),
            createdAt: createdAt,
            updatedAt: updatedAt,
            createdBy: data[Field.createdBy.rawValue] as? String ?? "",
            updatedBy: data[Field.updatedBy.rawValue] as? String,
            requiresDataRepair: true
        )
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

    private func appError(from error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        let nsError = error as NSError
        switch FunctionsErrorCode(rawValue: nsError.code) {
        case .permissionDenied, .unauthenticated:
            return .permissionDenied
        case .notFound:
            return .notFound
        case .invalidArgument, .alreadyExists, .failedPrecondition:
            return .validationFailed
        case .unavailable, .deadlineExceeded:
            return .network
        default:
            break
        }

        switch FirestoreErrorCode.Code(rawValue: nsError.code) {
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
