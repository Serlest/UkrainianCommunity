import FirebaseFirestore
import FirebaseFunctions
import Foundation

struct FirestoreOwnerContentDraftRepository: OwnerContentDraftRepository {
    private let database = Firestore.firestore()
    private let functions = Functions.functions(region: "europe-west3")

    func fetchDraftPage(
        userID: String,
        section: OwnerContentPlanningSection,
        limit: Int,
        after cursor: OwnerContentDraftPageCursor?
    ) async throws -> OwnerContentDraftPage {
        let pageSize = max(1, limit)
        let sortField = section.usesAscendingScheduleOrder ? "scheduledAt" : "updatedAt"
        let isDescending = !section.usesAscendingScheduleOrder
        var query: Query = collection(userID: userID)

        if section.states.count == 1, let state = section.states.first {
            query = query.whereField("state", isEqualTo: state.rawValue)
        } else {
            query = query.whereField("state", in: section.states.map(\.rawValue))
        }

        query = query
            .order(by: sortField, descending: isDescending)
            .order(by: FieldPath.documentID(), descending: isDescending)
            .limit(to: pageSize + 1)

        if let cursor {
            query = query.start(after: [Timestamp(date: cursor.sortDate), cursor.documentID])
        }

        do {
            let snapshot = try await query.getDocuments()
            let documents = Array(snapshot.documents.prefix(pageSize))
            let items = documents.compactMap(makeDraft)
            guard items.count == documents.count else {
                throw AppError.validationFailed
            }
            return OwnerContentDraftPage(
                items: items,
                nextCursor: documents.last.flatMap { document in
                    guard let sortDate = date(document.data()[sortField]) else { return nil }
                    return OwnerContentDraftPageCursor(sortDate: sortDate, documentID: document.documentID)
                },
                hasMore: snapshot.documents.count > pageSize
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.appError(from: error)
        }
    }

    func fetchDraft(userID: String, draftID: String) async throws -> OwnerContentDraft {
        do {
            let snapshot = try await collection(userID: userID).document(draftID).getDocument()
            guard snapshot.exists else { throw AppError.notFound }
            guard let draft = makeDraft(from: snapshot) else { throw AppError.validationFailed }
            return draft
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.appError(from: error)
        }
    }

    func beginPublication(
        userID: String,
        draftID: String,
        attemptID: String
    ) async throws -> OwnerContentPublicationLease {
        struct Request: Encodable {
            let draftId: String
            let attemptId: String
        }
        struct Response: Decodable {
            let draftId: String
            let kind: String
            let contentId: String
            let leaseId: String
            let expiresAt: String
            let contentAlreadyExists: Bool
            let existingModerationStatus: String?
            let existingScheduledAt: String?
        }

        do {
            let callable: Callable<Request, Response> = functions.httpsCallable("beginOwnerContentDraftPublication")
            let response = try await callable.call(Request(draftId: draftID, attemptId: attemptID))
            guard let kind = OwnerContentDraftKind(rawValue: response.kind),
                  let expiresAt = ISO8601DateFormatter().date(from: response.expiresAt),
                  response.existingModerationStatus == nil ||
                    ModerationStatus(rawValue: response.existingModerationStatus ?? "") != nil else {
                throw AppError.validationFailed
            }
            let existingScheduledAt = response.existingScheduledAt.flatMap {
                ISO8601DateFormatter().date(from: $0)
            }
            if response.existingScheduledAt != nil, existingScheduledAt == nil {
                throw AppError.validationFailed
            }
            let moderationStatus = response.existingModerationStatus.flatMap(ModerationStatus.init(rawValue:))
            guard response.contentAlreadyExists == (moderationStatus != nil),
                  moderationStatus == .draft || existingScheduledAt == nil else {
                throw AppError.validationFailed
            }
            return OwnerContentPublicationLease(
                draftID: response.draftId,
                kind: kind,
                contentID: response.contentId,
                leaseID: response.leaseId,
                expiresAt: expiresAt,
                contentAlreadyExists: response.contentAlreadyExists,
                existingModerationStatus: moderationStatus,
                existingScheduledAt: existingScheduledAt
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.appError(from: error)
        }
    }

    func finalizePublication(
        userID: String,
        draftID: String,
        publication: ContentPlanningPublicationResult
    ) async throws {
        guard let leaseID = publication.publicationLeaseID else {
            throw AppError.validationFailed
        }
        struct Request: Encodable {
            let draftId: String
            let leaseId: String
            let contentId: String
            let kind: String
        }
        struct Response: Decodable { let finalized: Bool }

        do {
            let callable: Callable<Request, Response> = functions.httpsCallable("finalizeOwnerContentDraftPublication")
            let response = try await callable.call(Request(
                draftId: draftID,
                leaseId: leaseID,
                contentId: publication.contentID,
                kind: publication.kind.rawValue
            ))
            guard response.finalized else { throw AppError.unknown }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.appError(from: error)
        }
    }

    func failPublication(
        userID: String,
        draftID: String,
        leaseID: String,
        message: String
    ) async throws {
        struct Request: Encodable {
            let draftId: String
            let leaseId: String
            let message: String
        }
        struct Response: Decodable { let failed: Bool }

        do {
            let callable: Callable<Request, Response> = functions.httpsCallable("failOwnerContentDraftPublication")
            _ = try await callable.call(Request(
                draftId: draftID,
                leaseId: leaseID,
                message: String(message.prefix(500))
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.appError(from: error)
        }
    }

    func archive(userID: String, draftID: String) async throws {
        struct Request: Encodable { let draftId: String }
        struct Response: Decodable { let archived: Bool }

        do {
            let callable: Callable<Request, Response> = functions.httpsCallable("archiveOwnerContentDraft")
            _ = try await callable.call(Request(draftId: draftID))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.appError(from: error)
        }
    }

    func delete(userID: String, draftID: String) async throws {
        struct Request: Encodable { let draftId: String }
        struct Response: Decodable { let deleted: Bool }

        do {
            let callable: Callable<Request, Response> = functions.httpsCallable("deleteOwnerContentDraft")
            _ = try await callable.call(Request(draftId: draftID))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.appError(from: error)
        }
    }

    private func collection(userID: String) -> CollectionReference {
        database.collection("users").document(userID).collection("contentPlanningDrafts")
    }

    private func makeDraft(from document: DocumentSnapshot) -> OwnerContentDraft? {
        guard let data = document.data() else { return nil }
        guard let kindRaw = data["kind"] as? String,
              let kind = OwnerContentDraftKind(rawValue: kindRaw),
              let stateRaw = data["state"] as? String,
              let state = OwnerContentDraftState(rawValue: stateRaw) else {
            return nil
        }
        let payload = data["payload"] as? [String: Any] ?? [:]

        let ownerUserID = document.reference.parent.parent?.documentID ?? string(data["ownerUserId"])
        let sources = (data["sources"] as? [[String: Any]] ?? []).compactMap(makeSource)
        let newsDraft = kind == .news ? makeNewsDraft(payload, updatedAt: date(data["updatedAt"]) ?? .now) : nil
        let eventDraft = kind == .event ? makeEventDraft(payload, updatedAt: date(data["updatedAt"]) ?? .now) : nil
        return OwnerContentDraft(
            id: document.documentID,
            schemaVersion: integer(data["schemaVersion"]) ?? 1,
            ownerUserID: ownerUserID,
            kind: kind,
            state: state,
            title: optionalString(data["title"]) ?? string(payload["title"]),
            sourceReferences: sources,
            verificationNotes: stringArray(data["verificationNotes"]),
            missingFields: stringArray(data["missingFields"]),
            newsDraft: newsDraft,
            eventDraft: eventDraft,
            createdAt: date(data["createdAt"]) ?? .now,
            updatedAt: date(data["updatedAt"]) ?? .now,
            scheduledAt: date(data["scheduledAt"]),
            completedAt: date(data["completedAt"]),
            archivedAt: date(data["archivedAt"]),
            failureMessage: optionalString(data["failureMessage"]),
            publicationLeaseExpiresAt: date(data["publicationLeaseExpiresAt"]),
            generatedImage: makeGeneratedImage(data["generatedImage"]),
            publishedContentID: optionalString(data["publishedContentId"]),
            publishedContentKind: optionalString(data["publishedContentKind"]).flatMap(OwnerContentDraftKind.init(rawValue:)),
            publishedOrganizationID: optionalString(data["publishedOrganizationId"]),
            publishedOrganizationName: optionalString(data["publishedOrganizationName"]),
            publicationOutcome: optionalString(data["publicationOutcome"]).flatMap(OwnerContentPublicationOutcome.init(rawValue:))
        )
    }

    private func makeGeneratedImage(_ value: Any?) -> OwnerContentGeneratedImage? {
        guard let data = value as? [String: Any],
              let url = optionalString(data["url"]),
              let storagePath = optionalString(data["storagePath"]) else { return nil }
        return OwnerContentGeneratedImage(
            url: url,
            storagePath: storagePath,
            alternativeText: optionalString(data["alternativeText"]),
            credit: optionalString(data["credit"])
        )
    }

    private func makeSource(_ data: [String: Any]) -> OwnerContentSourceReference? {
        guard let url = optionalString(data["url"]) else { return nil }
        return OwnerContentSourceReference(
            url: url,
            title: optionalString(data["title"]),
            isPrimary: data["isPrimary"] as? Bool ?? false,
            checkedAt: date(data["checkedAt"])
        )
    }

    private func makeNewsDraft(_ payload: [String: Any], updatedAt: Date) -> NewsCreateDraft? {
        let title = string(payload["title"])
        guard !title.isEmpty else { return nil }
        return NewsCreateDraft(
            version: NewsCreateDraft.currentVersion,
            updatedAt: updatedAt,
            organizationId: nil,
            organizationName: nil,
            organizationImageURL: nil,
            organizationFederalState: nil,
            title: title,
            summary: string(payload["summary"]),
            body: string(payload["body"]),
            sourceInput: string(payload["sourceInput"]),
            tagsInput: stringArray(payload["tags"]).joined(separator: ", "),
            selectedCategory: optionalString(payload["category"]).flatMap(NewsCategory.init(rawValue:)),
            additionalCategories: stringArray(payload["additionalCategories"]).compactMap(NewsCategory.init(rawValue:)),
            selectedFederalState: optionalString(payload["federalState"]).flatMap(AustrianFederalState.init(rawValue:)),
            germanTitle: optionalString(payload["germanTitle"]),
            germanSummary: optionalString(payload["germanSummary"]),
            germanBody: optionalString(payload["germanBody"]),
            imageCaption: optionalString(payload["imageCaption"]),
            imageAlternativeText: optionalString(payload["imageAlternativeText"]),
            imageCredit: optionalString(payload["imageCredit"]),
            externalActionTitle: optionalString(payload["externalActionTitle"]),
            externalActionURL: optionalString(payload["externalActionURL"]),
            generatedImageURL: optionalString(payload["generatedImageURL"]),
            regionScope: optionalString(payload["regionScope"]).flatMap(RegionScope.init(rawValue:)),
            publicationMode: optionalString(payload["publicationMode"]).flatMap(ContentPublicationMode.init(rawValue:)),
            scheduledAt: date(payload["scheduledAt"])
        )
    }

    private func makeEventDraft(_ payload: [String: Any], updatedAt: Date) -> EventCreateDraft? {
        let title = string(payload["title"])
        guard !title.isEmpty,
              let startDate = date(payload["startDate"]),
              let federalStateRaw = optionalString(payload["federalState"]),
              let federalState = AustrianFederalState(rawValue: federalStateRaw) else { return nil }
        let explicitEndDate = date(payload["endDate"])
        let endDate = explicitEndDate ?? startDate

        let occurrences = (payload["additionalOccurrences"] as? [[String: Any]] ?? []).compactMap { occurrence -> EventOccurrence? in
            guard let start = date(occurrence["startDate"]) else { return nil }
            let end = date(occurrence["endDate"]) ?? start
            return EventOccurrence(
                startDate: start,
                endDate: end,
                isAllDay: occurrence["isAllDay"] as? Bool ?? false
            )
        }
        let participationMode = optionalString(payload["participationMode"]).flatMap(EventParticipationMode.init(rawValue:)) ?? .none
        let priceKind = optionalString(payload["priceKind"]).flatMap(EventPriceKind.init(rawValue:)) ?? .unspecified

        return EventCreateDraft(
            version: EventCreateDraft.currentVersion,
            hasMeaningfulMetadata: true,
            updatedAt: updatedAt,
            organizationId: nil,
            organizationName: nil,
            organizationImageURL: nil,
            organizationFederalState: nil,
            title: title,
            summary: string(payload["summary"]),
            details: string(payload["details"]),
            city: string(payload["city"]),
            venue: string(payload["venue"]),
            address: string(payload["address"]),
            locationNote: string(payload["locationNote"]),
            latitude: double(payload["latitude"]),
            longitude: double(payload["longitude"]),
            eventOrganizerName: string(payload["eventOrganizerName"]),
            organizerURL: string(payload["organizerURL"]),
            contactPhone: string(payload["contactPhone"]),
            contactEmail: string(payload["contactEmail"]),
            contactURL: string(payload["contactURL"]),
            selectedFederalState: federalState,
            startDate: startDate,
            endDate: endDate,
            hasExplicitEndDate: payload["hasExplicitEndDate"] as? Bool ?? (explicitEndDate != nil && endDate > startDate),
            isAllDay: payload["isAllDay"] as? Bool ?? false,
            selectedCategory: optionalString(payload["category"]).flatMap(EventCategory.init(rawValue:)) ?? .other,
            additionalCategories: stringArray(payload["additionalCategories"]).compactMap(EventCategory.init(rawValue:)),
            selectedAudience: optionalString(payload["audience"]).flatMap(EventAudience.init(rawValue:)) ?? .everyone,
            minimumAgeText: integer(payload["minimumAge"]).map(String.init),
            maximumAgeText: integer(payload["maximumAge"]).map(String.init),
            tags: stringArray(payload["tags"]),
            tagInput: "",
            requiresRegistration: participationMode.usesInAppRegistration,
            priceText: decimalString(payload["price"]),
            capacityText: integer(payload["capacity"]).map(String.init) ?? "",
            germanTitle: optionalString(payload["germanTitle"]),
            germanSummary: optionalString(payload["germanSummary"]),
            germanDetails: optionalString(payload["germanDetails"]),
            additionalOccurrences: occurrences,
            participationMode: participationMode,
            externalActionTitle: optionalString(payload["externalActionTitle"]),
            externalActionURL: optionalString(payload["externalActionURL"]),
            priceKind: priceKind,
            maximumPriceText: decimalString(payload["maximumPrice"]),
            priceNote: optionalString(payload["priceNote"]),
            generatedImageURL: optionalString(payload["generatedImageURL"]),
            publicationMode: optionalString(payload["publicationMode"]).flatMap(ContentPublicationMode.init(rawValue:)),
            scheduledAt: date(payload["scheduledAt"])
        )
    }

    private static func appError(from error: Error) -> AppError {
        if error is CancellationError { return .unknown }
        if let appError = error as? AppError { return appError }
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: nsError.code) {
            switch code {
            case .unauthenticated, .permissionDenied:
                return .permissionDenied
            case .notFound:
                return .notFound
            case .invalidArgument, .failedPrecondition, .alreadyExists, .aborted:
                return .validationFailed
            case .cancelled, .deadlineExceeded, .resourceExhausted, .unavailable:
                return .network
            default:
                return .unknown
            }
        }
        switch nsError.code {
        case FirestoreErrorCode.permissionDenied.rawValue: return .permissionDenied
        case FirestoreErrorCode.notFound.rawValue: return .notFound
        case FirestoreErrorCode.unavailable.rawValue, FirestoreErrorCode.deadlineExceeded.rawValue: return .network
        default: return .unknown
        }
    }

    private func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        if let text = value as? String { return ISO8601DateFormatter().date(from: text) }
        return nil
    }

    private func string(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func optionalString(_ value: Any?) -> String? {
        let value = string(value)
        return value.isEmpty ? nil : value
    }

    private func stringArray(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap(optionalString)
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func decimalString(_ value: Any?) -> String {
        guard let value = double(value) else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
