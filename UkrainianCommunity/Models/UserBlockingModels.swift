import Foundation

nonisolated struct BlockedUser: Identifiable, Equatable {
    let targetUserId: String
    let displayName: String
    let avatarURL: URL?
    let blockedAt: Date
    let updatedAt: Date

    var id: String { targetUserId }
}

nonisolated struct UserBlockMutationReceipt: Equatable {
    let targetUserId: String
    let isBlocked: Bool
    let displayName: String
    let avatarURL: URL?
    let updatedAt: Date
}

struct UserBlockTarget: Identifiable, Equatable {
    let userId: String
    let contextTitle: String

    var id: String { userId }

    static func news(_ post: NewsPost) -> UserBlockTarget? {
        make(userId: post.authorId, contextTitle: post.title)
    }

    static func event(_ event: Event) -> UserBlockTarget? {
        make(userId: event.authorId, contextTitle: event.title)
    }

    static func comment(_ comment: Comment) -> UserBlockTarget? {
        make(userId: comment.authorId, contextTitle: comment.authorName)
    }

    private static func make(userId: String?, contextTitle: String) -> UserBlockTarget? {
        guard let userId = userId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userId.isEmpty else {
            return nil
        }
        return UserBlockTarget(userId: userId, contextTitle: contextTitle)
    }
}

struct ContentVisibilityPolicy: Equatable {
    let blockedUserIDs: Set<String>
    let blockedOrganizationIDs: Set<String>

    init(blockedUserIDs: Set<String> = [], blockedOrganizationIDs: Set<String> = []) {
        self.blockedUserIDs = blockedUserIDs
        self.blockedOrganizationIDs = blockedOrganizationIDs
    }

    func allows(authorID: String?) -> Bool {
        guard let authorID else { return true }
        return !blockedUserIDs.contains(authorID)
    }

    func visibleComments(_ comments: [Comment]) -> [Comment] {
        comments.filter { allows(authorID: $0.authorId) }
    }

    func visibleNews(_ posts: [NewsPost]) -> [NewsPost] {
        posts.compactMap { post in
            guard allows(authorID: post.authorId), allows(organizationID: post.source.organizationId) else { return nil }
            var visiblePost = post
            visiblePost.comments = visibleComments(post.comments)
            return visiblePost
        }
    }

    func visibleEvents(_ events: [Event]) -> [Event] {
        events.compactMap { event in
            guard allows(authorID: event.authorId), allows(organizationID: event.source.organizationId) else { return nil }
            var visibleEvent = event
            visibleEvent.comments = visibleComments(event.comments)
            return visibleEvent
        }
    }

    func visibleOrganizations(_ organizations: [Organization]) -> [Organization] {
        organizations.filter {
            allows(authorID: $0.ownerId ?? $0.submittedByUserId) && allows(organizationID: $0.id)
        }
    }

    func allows(organizationID: String?) -> Bool {
        organizationID.map { !blockedOrganizationIDs.contains($0) } ?? true
    }
}

nonisolated enum UserBlockingError: Error, Equatable {
    case authenticationRequired
    case permissionDenied
    case ownAccount
    case targetUnavailable
    case network
    case malformedResponse
    case unknown
}
