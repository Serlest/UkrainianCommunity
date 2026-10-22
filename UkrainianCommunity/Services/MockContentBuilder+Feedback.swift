import Foundation

extension MockContentBuilder {
    nonisolated static func feedbackFixtures() -> [FeedbackItem] {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.environment["UITestFeedbackInbox"] == "1" else { return [] }
        return [FeedbackItem(
            id: "directory-feedback-fixture", type: .report,
            subject: "Довідник · неточність · registration", message: "Feedback navigation fixture",
            status: .open, createdAt: .now, updatedAt: .now,
            userId: currentUser().id, userDisplayName: "Olena", ownerReply: nil,
            repliedAt: nil, repliedByUserId: nil, lastMessageText: nil,
            lastMessageAt: nil, lastMessageByUserId: nil, lastMessageByRole: nil,
            unreadForOwner: false, unreadForUser: false,
            reportContext: ProcessInfo.processInfo.environment["UITestFeedbackReportContext"] == "1" ? .init(
                targetType: .news, targetId: "news-1", parentType: nil, parentId: nil, targetAuthorId: nil,
                targetTitle: newsPosts()[0].title, targetExcerpt: "Full reported article context", reason: .spam, isUrgent: false,
                slaDueAt: .now.addingTimeInterval(86_400)) : nil
        )]
    }
}
