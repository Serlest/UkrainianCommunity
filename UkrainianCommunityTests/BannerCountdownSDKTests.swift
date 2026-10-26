import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import UIKit
@testable import UkrainianCommunity

@MainActor final class BannerCountdownSDKTests: XCTestCase {
    func testCountdownPersistsThroughRealSDKWithLegacyFieldsAndForeignDenial() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"]=="1" else { throw XCTSkip("Fixed localhost demo only") }
        guard FirebaseApp.app()?.options.projectID=="demo-uac-release-audit",Firestore.firestore().settings.host=="127.0.0.1:28080" else {XCTFail("Refusing non-local SDK");return}
        let auth=Auth.auth(),owner="banners-audit-owner-20261026",member="banners-audit-member-20261026"
        try? auth.signOut();defer{try? auth.signOut()}
        _ = try await auth.signIn(withEmail:owner+"@uac.test",password:"Emulator-Only-2026!")
        let repo=FirestoreFeaturedBannerRepository(mutationClient:LostBannerReplySDKClient())
        let model=FeaturedBannerEditorViewModel(repository:repo)
        model.imageURL="https://example.com/banner.jpg";model.title="SDK countdown";model.hasCountdown=true
        model.countdownDate=Date(timeIntervalSince1970:1_900_000_000);model.countdownLabel="До події";model.countdownGermanLabel="Bis zum Ereignis";model.countdownCompletion = .hideBanner
        let created = await model.save(updatedBy:owner); XCTAssertTrue(created)
        let initial = try await repo.fetchAllBannersForOwner()
        var saved=try XCTUnwrap(initial.first(where:{$0.title=="SDK countdown"}))
        XCTAssertEqual(saved.countdown,model.resolvedCountdown)
        let raw=try await Firestore.firestore().collection("featuredBanners").document(saved.id).getDocument(source:.server)
        XCTAssertNil(raw.data()?["countdown"]);XCTAssertNil(raw.data()?["presentationVersion"])
        XCTAssertEqual((raw.data()?["endsAt"] as? Timestamp)?.dateValue(),model.countdownDate)
        let edit=FeaturedBannerEditorViewModel(repository:repo,mode:.edit(saved));edit.countdownCompletion = .showStarted;edit.countdownLabel="Новий підпис"
        let image = UIGraphicsImageRenderer(size:CGSize(width:800,height:450)).image { context in
            UIColor.systemBlue.setFill();context.fill(CGRect(x:0,y:0,width:800,height:450))
        }
        edit.setSelectedImageData(try XCTUnwrap(image.jpegData(compressionQuality:0.8)))
        let updated = await edit.save(updatedBy:owner); XCTAssertTrue(updated)
        let reopened = try await repo.fetchAllBannersForOwner()
        saved=try XCTUnwrap(reopened.first(where:{$0.id==saved.id}))
        XCTAssertEqual(saved.countdown?.label,"Новий підпис")
        XCTAssertNil(saved.endsAt, "Countdown-generated compatibility expiry must not become an explicit user schedule")
        let imageURL = try XCTUnwrap(saved.imageURL)
        let reference = Storage.storage().reference(forURL:imageURL)
        let metadata = try await reference.getMetadata();XCTAssertEqual(metadata.contentType,"image/jpeg")
        let bytes = try await reference.data(maxSize:3_000_000);XCTAssertNotNil(UIImage(data:bytes))
        try auth.signOut();_ = try await auth.signIn(withEmail:member+"@uac.test",password:"Emulator-Only-2026!")
        let publicBanners=try await repo.fetchActiveBanners(for:.home,federalState:nil)
        XCTAssertEqual(publicBanners.first(where:{$0.id==saved.id})?.countdown?.label,"Новий підпис")
        do {try await repo.deleteBanner(id:saved.id);XCTFail("Member cannot delete")}catch{XCTAssertEqual(error as? AppError,.permissionDenied)}
        do {try await reference.delete();XCTFail("Member cannot delete another banner's image")}catch{XCTAssertEqual((error as NSError).code,StorageErrorCode.unauthorized.rawValue)}
        try auth.signOut();_ = try await auth.signIn(withEmail:owner+"@uac.test",password:"Emulator-Only-2026!")
        try await repo.deleteBanner(id:saved.id)
        let remaining = try await repo.fetchAllBannersForOwner(); XCTAssertFalse(remaining.contains(where:{$0.id==saved.id}))
        // The fixture namespace preserves the production URL shape inside the Storage emulator.
        // Its asset is explicitly removed here; backend reference cleanup is tested in its own bucket fixture.
        try? await reference.delete()
    }
}

@MainActor private final class LostBannerReplySDKClient: FeaturedBannerMutationClient {
    private var loseNextReply = true
    func saveFeaturedBanner(_ banner:FeaturedBanner, mode:FeaturedBannerSaveFunctionMode, expectedUpdatedAt:Date?, operationID:String) async throws {
        try await CloudFunctionsClient.shared.saveFeaturedBanner(banner,mode:mode,expectedUpdatedAt:expectedUpdatedAt,operationID:operationID)
        if loseNextReply { loseNextReply = false; throw AppError.network }
    }
    func setFeaturedBannerActive(id:String,isActive:Bool) async throws {
        try await CloudFunctionsClient.shared.setFeaturedBannerActive(id:id,isActive:isActive)
    }
    func deleteFeaturedBanner(id:String) async throws { try await CloudFunctionsClient.shared.deleteFeaturedBanner(id:id) }
}
