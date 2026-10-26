import FirebaseFunctions
import FirebaseFirestore
import Foundation

struct FirestoreFeaturedBannerRepository: FeaturedBannerRepository {
    private enum Field: String, CaseIterable {
        case id
        case internalName
        case localizations
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
            // Keep scheduled and recently expired active documents in memory so
            // the presentation layer can re-evaluate time boundaries without a
            // network request.
            return try await withPresentations(banners.eligibleFeaturedBanners(for: section, federalState: federalState), includeInactive: false)
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
                            targetTitle: document.data()[Field.internalName.rawValue] as? String ?? document.data()[Field.title.rawValue] as? String,
                            metadata: ["recoveryMode": "managementPlaceholder"]
                        )
                    )
                }
            }

            return try await withPresentations(banners, includeInactive: true).sorted { lhs, rhs in
                    if lhs.priority != rhs.priority {
                        return lhs.priority > rhs.priority
                    }
                    return lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt > rhs.updatedAt
                }
        } catch {
            throw appError(from: error)
        }
    }

    func saveBanner(_ banner: FeaturedBanner, isNew: Bool, expectedUpdatedAt: Date?, operationID: String) async throws {
        try validationService.validate(banner)
        do {
            try await mutationClient.saveFeaturedBanner(banner, mode: isNew ? .create : .update, expectedUpdatedAt: expectedUpdatedAt, operationID: operationID)
        } catch {
            if error is CancellationError { throw error }
            let failure = error as NSError
            let code = failure.domain == FunctionsErrorDomain ? FunctionsErrorCode(rawValue: failure.code) : nil
            let mapped = appError(from: error)
            if mapped == .network || mapped == .unknown || code == .alreadyExists || code == .aborted {
                // A lost reply does not prove failure. Accept only an exact authoritative content match.
                if let raw = try? await collection.document(banner.id).getDocument(source: .server), let data = raw.data(),
                   let stored = try? makeBanner(id: raw.documentID, data: data),
                   let resolved = try? await withPresentations([stored], includeInactive: true).first,
                   let actual = try? FeaturedBannerMutationPayload(banner: resolved),
                   let expected = try? FeaturedBannerMutationPayload(banner: banner), actual == expected { return }
            }
            if code == .aborted || code == .alreadyExists { throw FeaturedBannerSaveConflict() }
            throw mapped
        }
    }

    func createBanner(_ banner: FeaturedBanner) async throws {
        try validationService.validate(banner)
        do {
            try await mutationClient.saveFeaturedBanner(banner, mode: .create, expectedUpdatedAt: nil, operationID: UUID().uuidString)
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
            try await mutationClient.saveFeaturedBanner(banner, mode: .update, expectedUpdatedAt: nil, operationID: UUID().uuidString)
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

    private func withPresentations(_ banners: [FeaturedBanner], includeInactive: Bool) async throws -> [FeaturedBanner] {
        guard !banners.isEmpty else { return [] }
        var configurations: [String: FeaturedBannerCountdown] = [:]
        var configuredEnds: [String: Date] = [:]
        var restoredEndIDs = Set<String>()
        for start in stride(from: 0, to: banners.count, by: 100) {
            let ids = Array(banners[start..<min(start + 100, banners.count)].map(\.id))
            let callable = Functions.functions(region: "europe-west3").httpsCallable("getFeaturedBannerPresentations")
            callable.timeoutInterval = 15
            let result = try await callable.call(["ids": ids, "includeInactive": includeInactive])
            try Task.checkCancellation()
            guard let response = result.data as? [String: Any], let rows = response["presentations"] as? [[String: Any]] else { throw AppError.validationFailed }
            for row in rows {
                guard let id = row["id"] as? String, ids.contains(id) else { throw AppError.validationFailed }
                if let raw = row["countdown"] as? [String: Any] {
                    guard let countdown = Self.decodeCountdown(raw) else { throw AppError.validationFailed }
                    configurations[id] = countdown
                }
                if let value = row["configuredEndsAt"] {
                    restoredEndIDs.insert(id)
                    if let text = value as? String {
                        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        guard let date = formatter.date(from: text) else { throw AppError.validationFailed }
                        configuredEnds[id] = date
                    } else if !(value is NSNull) { throw AppError.validationFailed }
                }
            }
        }
        return banners.map { banner in
            var copy = banner; copy.countdown = configurations[banner.id]
            if restoredEndIDs.contains(banner.id) { copy.endsAt = configuredEnds[banner.id] }
            return copy
        }
    }

    static func decodeCountdown(_ value: [String: Any]) -> FeaturedBannerCountdown? {
        guard let target = value["targetDate"] as? String,
              let label = value["label"] as? String, let german = value["germanLabel"] as? String,
              let completion = (value["completion"] as? String).flatMap(FeaturedBannerCountdown.Completion.init(rawValue:)) else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: target) else { return nil }
        let countdown = FeaturedBannerCountdown(targetDate: date, label: label, germanLabel: german, completion: completion)
        return countdown.isValid ? countdown : nil
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
        func required<T>(_ value: T?, _ field: Field) throws -> T {
            guard let value else { throw FeaturedBannerDataIssue(field: field.rawValue, rule: "missingOrInvalidType") }
            return value
        }
        let actionTypeValue = try required(data[Field.actionType.rawValue] as? String, .actionType)
        let actionType = try required(FeaturedBannerActionType.normalized(from: actionTypeValue), .actionType)
        let regionScopeValue = try required(data[Field.regionScope.rawValue] as? String, .regionScope)
        let regionScope = try required(FeaturedBannerRegionScope(rawValue: regionScopeValue), .regionScope)
        let visibleSectionValues = try required(data[Field.visibleSections.rawValue] as? [String], .visibleSections)
        let displayDurationSeconds = try required(intValue(data[Field.displayDurationSeconds.rawValue]), .displayDurationSeconds)
        let priority = try required(intValue(data[Field.priority.rawValue]), .priority)
        let isActive = try required(data[Field.isActive.rawValue] as? Bool, .isActive)
        let createdAt = try required(timestampDate(data[Field.createdAt.rawValue]), .createdAt)
        let updatedAt = try required(timestampDate(data[Field.updatedAt.rawValue]), .updatedAt)
        let createdBy = try required(data[Field.createdBy.rawValue] as? String, .createdBy)
        let visibleSections = Set(visibleSectionValues.compactMap(FeaturedBannerVisibleSection.init(rawValue:)))
        guard visibleSections.count == visibleSectionValues.count else {
            throw FeaturedBannerDataIssue(field: "visibleSections", rule: "unknownOrDuplicateSection")
        }

        let federalState = (data[Field.federalState.rawValue] as? String).flatMap(AustrianFederalState.init(rawValue:))
        let storedID = data[Field.id.rawValue] as? String
        let hasUnknownFields = !Set(data.keys).isSubset(of: Set(Field.allCases.map(\.rawValue)))
        let localizations = try localizedContent(from: data[Field.localizations.rawValue])
        let banner = FeaturedBanner(
            id: documentID,
            internalName: data[Field.internalName.rawValue] as? String,
            localizations: localizations,
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
        if let issue = validationService.diagnosticIssue(banner, allowsUnsupportedLegacy: allowsUnsupportedLegacy) { throw issue }
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
            localizations: (try? localizedContent(from: data[Field.localizations.rawValue])) ?? [:],
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

    private func localizedContent(from value: Any?) throws -> [String: FeaturedBannerLocalizedContent] {
        guard let value else { return [:] }
        guard let rawLocalizations = value as? [String: Any] else {
            throw FeaturedBannerDataIssue(field: "localizations", rule: "invalidType")
        }

        var result: [String: FeaturedBannerLocalizedContent] = [:]
        for (language, rawContent) in rawLocalizations {
            guard PublishedContentLanguage(rawValue: language) != nil,
                  let content = rawContent as? [String: Any],
                  Set(content.keys).isSubset(of: ["title", "subtitle"]),
                  let title = content["title"] as? String,
                  let subtitle = content["subtitle"] as? String else {
                throw FeaturedBannerDataIssue(field: "localizations", rule: "invalidLocalizedFields")
            }
            result[language] = FeaturedBannerLocalizedContent(title: title, subtitle: subtitle)
        }
        return result
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
        case .invalidArgument, .alreadyExists, .failedPrecondition, .aborted:
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
