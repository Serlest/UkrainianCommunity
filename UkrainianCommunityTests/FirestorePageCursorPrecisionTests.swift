import Foundation
import FirebaseFirestore
import Testing
@testable import UkrainianCommunity

@MainActor
struct FirestorePageCursorPrecisionTests {
    @Test func everyCursorPreservesTheOriginalTimestampAndDocumentID() throws {
        // Includes both rounding directions from F01, whole-second boundaries,
        // and a pre-epoch timestamp. No Firebase app or network is needed.
        for seconds in [Int64(-1), 0, 1_788_600_000] {
            for nanoseconds in [Int32(0), 1_000, 111_111_000, 123_456_000, 999_999_000] {
                let original = Timestamp(seconds: seconds, nanoseconds: nanoseconds)
                for kind in CursorKind.allCases {
                    let values = kind.values(timestamp: original, id: "boundary-document")
                    let restored = try #require(values.first as? Timestamp)
                    #expect(restored.seconds == seconds)
                    #expect(restored.nanoseconds == nanoseconds)
                    #expect(values.count == 2)
                    #expect(values[1] as? String == "boundary-document")
                }
            }
        }
    }

    @Test func equalFractionalTimestampsCrossEveryPageWithoutSkipsOrRepeats() throws {
        for nanoseconds in [Int32(111_111_000), 123_456_000] {
            let timestamp = Timestamp(seconds: 1_788_600_000, nanoseconds: nanoseconds)
            let rows = ["a", "b", "c", "d", "e"].map { Row(timestamp: timestamp, id: $0) }
            for kind in CursorKind.allCases {
                for pageSize in [1, 2, 3] {
                    let ids = try paginate(rows, kind: kind, pageSize: pageSize)
                    #expect(ids == (kind.descending ? ["e", "d", "c", "b", "a"] : ["a", "b", "c", "d", "e"]))
                }
            }
        }
    }

    @Test func adjacentTimestampAndSecondBoundariesUseTimeBeforeDocumentID() throws {
        let rows = [
            Row(timestamp: Timestamp(seconds: 1_788_599_999, nanoseconds: 999_999_000), id: "z"),
            Row(timestamp: Timestamp(seconds: 1_788_600_000, nanoseconds: 0), id: "y"),
            Row(timestamp: Timestamp(seconds: 1_788_600_000, nanoseconds: 111_110_000), id: "x"),
            Row(timestamp: Timestamp(seconds: 1_788_600_000, nanoseconds: 111_111_000), id: "b"),
            Row(timestamp: Timestamp(seconds: 1_788_600_000, nanoseconds: 111_111_000), id: "c"),
            Row(timestamp: Timestamp(seconds: 1_788_600_000, nanoseconds: 111_112_000), id: "a"),
        ]
        for kind in CursorKind.allCases {
            for pageSize in [1, 2, 3] {
                let ids = try paginate(rows, kind: kind, pageSize: pageSize)
                #expect(ids == (kind.descending ? ["a", "c", "b", "x", "y", "z"] : ["z", "y", "x", "b", "c", "a"]))
            }
        }
    }

    @Test func legacyDateInitializersRemainUsable() throws {
        let date = Date(timeIntervalSince1970: 1_788_600_000.25)
        let expected = Timestamp(date: date)
        let cursors: [[Any]] = [
            NewsPageCursor(publishedAt: date, documentID: "legacy").firestoreStartAfterValues,
            EventPageCursor(endDate: date, documentID: "legacy").firestoreStartAfterValues,
            OrganizationPageCursor(createdAt: date, documentID: "legacy").firestoreStartAfterValues,
            OrganizationSubscriberCursor(followedAt: date, documentID: "legacy").firestoreStartAfterValues,
            OwnerContentDraftPageCursor(sortDate: date, documentID: "legacy").firestoreStartAfterValues,
        ]
        for values in cursors {
            let timestamp = try #require(values.first as? Timestamp)
            #expect(timestamp.seconds == expected.seconds)
            #expect(timestamp.nanoseconds == expected.nanoseconds)
            #expect(values[1] as? String == "legacy")
        }
    }

    // These tests exercise the exact cursor values consumed by the production
    // start(after:) calls. The tuple comparison models Firestore ordering;
    // a real emulator query remains a separate integration verification gate.
    private func paginate(_ rows: [Row], kind: CursorKind, pageSize: Int) throws -> [String] {
        let ordered = rows.sorted { kind.descending ? precedes($1, $0) : precedes($0, $1) }
        var boundary: Row?
        var result: [String] = []
        for _ in 0...rows.count {
            let remaining = ordered.filter { row in
                guard let boundary else { return true }
                return kind.descending ? precedes(row, boundary) : precedes(boundary, row)
            }
            // The extra document determines hasMore, but the cursor belongs to
            // the last returned document, never the lookahead document.
            let fetched = Array(remaining.prefix(pageSize + 1))
            let page = Array(fetched.prefix(pageSize))
            guard let last = page.last else { break }
            result.append(contentsOf: page.map(\.id))
            let values = kind.values(timestamp: last.timestamp, id: last.id)
            boundary = Row(
                timestamp: try #require(values.first as? Timestamp),
                id: try #require(values.last as? String)
            )
            if fetched.count <= pageSize { break }
        }
        #expect(result.count == rows.count)
        #expect(Set(result).count == rows.count)
        return result
    }

    private func precedes(_ lhs: Row, _ rhs: Row) -> Bool {
        if lhs.timestamp.seconds != rhs.timestamp.seconds {
            return lhs.timestamp.seconds < rhs.timestamp.seconds
        }
        if lhs.timestamp.nanoseconds != rhs.timestamp.nanoseconds {
            return lhs.timestamp.nanoseconds < rhs.timestamp.nanoseconds
        }
        return lhs.id < rhs.id
    }

    private struct Row {
        let timestamp: Timestamp
        let id: String
    }

    @MainActor
    private enum CursorKind: CaseIterable {
        case news, event, organization, subscriber, scheduledDraft, recentDraft

        var descending: Bool { self != .event && self != .scheduledDraft }

        func values(timestamp: Timestamp, id: String) -> [Any] {
            switch self {
            case .news:
                NewsPageCursor(publishedAt: timestamp, documentID: id).firestoreStartAfterValues
            case .event:
                EventPageCursor(endDate: timestamp, documentID: id).firestoreStartAfterValues
            case .organization:
                OrganizationPageCursor(createdAt: timestamp, documentID: id).firestoreStartAfterValues
            case .subscriber:
                OrganizationSubscriberCursor(followedAt: timestamp, documentID: id).firestoreStartAfterValues
            case .scheduledDraft, .recentDraft:
                OwnerContentDraftPageCursor(sortDate: timestamp, documentID: id).firestoreStartAfterValues
            }
        }
    }
}
