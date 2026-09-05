import FirebaseFirestore

extension PageCursorTimestamp {
    init(_ timestamp: Timestamp) {
        self.init(seconds: timestamp.seconds, nanoseconds: timestamp.nanoseconds)
    }

    var firestoreTimestamp: Timestamp {
        Timestamp(seconds: seconds, nanoseconds: nanoseconds)
    }
}

extension NewsPageCursor {
    init(publishedAt: Timestamp, documentID: String) {
        self.init(
            publishedAt: publishedAt.dateValue(),
            documentID: documentID,
            exactTimestamp: PageCursorTimestamp(publishedAt)
        )
    }

    var firestoreStartAfterValues: [Any] {
        [exactTimestamp?.firestoreTimestamp ?? Timestamp(date: publishedAt), documentID]
    }
}

extension EventPageCursor {
    init(endDate: Timestamp, documentID: String) {
        self.init(
            endDate: endDate.dateValue(),
            documentID: documentID,
            exactTimestamp: PageCursorTimestamp(endDate)
        )
    }

    var firestoreStartAfterValues: [Any] {
        [exactTimestamp?.firestoreTimestamp ?? Timestamp(date: endDate), documentID]
    }
}

extension OrganizationPageCursor {
    init(createdAt: Timestamp, documentID: String) {
        self.init(
            createdAt: createdAt.dateValue(),
            documentID: documentID,
            exactTimestamp: PageCursorTimestamp(createdAt)
        )
    }

    var firestoreStartAfterValues: [Any] {
        [exactTimestamp?.firestoreTimestamp ?? Timestamp(date: createdAt), documentID]
    }
}

extension OrganizationSubscriberCursor {
    init(followedAt: Timestamp, documentID: String) {
        self.init(
            followedAt: followedAt.dateValue(),
            documentID: documentID,
            exactTimestamp: PageCursorTimestamp(followedAt)
        )
    }

    var firestoreStartAfterValues: [Any] {
        [exactTimestamp?.firestoreTimestamp ?? Timestamp(date: followedAt), documentID]
    }
}

extension OwnerContentDraftPageCursor {
    init(sortDate: Timestamp, documentID: String) {
        self.init(
            sortDate: sortDate.dateValue(),
            documentID: documentID,
            exactTimestamp: PageCursorTimestamp(sortDate)
        )
    }

    var firestoreStartAfterValues: [Any] {
        [exactTimestamp?.firestoreTimestamp ?? Timestamp(date: sortDate), documentID]
    }
}
