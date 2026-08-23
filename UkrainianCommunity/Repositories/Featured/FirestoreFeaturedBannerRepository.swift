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
        let data = makeData(from: banner)

        do {
            try await collection.document(banner.id).setData(data)
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "FeaturedBanners",
                    operationName: "createBanner",
                    targetType: .systemConfiguration,
                    targetId: banner.id,
                    targetTitle: banner.title
                )
            )
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
        let document = collection.document(banner.id)
        let snapshot = try await document.getDocument()
        guard snapshot.exists else {
            throw AppError.notFound
        }
        let existingData = snapshot.data() ?? [:]
        let existingBanner: FeaturedBanner
        do {
            existingBanner = try makeBanner(
                id: banner.id,
                data: existingData,
                allowsUnsupportedLegacy: true
            )
        } catch {
            existingBanner = makeRecoverableOwnerBanner(
                id: banner.id,
                data: existingData
            )
        }
        let updatedBanner = FeaturedBanner(
            id: banner.id,
            internalName: banner.internalName,
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
            createdAt: existingBanner.createdAt == .distantPast
                ? banner.createdAt
                : existingBanner.createdAt,
            updatedAt: Date(),
            createdBy: nonEmpty(existingBanner.createdBy)
                ?? banner.createdBy,
            updatedBy: banner.updatedBy
        )
        try validationService.validate(updatedBanner)
        let data = makeUpdateData(
            from: updatedBanner,
            preservingIdentityFrom: existingData
        )

        do {
            try await document.setData(data)
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "FeaturedBanners",
                    operationName: "updateBanner",
                    targetType: .systemConfiguration,
                    targetId: banner.id,
                    targetTitle: banner.title
                )
            )
            throw appError(from: error)
        }

        await SystemAuditLoggingService.shared.logSuccess(
            SystemAuditLogContext(
                moduleName: "FeaturedBanners",
                operationName: "updateBanner",
                eventType: .contentUpdated,
                targetType: .systemConfiguration,
                targetId: updatedBanner.id,
                targetTitle: updatedBanner.title,
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

        let document = collection.document(trimmedID)
        let snapshot = try await document.getDocument()
        guard snapshot.exists else {
            throw AppError.notFound
        }
        let existingBanner: FeaturedBanner
        do {
            existingBanner = try makeBanner(
                id: trimmedID,
                data: snapshot.data() ?? [:],
                allowsUnsupportedLegacy: true
            )
        } catch {
            existingBanner = makeRecoverableOwnerBanner(
                id: trimmedID,
                data: snapshot.data() ?? [:]
            )
        }
        if existingBanner.hasUnsupportedLegacyConfiguration {
            guard existingBanner.isActive, !isActive else {
                throw AppError.validationFailed
            }
        }

        do {
            try await document.updateData([
                Field.isActive.rawValue: isActive,
                Field.updatedAt.rawValue: Timestamp(date: Date()),
                Field.updatedBy.rawValue: trimmedUserID
            ])
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "FeaturedBanners",
                    operationName: "setBannerActive",
                    targetType: .systemConfiguration,
                    targetId: trimmedID,
                    metadata: ["requestedActiveState": "\(isActive)"]
                )
            )
            throw appError(from: error)
        }
    }

    func deleteBanner(id: String) async throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw AppError.validationFailed
        }

        let document = collection.document(trimmedID)
        let snapshot = try await document.getDocument()
        guard snapshot.exists else {
            throw AppError.notFound
        }
        do {
            try await document.delete()
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "FeaturedBanners",
                    operationName: "deleteBanner",
                    targetType: .systemConfiguration,
                    targetId: trimmedID
                )
            )
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

    private func makeData(from banner: FeaturedBanner) -> [String: Any] {
        var data = makeMutableData(from: banner)
        data[Field.id.rawValue] = banner.id
        data[Field.createdAt.rawValue] = Timestamp(date: banner.createdAt)
        data[Field.createdBy.rawValue] = banner.createdBy
        return data
    }

    private func makeUpdateData(
        from banner: FeaturedBanner,
        preservingIdentityFrom existingData: [String: Any]
    ) -> [String: Any] {
        var data = makeData(from: banner)

        // Firestore timestamps have nanosecond precision. Preserve immutable
        // identity fields in their original representation so a Date
        // round-trip cannot make Security Rules treat them as modified.
        if let createdAt = existingData[Field.createdAt.rawValue] as? Timestamp {
            data[Field.createdAt.rawValue] = createdAt
        }
        if let createdBy = nonEmpty(existingData[Field.createdBy.rawValue] as? String) {
            data[Field.createdBy.rawValue] = createdBy
        }

        return data
    }

    private func makeMutableData(from banner: FeaturedBanner) -> [String: Any] {
        var data: [String: Any] = [
            Field.imageURL.rawValue: nonEmpty(banner.imageURL) ?? "",
            Field.actionType.rawValue: banner.actionType.rawValue,
            Field.regionScope.rawValue: banner.regionScope.rawValue,
            Field.visibleSections.rawValue: banner.visibleSections.map(\.rawValue).sorted(),
            Field.displayDurationSeconds.rawValue: banner.displayDurationSeconds,
            Field.priority.rawValue: banner.priority,
            Field.isActive.rawValue: banner.isActive,
            Field.updatedAt.rawValue: Timestamp(date: banner.updatedAt)
        ]

        setOptionalValue(nonEmpty(banner.title), forKey: Field.title.rawValue, in: &data)
        setOptionalValue(nonEmpty(banner.internalName), forKey: Field.internalName.rawValue, in: &data)
        setOptionalValue(nonEmpty(banner.subtitle), forKey: Field.subtitle.rawValue, in: &data)
        setOptionalValue(nonEmpty(banner.actionTargetID), forKey: Field.actionTargetID.rawValue, in: &data)
        setOptionalValue(nonEmpty(banner.externalURL), forKey: Field.externalURL.rawValue, in: &data)
        setOptionalValue(banner.federalState?.rawValue, forKey: Field.federalState.rawValue, in: &data)
        setOptionalValue(banner.startsAt.map(Timestamp.init(date:)), forKey: Field.startsAt.rawValue, in: &data)
        setOptionalValue(banner.endsAt.map(Timestamp.init(date:)), forKey: Field.endsAt.rawValue, in: &data)
        setOptionalValue(nonEmpty(banner.updatedBy), forKey: Field.updatedBy.rawValue, in: &data)

        return data
    }

    private func setOptionalValue(
        _ value: Any?,
        forKey key: String,
        in data: inout [String: Any]
    ) {
        if let value {
            data[key] = value
        }
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
