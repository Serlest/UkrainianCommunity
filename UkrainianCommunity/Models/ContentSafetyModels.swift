import Foundation

enum ContentReportTargetType: String, Codable, CaseIterable {
    case news
    case event
    case organization
    case comment

    var title: String {
        switch self {
        case .news:
            AppStrings.Safety.targetNews
        case .event:
            AppStrings.Safety.targetEvent
        case .organization:
            AppStrings.Safety.targetOrganization
        case .comment:
            AppStrings.Safety.targetComment
        }
    }

    var systemImage: String {
        switch self {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .organization:
            "building.2"
        case .comment:
            "text.bubble"
        }
    }
}

enum ContentReportReason: String, Codable, CaseIterable, Identifiable {
    case harassment
    case hate
    case violence
    case sexual
    case spam
    case misinformation
    case privacy
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .harassment:
            AppStrings.Safety.reasonHarassment
        case .hate:
            AppStrings.Safety.reasonHate
        case .violence:
            AppStrings.Safety.reasonViolence
        case .sexual:
            AppStrings.Safety.reasonSexual
        case .spam:
            AppStrings.Safety.reasonSpam
        case .misinformation:
            AppStrings.Safety.reasonMisinformation
        case .privacy:
            AppStrings.Safety.reasonPrivacy
        case .other:
            AppStrings.Safety.reasonOther
        }
    }

    var isUrgent: Bool {
        switch self {
        case .harassment, .hate, .violence, .sexual, .privacy:
            true
        case .spam, .misinformation, .other:
            false
        }
    }
}

struct ContentReportTarget: Identifiable, Equatable {
    let targetType: ContentReportTargetType
    let targetId: String
    let parentType: CommentParentType?
    let parentId: String?
    let title: String
    let authorId: String?

    var id: String {
        [targetType.rawValue, parentType?.rawValue, parentId, targetId]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    static func news(_ post: NewsPost) -> ContentReportTarget {
        ContentReportTarget(
            targetType: .news,
            targetId: post.id,
            parentType: nil,
            parentId: nil,
            title: post.title,
            authorId: post.authorId
        )
    }

    static func event(_ event: Event) -> ContentReportTarget {
        ContentReportTarget(
            targetType: .event,
            targetId: event.id,
            parentType: nil,
            parentId: nil,
            title: event.title,
            authorId: event.authorId
        )
    }

    static func organization(_ organization: Organization) -> ContentReportTarget {
        ContentReportTarget(
            targetType: .organization,
            targetId: organization.id,
            parentType: nil,
            parentId: nil,
            title: organization.name,
            authorId: organization.ownerId ?? organization.submittedByUserId
        )
    }

    static func comment(_ comment: Comment, parentTitle: String) -> ContentReportTarget? {
        guard let parentType = comment.parentType,
              let parentId = comment.parentId else {
            return nil
        }

        return ContentReportTarget(
            targetType: .comment,
            targetId: comment.id,
            parentType: parentType,
            parentId: parentId,
            title: parentTitle,
            authorId: comment.authorId
        )
    }
}

struct ContentReportReceipt: Equatable {
    let reportId: String
    let caseNumber: String
    let accessToken: String
    let submittedAt: Date
    let acknowledgementAt: Date
    let wasDuplicate: Bool
}

struct ContentReportSubmission: Equatable {
    let illegalExplanation: String
    let legalBasis: String?
    let evidence: String?
    let goodFaithConfirmed: Bool
}

enum ContentReportSubmissionError: Error, Equatable {
    case authenticationRequired
    case permissionDenied
    case ownContent
    case targetUnavailable
    case network
    case unknown
}
