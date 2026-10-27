import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
@testable import UkrainianCommunity

@MainActor final class ProjectSupportSDKTests: XCTestCase {
    func testOwnerSaveConflictJournalDeliveryAndAdminDenialThroughActualSDKAndRules() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Requires fixed disposable loopback Auth/Firestore/Functions fixtures") }
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit",
              Firestore.firestore().settings.host == "127.0.0.1:28080", !Firestore.firestore().settings.isSSLEnabled else {
            XCTFail("Refusing a non-demo connection");return
        }
        let db=Firestore.firestore(), ownerID="legal18-sdk-owner"
        try? Auth.auth().signOut()
        let owner=try await Auth.auth().signIn(withEmail:"legal18-sdk-owner@uac.test",password:"Emulator-Only-2026!").user
        defer { try? Auth.auth().signOut() }
        XCTAssertEqual(owner.uid,ownerID);XCTAssertTrue(owner.isEmailVerified)
        let repo=FirestoreDonationConfigRepository()
        var initial=DonationConfig.defaults;initial.donationURL="https://example.org/support19";initial.isEnabled=true
        let first=try await repo.saveDonationConfig(initial,updatedBy:ownerID)
        let firstRevision=try XCTUnwrap(first.sourceRevision)
        let independentlyRead=try await repo.fetchDonationConfig()
        XCTAssertEqual(independentlyRead?.sourceRevision,first.sourceRevision)
        var next=first;next.titleUK="Другий пристрій19"
        let second=try await repo.saveDonationConfig(next,updatedBy:ownerID)
        let secondRevision=try XCTUnwrap(second.sourceRevision)
        var stale=first;stale.titleUK="Застаріле19"
        do { _ = try await repo.saveDonationConfig(stale,updatedBy:ownerID);XCTFail("Stale save must reject") }
        catch DonationConfigSaveError.conflict {}
        let logs=try await waitForLogs(db:db,first:firstRevision,second:secondRevision)
        let successes=logs.filter { $0["eventType"] as? String == "configurationUpdated" }
        XCTAssertEqual(successes.count,2)
        XCTAssertEqual(Set(successes.compactMap { ($0["metadata"] as? [String:Any])?["resultRevision"] as? String }.map { $0.replacingOccurrences(of:" ",with:"") }),Set([firstRevision,secondRevision]))
        let failure=try XCTUnwrap(logs.first { $0["errorCode"] as? String == "configuration.conflict" })
        XCTAssertEqual(failure["actorUserId"] as? String,ownerID)
        XCTAssertEqual((failure["metadata"] as? [String:Any])?["failureStage"] as? String,"writeConfiguration")
        XCTAssertEqual((failure["metadata"] as? [String:Any])?["expectedRevision"] as? String,DonationConfigDiagnostics.fingerprint(first.sourceRevision))
        XCTAssertTrue(logs.allSatisfy { !String(describing:$0["metadata"]).contains("https://") })
        try Auth.auth().signOut()
        let admin=try await Auth.auth().signIn(withEmail:"support19-sdk-admin@uac.test",password:"Emulator-Only-2026!").user
        XCTAssertTrue(admin.isEmailVerified)
        let publicRead=try await repo.fetchDonationConfig();XCTAssertEqual(publicRead?.sourceRevision,second.sourceRevision)
        var denied=try XCTUnwrap(publicRead);denied.titleUK="Admin must not save"
        do { _ = try await repo.saveDonationConfig(denied,updatedBy:admin.uid);XCTFail("Admin write must reject") }
        catch { XCTAssertEqual(error as? AppError,.permissionDenied) }
        let stillSecond=try await repo.fetchDonationConfig();XCTAssertEqual(stillSecond?.sourceRevision,second.sourceRevision)
        try Auth.auth().signOut()
        _ = try await Auth.auth().signIn(withEmail:"legal18-sdk-owner@uac.test",password:"Emulator-Only-2026!")
        let final=try await self.logs(db:db).filter { row in
            let revision=(row["metadata"] as? [String:Any])?["resultRevision"] as? String
            return revision == DonationConfigDiagnostics.fingerprint(firstRevision) || revision == DonationConfigDiagnostics.fingerprint(secondRevision)
        }
        XCTAssertEqual(final.filter { $0["eventType"] as? String == "configurationUpdated" }.count,2)
    }
    private func logs(db:Firestore) async throws -> [[String:Any]] {
        try await db.collection("systemLogs").whereField("operationName",isEqualTo:"saveDonationConfig").getDocuments(source:.server).documents.map { $0.data() }
    }
    private func waitForLogs(db:Firestore,first:String,second:String) async throws -> [[String:Any]] {
        for _ in 0..<200 {
            await SystemLogDeliveryQueue.shared.flush()
            let result=try await logs(db:db).filter { row in
                let metadata=row["metadata"] as? [String:Any] ?? [:]
                return metadata["resultRevision"] as? String == DonationConfigDiagnostics.fingerprint(first)
                    || metadata["resultRevision"] as? String == DonationConfigDiagnostics.fingerprint(second)
                    || metadata["expectedRevision"] as? String == DonationConfigDiagnostics.fingerprint(first)
            }
            if result.filter({$0["eventType"] as? String == "configurationUpdated"}).count == 2, result.contains(where:{$0["errorCode"] as? String == "configuration.conflict"}) { return result }
            try await Task.sleep(for:.milliseconds(100))
        }
        XCTFail("Actual support journal records did not arrive")
        return try await logs(db:db)
    }
}
