import FirebaseFirestore
import FirebaseFunctions
import Foundation

struct FirestoreOwnerContentDraftRepository: OwnerContentDraftRepository {
    private let database = Firestore.firestore()
    private let functions = Functions.functions(region: "europe-west3")

    func fetchDrafts(userID: String, limit: Int) async throws -> [OwnerContentDraft] {
        let snapshot = try await collection(userID: userID)
            .order(by: "updatedAt", descending: true)
            .limit(to: max(1, limit))
            .getDocuments()
        return snapshot.documents.compactMap(makeDraft).filter(\.isVisibleInPlanning)
    }

    func listenDrafts(
        userID: String,
        limit: Int,
        onChange: @escaping @MainActor ([OwnerContentDraft]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener {
        let registration = collection(userID: userID)
            .order(by: "updatedAt", descending: true)
            .limit(to: max(1, limit))
            .addSnapshotListener { snapshot, error in
                if let error {
                    Task { @MainActor in onError(Self.appError(from: error)) }
                    return
                }
                let drafts = snapshot?.documents.compactMap(makeDraft).filter(\.isVisibleInPlanning) ?? []
                Task { @MainActor in onChange(drafts) }
            }
        return FirebaseRealtimeListener(registration)
    }

    func markCompleted(userID: String, draftID: String) async throws {
        try await collection(userID: userID).document(draftID).updateData([
            "state": OwnerContentDraftState.completed.rawValue,
            "completedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func archive(userID: String, draftID: String) async throws {
        try await collection(userID: userID).document(draftID).updateData([
            "state": OwnerContentDraftState.archived.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func delete(userID: String, draftID: String) async throws {
        struct Request: Encodable { let draftId: String }
        struct Response: Decodable { let deleted: Bool }

        let callable: Callable<Request, Response> = functions.httpsCallable("deleteOwnerContentDraft")
        _ = try await callable.call(Request(draftId: draftID))
    }

    private func collection(userID: String) -> CollectionReference {
        database.collection("users").document(userID).collection("contentPlanningDrafts")
    }

    private func makeDraft(from document: QueryDocumentSnapshot) -> OwnerContentDraft? {
        let data = document.data()
        guard let kindRaw = data["kind"] as? String,
              let kind = OwnerContentDraftKind(rawValue: kindRaw),
              let stateRaw = data["state"] as? String,
              let state = OwnerContentDraftState(rawValue: stateRaw),
              let payload = data["payload"] as? [String: Any] else {
            return nil
        }

        let ownerUserID = document.reference.parent.parent?.documentID ?? string(data["ownerUserId"])
        let sources = (data["sources"] as? [[String: Any]] ?? []).compactMap(makeSource)
        let newsDraft = kind == .news ? makeNewsDraft(payload, updatedAt: date(data["updatedAt"]) ?? .now) : nil
        let eventDraft = kind == .event ? makeEventDraft(payload, updatedAt: date(data["updatedAt"]) ?? .now) : nil
        guard newsDraft != nil || eventDraft != nil else { return nil }

        return OwnerContentDraft(
            id: document.documentID,
            schemaVersion: integer(data["schemaVersion"]) ?? 1,
            ownerUserID: ownerUserID,
            kind: kind,
            state: state,
            title: string(data["title"]),
            sourceReferences: sources,
            verificationNotes: stringArray(data["verificationNotes"]),
            missingFields: stringArray(data["missingFields"]),
            newsDraft: newsDraft,
            eventDraft: eventDraft,
            createdAt: date(data["createdAt"]) ?? .now,
            updatedAt: date(data["updatedAt"]) ?? .now,
            scheduledAt: date(data["scheduledAt"]),
            completedAt: date(data["completedAt"]),
            failureMessage: optionalString(data["failureMessage"]),
            generatedImage: makeGeneratedImage(data["generatedImage"])
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
        let nsError = error as NSError
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
