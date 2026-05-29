import Foundation

enum GuideReviewState: String, Codable, CaseIterable, Identifiable {
    case current
    case dueSoon
    case overdue
    case archived

    var id: String { rawValue }
}

extension GuideArticle {
    var isReviewOverdue: Bool {
        reviewState == .overdue
    }

    var effectiveNextReviewAt: Date? {
        if let nextReviewAt {
            return nextReviewAt
        }

        guard let reviewInterval else { return nil }
        let baseDate = lastReviewedAt ?? publishedAt
        guard let baseDate else { return nil }

        return Calendar.current.date(byAdding: .month, value: reviewInterval.months, to: baseDate)
    }

    var reviewState: GuideReviewState {
        reviewState(relativeTo: Date())
    }

    func reviewState(relativeTo date: Date) -> GuideReviewState {
        if archivedAt != nil || status == .archived {
            return .archived
        }

        if status == .needsReview {
            return .overdue
        }

        guard let effectiveNextReviewAt else {
            return .current
        }

        if effectiveNextReviewAt < date {
            return .overdue
        }

        let dueSoonCutoff = Calendar.current.date(byAdding: .day, value: 30, to: date) ?? date
        if effectiveNextReviewAt <= dueSoonCutoff {
            return .dueSoon
        }

        return .current
    }
}
