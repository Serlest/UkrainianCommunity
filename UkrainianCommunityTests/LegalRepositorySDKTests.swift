import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
@testable import UkrainianCommunity

/// Opt-in connected SDK proof. Fixed loopback/demo transport; never production.
@MainActor
final class LegalRepositorySDKTests: XCTestCase {
    func testDraftMetadataConflictPublishHistoryAndIdempotentAcknowledgementThroughActualSDK() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires disposable legal18 fixtures in loopback Firebase emulators")
        }
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit",
              Firestore.firestore().settings.host == "127.0.0.1:28080", !Firestore.firestore().settings.isSSLEnabled else {
            XCTFail("Refusing a non-demo SDK connection"); return
        }
        try? Auth.auth().signOut()
        let signedIn = try await Auth.auth().signIn(withEmail: "legal18-sdk-owner@uac.test", password: "Emulator-Only-2026!")
        let user = signedIn.user
        defer { try? Auth.auth().signOut() }
        XCTAssertEqual(user.uid, "legal18-sdk-owner")
        let repo = FirestoreLegalDocumentRepository()
        let initial = try await repo.fetchManagementState(type: .terms)
        XCTAssertNil(initial.draftDocument)
        var created = LegalDocumentDraft.from(activeDocument: initial.activeDocument)
        created.changeSummary = "DE:Disposable SDK test\nUK:Ізольована перевірка SDK"
        try await repo.saveDraft(created, updatedBy: user.uid)
        let reopened = try await repo.fetchManagementState(type: .terms)
        let stored = try XCTUnwrap(reopened.draftDocument)
        var first = LegalDocumentDraft(document: stored), stale = LegalDocumentDraft(document: stored)
        first.changeSummary = "DE:First device edit\nUK:Перша правка"
        try await repo.saveDraft(first, updatedBy: user.uid)
        stale.changeSummary = "DE:Stale device edit\nUK:Застаріла правка"
        do { try await repo.saveDraft(stale, updatedBy: user.uid); XCTFail("Stale metadata must not overwrite a saved revision") } catch {}
        do { try await repo.discardDraft(stale); XCTFail("Stale confirmation must not delete the newer draft") } catch {}
        do { try await repo.publishDraft(stale, publishedBy: user.uid); XCTFail("Stale confirmation must not publish the newer draft") } catch {}
        let unchanged = try await repo.fetchManagementState(type: .terms)
        XCTAssertEqual(unchanged.draftDocument?.changeSummary, first.changeSummary)
        XCTAssertEqual(unchanged.activeDocument.version, initial.activeDocument.version)
        let publishable = LegalDocumentDraft(document: try XCTUnwrap(unchanged.draftDocument))
        try await repo.publishDraft(publishable, publishedBy: user.uid)
        let publicRead = try await repo.fetchAuthoritativeActiveDocument(type: .terms)
        XCTAssertEqual(publicRead.version, created.version)
        // The SDK now has this version cached. An offline cache must still not be
        // presented as a freshly verified public document.
        try await Firestore.firestore().disableNetwork()
        do { _ = try await repo.fetchActiveDocumentForReader(type: .terms); XCTFail("Offline cache must not impersonate a verified server read") } catch {}
        try await Firestore.firestore().enableNetwork()
        // A new version must still require acknowledgement, including for its publisher.
        do { _ = try await repo.fetchManagementState(type: .terms); XCTFail("Owner access must remain gated until the new terms are acknowledged") } catch {}
        let firstReceipt = try await repo.acceptDocument(type: .terms, version: created.version,
            appVersion: "sdk-audit", locale: "uk", acceptedFromPlatform: "ios")
        let retriedReceipt = try await repo.acceptDocument(type: .terms, version: created.version,
            appVersion: "sdk-audit", locale: "uk", acceptedFromPlatform: "ios")
        XCTAssertEqual(firstReceipt.acceptedAt, retriedReceipt.acceptedAt)
        let final = try await repo.fetchManagementState(type: .terms)
        XCTAssertNil(final.draftDocument); XCTAssertEqual(final.activeDocument.version, created.version)
        let previous = try await repo.fetchPublishedVersion(type: .terms, version: initial.activeDocument.version,
            expectedHash: initial.activeDocument.contentHash)
        XCTAssertEqual(previous, initial.activeDocument)
        let history = try await repo.fetchVersionHistory(type: .terms, before: nil)
        XCTAssertEqual(history.documents.map(\.version), [created.version, initial.activeDocument.version])
        let evidence = CloudLegalEvidenceRepository()
        let page = try await evidence.fetchEvidencePage(userID: user.uid, cursor: nil, filter: .terms, query: "")
        let exact = page.history.events.filter { $0.eventType == .termsAccepted && $0.version == created.version && $0.source == "legalDocument" }
        XCTAssertEqual(exact.count, 1)
        XCTAssertEqual(exact.first?.contentHash, final.activeDocument.contentHash)
        let full = try await evidence.fetchEvidence(userID: user.uid)
        XCTAssertEqual(full.events.filter { $0.version == created.version && $0.source == "legalDocument" }.count, 1)
        let rawUser = try await Firestore.firestore().collection("users").document(user.uid).getDocument(source: .server)
        XCTAssertEqual(rawUser.get("acceptedTermsVersion") as? String, created.version)
    }
}
