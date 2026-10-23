import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import XCTest
@testable import UkrainianCommunity

@MainActor
final class ProfileProjectionSDKTests: XCTestCase {
    func testRepairCreatesProjectionAndNeverOverwritesNewerRevision() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires isolated local Auth/Firestore fixture")
        }
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit" else {
            XCTFail("Refusing a non-demo project"); return
        }
        let auth = Auth.auth()
        try? auth.signOut()
        defer { try? auth.signOut() }
        _ = try await auth.signIn(withEmail: "projection@uac.test", password: "Emulator-Only-2026!")
        let uid = "projection-sdk-user"
        let service = UserProfileService.shared
        let original = try await service.fetchExistingUserProfile(uid: uid)
        try await service.ensurePublicProfile(for: original)
        let publicReference = Firestore.firestore().document("publicProfiles/" + uid)
        let initial = try await publicReference.getDocument(source: .server)
        XCTAssertEqual(initial.get("displayName") as? String, "Original")
        try await Firestore.firestore().document("users/" + uid).updateData([
            "displayName": "Newest", "updatedAt": FieldValue.serverTimestamp()
        ])
        let latest = try await service.fetchExistingUserProfile(uid: uid)
        try await service.upsertPublicProfile(for: latest)
        try await service.ensurePublicProfile(for: original)
        let final = try await publicReference.getDocument(source: .server)
        XCTAssertEqual(final.get("displayName") as? String, "Newest")
    }
}
