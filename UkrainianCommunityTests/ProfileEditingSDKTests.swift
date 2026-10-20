import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
@testable import UkrainianCommunity

@MainActor
final class ProfileEditingSDKTests: XCTestCase {
    func testProfilePersistenceAfterSignOutAndSignInThroughRealSDK() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires isolated owner-profile emulator fixtures.")
        }
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit" else {
            XCTFail("Refusing a non-demo project"); return
        }
        let auth = Auth.auth()
        try? auth.signOut()
        defer { try? auth.signOut() }
        _ = try await auth.signIn(withEmail: "profile-owner@uac.test", password: "Emulator-Only-2026!")
        let repository = FirestoreUserRepository()
        let draft = EditableUserProfileDraft(fullName: "Owner SDK Name", displayName: "Owner SDK Display",
            telegramUsername: "owner_sdk", city: "Graz", bio: "Persisted profile",
            selectedFederalState: .steiermark)
        let saved = try await repository.updateProfile(draft)
        XCTAssertEqual(saved.id, "profile-sdk-owner")
        XCTAssertEqual(saved.globalRole, .owner)
        XCTAssertEqual(saved.displayName, draft.displayName)
        let publicProfile = try await Firestore.firestore().document("publicProfiles/profile-sdk-owner").getDocument(source: .server)
        XCTAssertEqual(publicProfile.get("displayName") as? String, draft.displayName)
        try auth.signOut()
        _ = try await auth.signIn(withEmail: "profile-owner@uac.test", password: "Emulator-Only-2026!")
        let reopened = try await UserProfileService.shared.fetchExistingUserProfile(uid: "profile-sdk-owner")
        XCTAssertEqual(reopened.fullName, draft.fullName)
        XCTAssertEqual(reopened.city, draft.city)
        XCTAssertEqual(reopened.bio, draft.bio)
        XCTAssertEqual(reopened.telegramUsername, draft.telegramUsername)
        XCTAssertEqual(reopened.selectedFederalState, .steiermark)
        try auth.signOut()
        _ = try await auth.signIn(withEmail: "profile-member@uac.test", password: "Emulator-Only-2026!")
        do {
            try await Firestore.firestore().document("users/profile-sdk-owner").updateData(["displayName": "Forged"])
            XCTFail("Another account must not edit the owner profile")
        } catch {
            XCTAssertEqual((error as NSError).code, FirestoreErrorCode.permissionDenied.rawValue)
        }
    }
}
