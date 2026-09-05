import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import UIKit
@testable import UkrainianCommunity

@MainActor
final class FirebaseEmulatorJourneyTests: XCTestCase {
    func testActualSDKPermissionsPhotoLifecycleConsentAndAccountSwitch() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Run separately against the local Firebase Emulator fixture.")
        }
        // Never turn a missing test configuration into a request to a real project.
        XCTAssertEqual(FirebaseApp.app()?.options.projectID, "demo-uac-release-audit")
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit" else { return }
        let auth = Auth.auth()
        try? auth.signOut()
        let signedIn = try await auth.signIn(withEmail: "editor@uac.test", password: "Emulator-Only-2026!")
        XCTAssertEqual(signedIn.user.uid, "sdk-editor")
        XCTAssertTrue(signedIn.user.isEmailVerified)
        OrganizationAccessStore.shared.transition(to: signedIn.user.uid)
        let database = Firestore.firestore()
        let org = database.collection("organizations").document("sdk-org")
        let call = Functions.functions(region: "europe-west3")
        let before = try await org.getDocument(source: .server)
        let updated = try XCTUnwrap(before.get("updatedAt") as? Timestamp)
        let response = try await call.httpsCallable("updateOrganizationInfo").call([
            "principalId": "sdk-editor", "organizationId": "sdk-org", "operationId": UUID().uuidString,
            "expectedRevision": "\(updated.seconds):\(updated.nanoseconds)", "targetStatus": "approved",
            "fields": ["name": "SDK verified organization"],
        ])
        XCTAssertEqual((response.data as? [String: Any])?["didChange"] as? Bool, true)
        let changed = try await org.getDocument(source: .server)
        XCTAssertEqual(changed.get("name") as? String, "SDK verified organization")
        XCTAssertEqual(changed.get("ownerId") as? String, "sdk-editor")
        XCTAssertEqual(changed.get("submittedAt") as? Timestamp, before.get("submittedAt") as? Timestamp)

        let repository = FirestoreOrganizationPhotoRepository()
        var missingAppCheck = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:15001/demo-uac-release-audit/europe-west3/saveOrganizationPhoto")))
        missingAppCheck.httpMethod = "POST"
        missingAppCheck.setValue("application/json", forHTTPHeaderField: "Content-Type")
        missingAppCheck.setValue("Bearer " + (try await signedIn.user.getIDToken()), forHTTPHeaderField: "Authorization")
        missingAppCheck.httpBody = try JSONSerialization.data(withJSONObject: ["data": [:]])
        let (_, rejected) = try await URLSession.shared.data(for: missingAppCheck)
        XCTAssertEqual((rejected as? HTTPURLResponse)?.statusCode, 401, "New uploads must retain the existing App Check requirement")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let jpeg = try XCTUnwrap(renderer.image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }.jpegData(compressionQuality: 0.8))
        let photo = try await repository.addPhoto(organizationId: "sdk-org", imageData: jpeg, caption: "SDK initial", uploadedBy: "sdk-editor")
        let storedBytes = try await Storage.storage().reference(forURL: photo.imageURL).data(maxSize: 3_000_000)
        XCTAssertEqual(storedBytes, jpeg)
        let replacement = try await repository.replacePhoto(photo, imageData: jpeg, caption: "SDK replaced")
        XCTAssertEqual(replacement.id, photo.id)
        XCTAssertNotEqual(replacement.imageURL, photo.imageURL)
        XCTAssertEqual(replacement.caption, "SDK replaced")
        let withPhoto = try await org.getDocument(source: .server)
        XCTAssertEqual(withPhoto.get("photoCount") as? Int, 1)
        do {
            _ = try await repository.replacePhoto(photo, imageData: jpeg, caption: "Stale edit")
            XCTFail("Stale photo replacement must be rejected")
        } catch let error as OrganizationAccessFailure { XCTAssertEqual(error.reason, "object_changed") }

        let consentID = UUID().uuidString
        let consent: [String: Any] = ["principalId": "sdk-editor", "enabled": true, "consentID": consentID,
            "locale": "de", "privacyVersion": "2026.12", "disclosureVersion": "2026-08-25.1"]
        _ = try await call.httpsCallable("updateAnalyticsConsentV2").call(consent)
        var revoke = consent; revoke["enabled"] = false
        _ = try await call.httpsCallable("updateAnalyticsConsentV2").call(revoke)
        do {
            _ = try await call.httpsCallable("updateAnalyticsConsentV2").call(consent)
            XCTFail("A delayed request must not re-enable withdrawn consent")
        } catch { XCTAssertEqual((error as NSError).code, FunctionsErrorCode.failedPrecondition.rawValue) }

        try auth.signOut()
        let outsider = try await auth.signIn(withEmail: "outsider@uac.test", password: "Emulator-Only-2026!")
        XCTAssertEqual(outsider.user.uid, "sdk-outsider")
        OrganizationAccessStore.shared.transition(to: outsider.user.uid)
        do {
            _ = try await repository.replacePhoto(replacement, imageData: jpeg, caption: "Unauthorized")
            XCTFail("The next account must not inherit photo permissions")
        } catch let error as OrganizationAccessFailure { XCTAssertEqual(error.reason, "role_missing") }
        do {
            try await org.updateData(["ownerId": "sdk-outsider"])
            XCTFail("Firestore Rules must reject ownership forgery")
        } catch { XCTAssertEqual((error as NSError).code, FirestoreErrorCode.permissionDenied.rawValue) }
        try auth.signOut()
        _ = try await auth.signIn(withEmail: "editor@uac.test", password: "Emulator-Only-2026!")
        OrganizationAccessStore.shared.transition(to: "sdk-editor")
        try await repository.deletePhoto(replacement)
        let removed = try await org.collection("photos").document(photo.id).getDocument(source: .server)
        XCTAssertFalse(removed.exists)
        let empty = try await org.getDocument(source: .server)
        XCTAssertEqual(empty.get("photoCount") as? Int, 0)
        try auth.signOut()
        OrganizationAccessStore.shared.transition(to: nil)
    }
}
