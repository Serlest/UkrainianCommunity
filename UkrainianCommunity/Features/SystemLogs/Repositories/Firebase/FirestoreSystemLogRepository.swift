import FirebaseFirestore
import FirebaseFunctions
import Foundation

final class FirestoreSystemLogRepository: SystemLogRepositoryProtocol, SystemLoggingServiceProtocol {
    private let collection: CollectionReference
    private let redactionPolicy: SystemLogRedactionPolicy
    private let functions: Functions

    private var lastFilter: SystemLogFilter = .empty
    private var lastSortOption: SystemLogSortOption = .newestFirst
    private var lastLimit = 50
    private var lastDocument: DocumentSnapshot?

    init(
        database: Firestore = Firestore.firestore(),
        functions: Functions = Functions.functions(region: "europe-west3"),
        redactionPolicy: SystemLogRedactionPolicy = .default
    ) {
        collection = database.collection(SystemLogFirestoreContract.collectionPath)
        self.functions = functions
        self.redactionPolicy = redactionPolicy
    }

    func fetchLogs(
        filter: SystemLogFilter,
        sortOption: SystemLogSortOption,
        limit: Int
    ) async throws -> [SystemLogEntry] {
        lastFilter = filter
        lastSortOption = sortOption
        lastLimit = max(1, limit)
        lastDocument = nil

        return try await fetchPage(
            filter: filter,
            sortOption: sortOption,
            limit: lastLimit,
            after: nil
        )
    }

    func fetchNextPage() async throws -> [SystemLogEntry] {
        guard let lastDocument else { return [] }

        return try await fetchPage(
            filter: lastFilter,
            sortOption: lastSortOption,
            limit: lastLimit,
            after: lastDocument
        )
    }

    func fetchLog(id: String) async throws -> SystemLogEntry? {
        let snapshot = try await collection.document(id).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return FirestoreSystemLogDTO(id: snapshot.documentID, data: data).entry
    }

    func createLog(from draft: SystemLogDraft) async throws -> SystemLogEntry {
        let redactedDraft = redactionPolicy.redactedDraft(from: draft)

        if redactedDraft.category == .diagnostics {
            return try await createServerDiagnostic(from: redactedDraft)
        }

        let id = UUID().uuidString
        let createdAt = Date()
        let entry = SystemLogEntry(id: id, createdAt: createdAt, draft: redactedDraft)
        let dto = FirestoreSystemLogDTO(entry: entry)
        var data = dto.data
        data[SystemLogFirestoreContract.Field.createdAt.rawValue] = FieldValue.serverTimestamp()

        try await collection.document(id).setData(data)
        return entry
    }

    func markReviewed(logID: String, reviewedByUserId: String) async throws {
        let field = SystemLogFirestoreContract.Field.self
        let trimmedReviewerID = reviewedByUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReviewerID.isEmpty else { return }

        try await collection.document(logID).updateData([
            field.isReviewed.rawValue: true,
            field.reviewedAt.rawValue: FieldValue.serverTimestamp(),
            field.reviewedByUserId.rawValue: trimmedReviewerID
        ])
    }

    func log(_ draft: SystemLogDraft) async throws {
        _ = try await createLog(from: draft)
    }

    func clearAllLogs() async throws -> Int {
        let callable: Callable<EmptySystemLogRequest, ClearSystemLogsFunctionResponse> =
            functions.httpsCallable("clearSystemLogs")
        return try await callable.call(EmptySystemLogRequest()).deletedCount
    }

    func deleteLog(id: String) async throws {
        let callable: Callable<DeleteSystemLogRequest, ClearSystemLogsFunctionResponse> =
            functions.httpsCallable("deleteSystemLog")
        _ = try await callable.call(DeleteSystemLogRequest(logId: id))
    }

    private func fetchPage(
        filter: SystemLogFilter,
        sortOption: SystemLogSortOption,
        limit: Int,
        after cursor: DocumentSnapshot?
    ) async throws -> [SystemLogEntry] {
        var query = makeQuery(filter: filter, sortOption: sortOption)
            .limit(to: max(1, limit))

        if let cursor {
            query = query.start(afterDocument: cursor)
        }

        let snapshot = try await query.getDocuments()
        lastDocument = snapshot.documents.last

        return snapshot.documents.map { document in
            FirestoreSystemLogDTO(id: document.documentID, data: document.data()).entry
        }
    }

    private func makeQuery(filter: SystemLogFilter, sortOption: SystemLogSortOption) -> Query {
        let field = SystemLogFirestoreContract.Field.self
        var query: Query = collection

        query = apply(filter.categories.map(\.rawValue), field: field.category, to: query)
        query = apply(filter.severities.map(\.rawValue), field: field.severity, to: query)
        query = apply(filter.eventTypes.map(\.rawValue), field: field.eventType, to: query)
        query = apply(filter.actorRoles.map(\.rawValue), field: field.actorRole, to: query)
        query = apply(filter.targetTypes.map(\.rawValue), field: field.targetType, to: query)
        query = apply(filter.outcomes.map(\.rawValue), field: field.outcome, to: query)

        if let actorUserId = filter.actorUserId {
            query = query.whereField(field.actorUserId.rawValue, isEqualTo: actorUserId)
        }

        if let targetId = filter.targetId {
            query = query.whereField(field.targetId.rawValue, isEqualTo: targetId)
        }

        if let organizationId = filter.organizationId {
            query = query.whereField(field.organizationId.rawValue, isEqualTo: organizationId)
        }

        if let isReviewed = filter.isReviewed {
            query = query.whereField(field.isReviewed.rawValue, isEqualTo: isReviewed)
        }

        if let startDate = filter.startDate {
            query = query.whereField(field.createdAt.rawValue, isGreaterThanOrEqualTo: Timestamp(date: startDate))
        }

        if let endDate = filter.endDate {
            query = query.whereField(field.createdAt.rawValue, isLessThanOrEqualTo: Timestamp(date: endDate))
        }

        if let isAppAdminReadable = filter.isAppAdminReadable {
            query = query.whereField(field.isAppAdminReadable.rawValue, isEqualTo: isAppAdminReadable)
        }

        // Intentionally not applying searchText in Firestore. Full-text search can be handled
        // client-side on loaded pages or with search tokens in a later pass.
        return applySort(sortOption, to: query)
    }

    private func apply(_ values: [String], field: SystemLogFirestoreContract.Field, to query: Query) -> Query {
        let uniqueValues = Array(Set(values)).sorted()
        guard !uniqueValues.isEmpty else { return query }

        if uniqueValues.count == 1, let value = uniqueValues.first {
            return query.whereField(field.rawValue, isEqualTo: value)
        }

        return query.whereField(field.rawValue, in: Array(uniqueValues.prefix(10)))
    }

    private func applySort(_ sortOption: SystemLogSortOption, to query: Query) -> Query {
        let field = SystemLogFirestoreContract.Field.self

        switch sortOption {
        case .severityHighToLow:
            return query
                .order(by: field.severityRank.rawValue, descending: true)
                .order(by: field.createdAt.rawValue, descending: true)
        case .severityLowToHigh:
            return query
                .order(by: field.severityRank.rawValue, descending: false)
                .order(by: field.createdAt.rawValue, descending: true)
        case .oldestFirst:
            return query.order(by: field.createdAt.rawValue, descending: false)
        case .category:
            return query
                .order(by: field.category.rawValue, descending: false)
                .order(by: field.createdAt.rawValue, descending: true)
        case .newestFirst:
            return query.order(by: field.createdAt.rawValue, descending: true)
        }
    }

    private func createServerDiagnostic(from draft: SystemLogDraft) async throws -> SystemLogEntry {
        let request = SystemDiagnosticFunctionRequest(draft: draft)
        let callable: Callable<SystemDiagnosticFunctionRequest, SystemDiagnosticFunctionResponse> =
            functions.httpsCallable("writeClientDiagnostic")
        let response = try await callable.call(request)
        let createdAt = ISO8601DateFormatter().date(from: response.createdAt) ?? Date()
        return SystemLogEntry(
            id: response.id,
            createdAt: createdAt,
            draft: draft
        )
    }
}

private struct SystemDiagnosticFunctionRequest: Encodable {
    let eventType: String
    let severity: String
    let targetType: String
    let targetId: String?
    let targetTitle: String?
    let organizationId: String?
    let organizationName: String?
    let summary: String
    let technicalMessage: String?
    let errorCode: String?
    let moduleName: String?
    let screenName: String?
    let operationName: String?
    let appVersion: String?
    let osVersion: String?
    let deviceModel: String?
    let metadata: [String: String]
    let correlationId: String?

    init(draft: SystemLogDraft) {
        eventType = draft.eventType.rawValue
        severity = draft.severity.rawValue
        targetType = draft.targetType.rawValue
        targetId = draft.targetId
        targetTitle = draft.targetTitle
        organizationId = draft.organizationId
        organizationName = draft.organizationName
        summary = draft.summary
        technicalMessage = draft.technicalMessage
        errorCode = draft.errorCode
        moduleName = draft.moduleName
        screenName = draft.screenName
        operationName = draft.operationName
        appVersion = draft.appVersion
        osVersion = draft.osVersion
        deviceModel = draft.deviceModel
        metadata = draft.metadata
        correlationId = draft.correlationId
    }
}

private struct SystemDiagnosticFunctionResponse: Decodable {
    let id: String
    let createdAt: String
}

private struct EmptySystemLogRequest: Encodable {}

private struct DeleteSystemLogRequest: Encodable {
    let logId: String
}

private struct ClearSystemLogsFunctionResponse: Decodable {
    let deletedCount: Int
}
