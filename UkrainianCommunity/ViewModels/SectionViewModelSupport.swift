import Foundation

nonisolated let defaultRefreshStaleInterval: TimeInterval = 300
nonisolated let organizationRefreshStaleInterval: TimeInterval = 600
nonisolated let publicFeedPageSize = 30

extension Array where Element == NewsPost {
    func deduplicatedNewsByID() -> [NewsPost] {
        var seenIDs = Set<String>()
        return filter { post in
            seenIDs.insert(post.id).inserted
        }
    }
}

extension Array where Element == Organization {
    func deduplicatedOrganizationsByID() -> [Organization] {
        var seenIDs = Set<String>()
        return filter { organization in
            seenIDs.insert(organization.id).inserted
        }
    }

    mutating func upsertOrganizationByID(_ organization: Organization) {
        if let index = firstIndex(where: { $0.id == organization.id }) {
            self[index] = organization
        } else {
            insert(organization, at: 0)
        }
    }
}

extension Array where Element == Event {
    func deduplicatedEventsByID() -> [Event] {
        var seenIDs = Set<String>()
        return filter { event in
            seenIDs.insert(event.id).inserted
        }
    }
}

extension Array where Element == Comment {
    func deduplicatedCommentsByID() -> [Comment] {
        var seenIDs = Set<String>()
        return filter { comment in
            seenIDs.insert(comment.id).inserted
        }
    }

    mutating func upsertCommentByID(_ comment: Comment) {
        if let index = firstIndex(where: { $0.id == comment.id }) {
            self[index] = comment
        } else {
            append(comment)
        }
    }
}
