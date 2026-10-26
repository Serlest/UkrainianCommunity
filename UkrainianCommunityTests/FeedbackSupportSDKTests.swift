import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
@testable import UkrainianCommunity

/// Actual client repository + Auth SDK + Firestore Rules, fixed local transport only.
@MainActor final class FeedbackSupportSDKTests: XCTestCase {
    private func signIn(_ suffix: String) async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Requires disposable feedback emulators") }
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit",
              Firestore.firestore().settings.host == "127.0.0.1:28080", !Firestore.firestore().settings.isSSLEnabled else {
            throw NSError(domain: "RefusingNonLocalFeedbackAudit", code: 1)
        }
        try? Auth.auth().signOut()
        let result = try await Auth.auth().signIn(withEmail: "feedback-audit-\(suffix)@uac.test", password: "Emulator-Only-2026!")
        XCTAssertEqual(result.user.uid, "feedback-audit-\(suffix)")
    }

    func testSubmissionRetryDoesNotDuplicateOrOverwriteManagerReply() async throws {
        try await signIn("reporter")
        defer { try? Auth.auth().signOut() }
        let repository = FirestoreFeedbackRepository()
        let id = "feedback-audit-" + UUID().uuidString
        let time = Date()
        let item = FeedbackItem(id: id, type: .question, subject: "Directory · article identity", message: "Complete original request",
                                status: .open, createdAt: time, updatedAt: time, userId: "feedback-audit-reporter", userDisplayName: "Reporter",
                                ownerReply: nil, repliedAt: nil, repliedByUserId: nil, lastMessageText: nil, lastMessageAt: nil,
                                lastMessageByUserId: nil, lastMessageByRole: nil, unreadForOwner: true, unreadForUser: false)
        try await repository.submitFeedback(item)
        try await repository.submitFeedback(item) // Lost initial response, same reviewed submission.
        let ref = Firestore.firestore().document("feedback/\(id)")
        let initial = try await ref.getDocument(source: .server)
        XCTAssertEqual(initial.get("message") as? String, item.message)
        XCTAssertEqual(initial.get("subject") as? String, item.subject)
        let originalDate = try XCTUnwrap(initial.get("createdAt") as? Timestamp)
        try await signIn("manager")
        let operation = FeedbackOperationAttempt(id: UUID().uuidString, feedbackID: id, kind: .ownerReply,
            text: "Verified response from support", actorID: "feedback-audit-manager", actorDisplayName: "Support", createdAt: Date())
        try await repository.performFeedbackOperation(operation)
        try await repository.performFeedbackOperation(operation) // Idempotent command replay.
        try await signIn("reporter")
        let notices = try await waitForNotices(sourceID: id, atLeast: 1)
        XCTAssertEqual(notices.documents.count, 1)
        XCTAssertEqual(notices.documents[0].get("recipientUserId") as? String, "feedback-audit-reporter")
        XCTAssertEqual(notices.documents[0].get("actionTargetId") as? String, id)
        try await repository.submitFeedback(item) // Must not reset answered/unread flags.
        let saved = try await ref.getDocument(source: .server)
        XCTAssertEqual(saved.get("status") as? String, "answered")
        XCTAssertEqual(saved.get("ownerReply") as? String, operation.text)
        XCTAssertEqual(saved.get("createdAt") as? Timestamp, originalDate)
        XCTAssertEqual(saved.get("unreadForUser") as? Bool, true)
        let messages = try await ref.collection("messages").getDocuments(source: .server)
        XCTAssertEqual(messages.documents.count, 1)
        XCTAssertEqual(messages.documents[0].get("text") as? String, operation.text)
        try await repository.acknowledgeFeedbackReadByUser(id: id, userID: "feedback-audit-reporter")
        let acknowledged = try await ref.getDocument(source: .server)
        XCTAssertEqual(acknowledged.get("unreadForUser") as? Bool, false)
        try await signIn("other")
        let otherNotices = try await Firestore.firestore().collection("users/feedback-audit-other/notificationInbox").whereField("sourceId", isEqualTo: id).getDocuments(source: .server)
        XCTAssertTrue(otherNotices.isEmpty)
        do { _ = try await repository.fetchFeedback(id: id); XCTFail("Foreign case read must be denied") } catch {}
    }

    func testMessagePaginationReadsAll205TiedTimestampsWithoutDuplicates() async throws {
        try await signIn("reporter")
        defer { try? Auth.auth().signOut() }
        let repository = FirestoreFeedbackRepository()
        let id = "feedback-audit-pages-" + UUID().uuidString
        let time = Date()
        let item = FeedbackItem(id: id, type: .question, subject: "Disposable pagination", message: "Pagination fixture",
            status: .open, createdAt: time, updatedAt: time, userId: "feedback-audit-reporter", userDisplayName: "Reporter",
            ownerReply: nil, repliedAt: nil, repliedByUserId: nil, lastMessageText: nil, lastMessageAt: nil,
            lastMessageByUserId: nil, lastMessageByRole: nil, unreadForOwner: false, unreadForUser: false)
        try await repository.submitFeedback(item)
        // Seed historical system messages only in the already verified loopback demo.
        // The actual paginated reads below use the signed-in client and deployed local Rules.
        let base = "projects/demo-uac-release-audit/databases/(default)/documents/feedback/" + id + "/messages/"
        let writes = (0..<205).map { index -> [String: Any] in
            let messageID = String(format: "history-%03d", index)
            return ["update": ["name": base + messageID, "fields": [
                "id": ["stringValue": messageID], "text": ["stringValue": "History \(index)"],
                "senderRole": ["stringValue": "system"], "isSystem": ["booleanValue": true],
                "createdAt": ["timestampValue": "2026-10-20T12:00:00.123456Z"]]]]
        }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:28080/v1/projects/demo-uac-release-audit/databases/(default)/documents:commit")!)
        request.httpMethod = "POST"; request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["writes": writes])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let first = try await repository.fetchFeedbackMessagesPage(feedback: item, after: nil, limit: 100)
        let second = try await repository.fetchFeedbackMessagesPage(feedback: item, after: first.nextCursor, limit: 100)
        let third = try await repository.fetchFeedbackMessagesPage(feedback: item, after: second.nextCursor, limit: 100)
        XCTAssertEqual([first.items.count, second.items.count, third.items.count], [100, 100, 5])
        XCTAssertTrue(first.hasMore); XCTAssertTrue(second.hasMore); XCTAssertFalse(third.hasMore)
        XCTAssertEqual(Set((first.items + second.items + third.items).map(\.id)).count, 205)
        XCTAssertEqual(first.items.last?.id, "history-204")
        XCTAssertEqual(third.items.first?.id, "history-000")
    }

    func testReportDecisionAppealAndSanitizedAuthorStatementThroughActualClient() async throws {
        try await signIn("reporter")
        defer { try? Auth.auth().signOut() }
        let repository = FirestoreFeedbackRepository()
        let targetID = try await prepareReportTarget()
        let receipt = try await CloudContentSafetyRepository().submitReport(
            target: .init(targetType: .news, targetId: targetID, parentType: nil, parentId: nil,
                          title: "Feedback isolated target", authorId: "feedback-audit-other"),
            reason: .privacy, submission: .init(illegalExplanation: "Specific facts requiring a human review of this isolated target.",
                legalBasis: nil, evidence: "Synthetic evidence; must not appear in author statement", goodFaithConfirmed: true))
        let own = try await repository.fetchFeedback(id: receipt.reportId)
        XCTAssertEqual(own.dsaCase?.caseNumber, receipt.caseNumber)
        XCTAssertEqual(own.reportContext?.targetId, targetID)
        try await signIn("manager")
        let current = try await repository.fetchFeedback(id: receipt.reportId)
        let decision = DsaDecisionFunctionRequest(reportId: current.id, outcome: "noAction",
            factsAndCircumstances: "Human reviewer verified the facts and circumstances of this isolated target.", legalBasis: nil,
            termsBasis: "Synthetic audit review", territorialScope: "Austria", duration: "Permanent",
            redressInformation: "Internal appeal", humanReviewConfirmed: true,
            operationId: UUID().uuidString, expectedRevision: current.revision, revisionFormat: "exact", principalId: "feedback-audit-manager")
        try await repository.decideDsaCase(decision)
        try await repository.decideDsaCase(decision)
        try await signIn("other")
        let statement = try await CloudFunctionsClient.shared.getMyDsaStatement(reportID: current.id)
        XCTAssertEqual(statement.sourceId, targetID)
        XCTAssertEqual(statement.decision?.outcome, "noAction")
        let authorNotices = try await waitForNotices(sourceID: current.id, atLeast: 1)
        XCTAssertEqual(authorNotices.documents.count, 1)
        XCTAssertEqual(authorNotices.documents[0].get("actionTargetId") as? String, current.id)
        try await signIn("reporter")
        let decided = try await repository.fetchFeedback(id: current.id)
        XCTAssertEqual(decided.status, .closed)
        XCTAssertEqual(decided.dsaCase?.status, "decided")
        try await repository.submitDsaAppeal(.init(reportId: current.id, reason: "Additional precise facts supporting a review of this synthetic case.",
            operationId: UUID().uuidString, expectedRevision: decided.revision, revisionFormat: "exact", principalId: "feedback-audit-reporter"))
        try await signIn("manager")
        let appealed = try await repository.fetchFeedback(id: current.id)
        XCTAssertEqual(appealed.dsaCase?.status, "appealed")
        try await repository.decideDsaAppeal(.init(reportId: current.id, outcome: "upheld", reason: "The additional facts have been independently reviewed by a human.",
            humanReviewConfirmed: true, operationId: UUID().uuidString, expectedRevision: appealed.revision,
            revisionFormat: "exact", principalId: "feedback-audit-manager"))
        let final = try await repository.fetchFeedback(id: current.id)
        XCTAssertEqual(final.dsaCase?.status, "appealDecided")
        XCTAssertEqual(final.status, .closed)
        do { try await repository.deleteFeedback(id: current.id); XCTFail("Protected DSA retention must prevent deletion") } catch {}
    }

    private func prepareReportTarget() async throws -> String {
        let id = "feedback-audit-target-" + UUID().uuidString
        let base = "http://127.0.0.1:28080/v1/projects/demo-uac-release-audit/databases/(default)/documents/news/"
        var read = URLRequest(url: URL(string: base + "feedback-audit-target")!)
        read.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: read)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let source = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var fields = try XCTUnwrap(source["fields"] as? [String: Any])
        fields["id"] = ["stringValue": id]
        var write = URLRequest(url: URL(string: base + id)!)
        write.httpMethod = "PATCH"; write.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        write.setValue("application/json", forHTTPHeaderField: "Content-Type")
        write.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])
        let (_, written) = try await URLSession.shared.data(for: write)
        XCTAssertEqual((written as? HTTPURLResponse)?.statusCode, 200)
        return id
    }

    private func waitForNotices(sourceID: String, atLeast: Int) async throws -> QuerySnapshot {
        let uid = try XCTUnwrap(Auth.auth().currentUser?.uid)
        let query = Firestore.firestore().collection("users/\(uid)/notificationInbox").whereField("sourceId", isEqualTo: sourceID)
        for _ in 0..<30 {
            let value = try await query.getDocuments(source: .server)
            if value.count >= atLeast { return value }
            try await Task.sleep(for: .milliseconds(200))
        }
        return try await query.getDocuments(source: .server)
    }
}
