import Foundation
import Combine
import Testing
@testable import UkrainianCommunity

@MainActor
struct BannerCountdownTests {
    private func banner(countdown: FeaturedBannerCountdown? = nil) -> FeaturedBanner {
        FeaturedBanner(id:"b14",title:"Подія",imageURL:"https://example.com/banner.jpg",visibleSections:[.home],createdAt:.now,updatedAt:.now,createdBy:"owner",countdown:countdown)
    }
    @Test func elapsedTimeUsesExactInstantsAcrossViennaDSTAndZeroBoundary() throws {
        let format = ISO8601DateFormatter()
        let before = try #require(format.date(from:"2027-03-28T00:30:00Z"))
        let after = try #require(format.date(from:"2027-03-28T01:30:00Z"))
        let timer = FeaturedBannerCountdown(targetDate:after,label:"До події",germanLabel:"",completion:.hideCountdown)
        #expect(timer.remaining(at:before)?.hours == 1)
        #expect(timer.remaining(at:after) == nil)
        #expect(timer.remaining(at:after.addingTimeInterval(1)) == nil)
        #expect(timer.remaining(at:after.addingTimeInterval(-1))?.minutes == 1)
        #expect(timer.label(for:.german)=="До події")
        let long = FeaturedBannerCountdown(targetDate:before.addingTimeInterval(86400 * 4000),label:"",germanLabel:"",completion:.showStarted)
        #expect(long.remaining(at:before)?.days == 4000)
    }
    @Test func hiddenBannerExpiresAtCountdownForAllPlacementsAndRegions() {
        let now=Date()
        for completion in FeaturedBannerCountdown.Completion.allCases {
            let timer=FeaturedBannerCountdown(targetDate:now,label:"",germanLabel:"",completion:completion)
            let value=banner(countdown:timer)
            #expect(value.isVisible(on:now)==(completion != .hideBanner))
            #expect(value.isVisible(on:now.addingTimeInterval(-1)))
        }
    }
    @Test func editorCopiesSavesReopensAndClearsAllCountdownFields() async throws {
        let repo=MockFeaturedBannerRepository(banners:[])
        let model=FeaturedBannerEditorViewModel(repository:repo)
        model.imageURL="https://example.com/banner.jpg";model.title="Подія"
        #expect(!model.hasCountdown)
        model.hasCountdown=true;model.countdownDate=Date().addingTimeInterval(86400*4+3600);model.countdownLabel="До події";model.countdownGermanLabel="Bis zum Ereignis";model.countdownCompletion = .showStarted
        #expect(model.hasUnsavedChanges)
        #expect(await model.save(updatedBy:"owner"))
        let saved=try #require(try await repo.fetchAllBannersForOwner().first)
        #expect(saved.countdown==model.resolvedCountdown)
        let edit=FeaturedBannerEditorViewModel(repository:repo,mode:.edit(saved))
        #expect(!edit.hasUnsavedChanges)
        #expect(edit.countdownGermanLabel=="Bis zum Ereignis")
        let copy=FeaturedBannerEditorViewModel(repository:repo,mode:.duplicate(saved))
        #expect(copy.resolvedCountdown==saved.countdown);#expect(!copy.isActive)
        try await repo.setBannerActive(id:saved.id,isActive:false,updatedBy:"owner")
        #expect(try await repo.fetchAllBannersForOwner().first?.countdown==saved.countdown)
        edit.hasCountdown=false
        #expect(await edit.save(updatedBy:"owner"))
        #expect(try await repo.fetchAllBannersForOwner().first?.countdown==nil)
    }
    @Test func countdownValidationIncludesUTF16AndStartOrder() {
        let model=FeaturedBannerEditorViewModel(repository:MockFeaturedBannerRepository(banners:[]))
        model.imageURL="https://example.com/banner.jpg";model.hasCountdown=true
        model.countdownLabel=String(repeating:"😀",count:21)
        #expect(model.validationMessage==BannerCountdownStrings.text("invalid"))
        model.countdownLabel="";model.hasStartDate=true;model.startsAt=model.countdownDate
        #expect(model.validationMessage==BannerCountdownStrings.text("invalid"))
    }
    @Test func payloadAndSeparatePresentationDecodeRoundTrip() throws {
        let timer=FeaturedBannerCountdown(targetDate:Date(timeIntervalSince1970:1_900_000_000),label:"До події",germanLabel:"Bis zum Ereignis",completion:.hideBanner)
        let payload=try FeaturedBannerMutationPayload(banner:banner(countdown:timer))
        let data=try JSONSerialization.jsonObject(with:JSONEncoder().encode(payload)) as! [String:Any]
        #expect(data["presentationVersion"] as? Int==1)
        let raw=try #require(data["countdown"] as? [String:Any])
        #expect(FirestoreFeaturedBannerRepository.decodeCountdown(raw)==timer)
        #expect(FirestoreFeaturedBannerRepository.decodeCountdown(raw.merging(["completion":"unknown"]){_,b in b})==nil)
    }
    @Test func neighborEdgeNeverQualifiesAndSettledCardRequiresNewDwell() {
        var tracker=FeaturedBannerExposureTracker();let now=Date()
        #expect(tracker.observe(bannerID:"neighbor",section:.home,visibleFraction:0.06,isEligible:true,at:now)==nil)
        #expect(tracker.observe(bannerID:"neighbor",section:.home,visibleFraction:0.06,isEligible:true,at:now.addingTimeInterval(2))==nil)
        #expect(tracker.observe(bannerID:"selected",section:.home,visibleFraction:1,isEligible:false,at:now.addingTimeInterval(2))==nil)
        #expect(tracker.observe(bannerID:"selected",section:.home,visibleFraction:1,isEligible:true,at:now.addingTimeInterval(3))==nil)
        #expect(tracker.observe(bannerID:"selected",section:.home,visibleFraction:1,isEligible:true,at:now.addingTimeInterval(4.1))?.kind == .impression)
    }
}

@MainActor private final class LostReplyBannerRepository: FeaturedBannerRepository {
    var calls:[String]=[];var saved:FeaturedBanner?;var failOnce=true
    func fetchActiveBanners(for section:FeaturedBannerVisibleSection,federalState:AustrianFederalState?) async throws->[FeaturedBanner]{saved.map{[$0]} ?? []}
    func fetchAllBannersForOwner() async throws->[FeaturedBanner]{saved.map{[$0]} ?? []}
    func createBanner(_ banner:FeaturedBanner) async throws {saved=banner}
    func updateBanner(_ banner:FeaturedBanner) async throws {saved=banner}
    func setBannerActive(id:String,isActive:Bool,updatedBy:String) async throws {}
    func deleteBanner(id:String) async throws {}
    func saveBanner(_ banner:FeaturedBanner,isNew:Bool,expectedUpdatedAt:Date?,operationID:String) async throws {
        calls.append(operationID);saved=banner
        if failOnce {failOnce=false;throw AppError.network}
    }
}
@MainActor private final class CountdownImageSpy: FeaturedBannerImageService {
    var uploads=0;var deleted:[URL]=[]
    func uploadFeaturedBannerImage(bannerId:String,imageData:Data) async throws->URL {uploads += 1;return URL(string:"https://example.com/uploaded.jpg")!}
    func uploadFeaturedBannerImage(bannerId:String,processedImage:ProcessedImageSelection) async throws->URL {try await uploadFeaturedBannerImage(bannerId:bannerId,imageData:processedImage.data)}
    func deleteFeaturedBannerImage(at imageURL:URL,bannerId:String) async throws {deleted.append(imageURL)}
}
extension BannerCountdownTests {
    @Test func lostReplyKeepsCommittedImageAndRetriesSameReviewedCommandWithoutReupload() async throws {
        let repo=LostReplyBannerRepository(),images=CountdownImageSpy()
        let model=FeaturedBannerEditorViewModel(repository:repo,imageUploadService:images)
        model.title="Lost reply";model.setSelectedImageData(Data([1]));model.hasCountdown=true
        let first=await model.save(updatedBy:"owner");#expect(!first)
        #expect(repo.saved != nil);#expect(images.deleted.isEmpty);#expect(images.uploads==1)
        let second=await model.save(updatedBy:"owner");#expect(second)
        #expect(repo.calls.count==2);#expect(repo.calls[0]==repo.calls[1]);#expect(images.uploads==1)
        #expect(repo.saved?.countdown==model.resolvedCountdown)
    }
    @Test func choosingAnotherImageAfterFailedReplyCreatesAnotherReviewedCommand() async {
        let repo=LostReplyBannerRepository(),images=CountdownImageSpy()
        let model=FeaturedBannerEditorViewModel(repository:repo,imageUploadService:images)
        model.title="Image change";model.setSelectedImageData(Data([1]))
        #expect(await model.save(updatedBy:"owner")==false)
        model.setSelectedImageData(Data([2]))
        #expect(await model.save(updatedBy:"owner"))
        #expect(repo.calls.count==2);#expect(repo.calls[0] != repo.calls[1]);#expect(images.uploads==2)
    }
    @Test func revokedAuthorityStopsBeforeServerAndPreservesDraft() async {
        let repo=LostReplyBannerRepository()
        let model=FeaturedBannerEditorViewModel(repository:repo)
        model.imageURL="https://example.com/banner.jpg";model.title="Draft"
        let saved=await model.save(updatedBy:"owner",isAuthorized:{false})
        #expect(!saved);#expect(model.title=="Draft");#expect(repo.calls.isEmpty)
    }
}

extension BannerCountdownTests {
    @Test func targetPickerTraversesBeyondFormer250LimitAndFindsOldSelectedMaterial() async throws {
        let base=Date()
        let posts=(0..<301).map { n in NewsPost(id:"target-\(n)",title:"Material \(n)",subtitle:"",body:"Body",authorName:"Fixture",publishedAt:base.addingTimeInterval(-Double(n)),createdAt:base.addingTimeInterval(-Double(n)),updatedAt:base,comments:[],moderationStatus:.approved,likeCount:0,likeState:.notLiked) }
        let news=MockNewsRepository(seededNews:posts)
        let model=FeaturedBannerEditorViewModel(repository:MockFeaturedBannerRepository(banners:[]),newsRepository:news)
        model.actionType = .news;model.actionTargetID="target-300"
        await model.loadActionTargetsIfNeeded()
        #expect(model.actionTargetItems(matching:"").count==50)
        #expect(model.selectedActionTargetItem?.id=="target-300")
        var pages=1
        while model.hasMoreActionTargets && pages<10 {await model.loadMoreActionTargets();pages += 1}
        #expect(pages==7);#expect(!model.hasMoreActionTargets)
        #expect(Set(model.actionTargetItems(matching:"").map(\.id)).count==301)
        #expect(model.actionTargetItems(matching:"Material 300").map(\.id)==["target-300"])
    }
    @Test func countdownBoundaryRemovesCachedBannerWithoutAnotherServerRequest() async throws {
        let clock = BannerBoundaryClock()
        let value=banner(countdown:.init(targetDate:clock.date.addingTimeInterval(300),label:"",germanLabel:"",completion:.hideBanner))
        let cache=FeaturedBannerCache(),repo=MockFeaturedBannerRepository(banners:[value])
        let model=FeaturedBannerListViewModel(repository:repo,cache:cache,now:{clock.date},boundarySleep:{ try await clock.sleep($0) })
        await model.loadIfNeeded(for:.home,federalState:nil)
        #expect(model.banners.count==1)
        await clock.waitUntilSleeping()
        #expect(clock.interval == 300.05)
        let expired = Task {
            for await values in model.$banners.values { if values.isEmpty { return true } }
            return false
        }
        let resume = try #require(clock.waiting)
        clock.date += 301;clock.waiting = nil;resume.resume()
        #expect(await expired.value)
        #expect(model.banners.isEmpty)
        #expect(cache.entry(for:.init(section:.home,federalState:nil),maxAge:30)?.banners.count==1)
    }
}

@MainActor private final class BannerBoundaryClock {
    var date = Date()
    var interval: TimeInterval?
    var waiting: CheckedContinuation<Void, Error>?
    private var started: CheckedContinuation<Void, Never>?
    func waitUntilSleeping() async {
        if waiting != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func sleep(_ interval: TimeInterval) async throws {
        self.interval = interval
        try await withCheckedThrowingContinuation {
            waiting = $0; started?.resume(); started = nil
        }
    }
}
