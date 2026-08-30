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
    let failureMessage: String?
    let generatedImage: OwnerContentGeneratedImage?

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

    var isVisibleInPlanning: Bool {
        ![.completed, .archived].contains(state)
    }
}
