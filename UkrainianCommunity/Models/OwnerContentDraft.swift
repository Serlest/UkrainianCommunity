import Foundation

enum OwnerContentDraftKind: String, CaseIterable, Codable {
    case news
    case event
}

enum OwnerContentDraftState: String, CaseIterable, Codable {
    case readyForReview
    case needsAttention
    case scheduled
    case publishing
    case failed
    case completed
    case archived
}

enum OwnerContentPlanningSection: String, CaseIterable, Identifiable, Codable {
    case drafts
    case scheduled
    case attention
    case history

    var id: String { rawValue }

    var states: [OwnerContentDraftState] {
        switch self {
        case .drafts:
            [.readyForReview, .publishing]
        case .scheduled:
            [.scheduled]
        case .attention:
            [.needsAttention, .failed]
        case .history:
            [.completed, .archived]
        }
    }

    var usesAscendingScheduleOrder: Bool { self == .scheduled }
}

enum OwnerContentPublicationOutcome: String, Codable {
    case approved
    case pendingReview
    case scheduled
    case archived
    case unresolved
}

struct OwnerContentDraftPageCursor: Equatable {
    let sortDate: Date
    let documentID: String
}

struct OwnerContentDraftPage: Equatable {
    let items: [OwnerContentDraft]
    let nextCursor: OwnerContentDraftPageCursor?
    let hasMore: Bool
}

struct OwnerContentPublicationLease: Equatable, Sendable {
    let draftID: String
    let kind: OwnerContentDraftKind
    let contentID: String
    let leaseID: String
    let expiresAt: Date
    let contentAlreadyExists: Bool
    let existingModerationStatus: ModerationStatus?
    let existingScheduledAt: Date?
}

struct OwnerContentPlanningPublicationCallbacks {
    let begin: @MainActor () async -> OwnerContentPublicationLease?
    let fail: @MainActor (_ message: String) async -> Void
}

struct ContentPlanningPublicationResult: Equatable, Sendable {
    let kind: OwnerContentDraftKind
    let contentID: String
    let scheduledAt: Date?
    let publicationLeaseID: String?

    var isScheduled: Bool { scheduledAt != nil }

    init(
        kind: OwnerContentDraftKind,
        contentID: String,
        scheduledAt: Date?,
        publicationLeaseID: String? = nil
    ) {
        self.kind = kind
        self.contentID = contentID
        self.scheduledAt = scheduledAt
        self.publicationLeaseID = publicationLeaseID
    }
}

struct OwnerContentSourceReference: Codable, Equatable, Identifiable {
    let url: String
    let title: String?
    let isPrimary: Bool
    let checkedAt: Date?

    var id: String { url }
}

struct OwnerContentGeneratedImage: Codable, Equatable {
    let url: String
    let storagePath: String
    let alternativeText: String?
    let credit: String?
}

struct OwnerContentDraft: Identifiable, Equatable {
    let id: String
    let schemaVersion: Int
    let ownerUserID: String
    let kind: OwnerContentDraftKind
    let state: OwnerContentDraftState
    let title: String
    let sourceReferences: [OwnerContentSourceReference]
    let verificationNotes: [String]
    let missingFields: [String]
    let newsDraft: NewsCreateDraft?
    let eventDraft: EventCreateDraft?
    let createdAt: Date
    let updatedAt: Date
    let scheduledAt: Date?
    let completedAt: Date?
    let archivedAt: Date?
    let failureMessage: String?
    let publicationLeaseExpiresAt: Date?
    let generatedImage: OwnerContentGeneratedImage?
    let publishedContentID: String?
    let publishedContentKind: OwnerContentDraftKind?
    let publishedOrganizationID: String?
    let publishedOrganizationName: String?
    let publicationOutcome: OwnerContentPublicationOutcome?

    var requiresAttention: Bool {
        state == .needsAttention || state == .failed || !missingFields.isEmpty
    }

    var attentionMessages: [String] {
        let fields = missingFields
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !fields.isEmpty {
            return fields
        }
        if let failureMessage = failureMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !failureMessage.isEmpty {
            return [failureMessage]
        }
        return requiresAttention ? [AppStrings.ContentPlanning.attentionReasonMissing] : []
    }

    var primarySourceURL: String? {
        sourceReferences.first(where: \OwnerContentSourceReference.isPrimary)?.url
            ?? sourceReferences.first?.url
    }

    var isEditableInPlanning: Bool {
        let hasExpiredPublicationLease = state == .publishing
            && (publicationLeaseExpiresAt?.timeIntervalSinceNow ?? -1) <= 0
        switch kind {
        case .news:
            return newsDraft != nil && (
                [.readyForReview, .needsAttention, .failed].contains(state) || hasExpiredPublicationLease
            )
        case .event:
            return eventDraft != nil && (
                [.readyForReview, .needsAttention, .failed].contains(state) || hasExpiredPublicationLease
            )
        }
    }

    var isHistory: Bool {
        [.completed, .archived].contains(state)
    }

    var historyDate: Date {
        completedAt ?? archivedAt ?? updatedAt
    }

    var planningSection: OwnerContentPlanningSection {
        switch state {
        case .readyForReview, .publishing:
            .drafts
        case .scheduled:
            .scheduled
        case .needsAttention, .failed:
            .attention
        case .completed, .archived:
            .history
        }
    }
}
