import FirebaseFirestore
import Foundation

final class FirestoreSystemLogRepository: SystemLogRepositoryProtocol, SystemLoggingServiceProtocol {
    private let collection: CollectionReference
    private let redactionPolicy: SystemLogRedactionPolicy

    private var lastFilter: SystemLogFilter = .empty
    private var lastSortOption: SystemLogSortOption = .newestFirst
    private var lastLimit = 50
    private var lastDocument: DocumentSnapshot?

    init(
        database: Firestore = Firestore.firestore(),
        redactionPolicy: SystemLogRedactionPolicy = .default
    ) {
        collection = database.collection(SystemLogFirestoreContract.collectionPath)
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
        let id = UUID().uuidString
        let createdAt = Date()
        let redactedDraft = redactionPolicy.redactedDraft(from: draft)
        let entry = SystemLogEntry(id: id, createdAt: createdAt, draft: redactedDraft)
        let dto = FirestoreSystemLogDTO(entry: entry)

        try await collection.document(id).setData(dto.data)
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
        query = apply(filter.outcomes.map(\.rawValue), field: field.outcome, to: query)

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
}
