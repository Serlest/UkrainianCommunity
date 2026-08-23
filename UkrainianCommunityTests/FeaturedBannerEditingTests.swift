import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
private final class RecordingBannerImageService: FeaturedBannerImageService {
    let uploadedURL: URL
    private(set) var uploadedBannerIDs: [String] = []
    private(set) var deletedURLs: [URL] = []

    init(uploadedURL: URL) {
        self.uploadedURL = uploadedURL
    }

    func uploadFeaturedBannerImage(bannerId: String, imageData: Data) async throws -> URL {
        uploadedBannerIDs.append(bannerId)
        return uploadedURL
    }

    func uploadFeaturedBannerImage(
        bannerId: String,
        processedImage: ProcessedImageSelection
    ) async throws -> URL {
        uploadedBannerIDs.append(bannerId)
        return uploadedURL
    }

    func deleteFeaturedBannerImage(at imageURL: URL, bannerId: String) async throws {
        deletedURLs.append(imageURL)
    }
}

private final class RecordingBannerRepository: FeaturedBannerRepository {
    var updateError: AppError?
    private(set) var updatedBanner: FeaturedBanner?

    func fetchActiveBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async throws -> [FeaturedBanner] {
        []
    }

    func fetchAllBannersForOwner() async throws -> [FeaturedBanner] {
        updatedBanner.map { [$0] } ?? []
    }

    func createBanner(_ banner: FeaturedBanner) async throws {
        updatedBanner = banner
    }

    func updateBanner(_ banner: FeaturedBanner) async throws {
        if let updateError {
            throw updateError
        }
        updatedBanner = banner
    }

    func setBannerActive(id: String, isActive: Bool, updatedBy userID: String) async throws {}
    func deleteBanner(id: String) async throws {}
}

@MainActor
struct FeaturedBannerEditingTests {
    @Test func mutationPayloadOmitsClearedTextAndUsesNewImage() throws {
        let banner = makeBanner(
            title: "   ",
            subtitle: "",
            imageURL: "https://example.com/new-image.jpg"
        )

        let payload = try FeaturedBannerMutationPayload(banner: banner)

        #expect(payload.title == nil)
        #expect(payload.subtitle == nil)
        #expect(payload.imageURL == "https://example.com/new-image.jpg")
    }

    @Test func successfulEditReplacesImageAndDeletesOnlyPreviousAsset() async throws {
        let oldURL = try #require(URL(string: "https://firebasestorage.googleapis.com/old.jpg"))
        let newURL = try #require(URL(string: "https://firebasestorage.googleapis.com/new.jpg"))
        let repository = RecordingBannerRepository()
        let images = RecordingBannerImageService(uploadedURL: newURL)
        let viewModel = FeaturedBannerEditorViewModel(
            repository: repository,
            mode: .edit(makeBanner(title: "Old", subtitle: "Old subtitle", imageURL: oldURL.absoluteString)),
            imageUploadService: images
        )

        viewModel.title = ""
        viewModel.subtitle = ""
        viewModel.setSelectedImageData(Data([0x01]))

        let didSave = await viewModel.save(updatedBy: "owner-id")

        #expect(didSave)
        let updated = try #require(repository.updatedBanner)
        #expect(updated.title.isEmpty)
        #expect(updated.subtitle == nil)
        #expect(updated.imageURL == newURL.absoluteString)
        #expect(images.deletedURLs == [oldURL])
    }

    @Test func failedEditDeletesNewUploadAndKeepsPreviousAsset() async throws {
        let oldURL = try #require(URL(string: "https://firebasestorage.googleapis.com/old.jpg"))
        let newURL = try #require(URL(string: "https://firebasestorage.googleapis.com/new.jpg"))
        let repository = RecordingBannerRepository()
        repository.updateError = .permissionDenied
        let images = RecordingBannerImageService(uploadedURL: newURL)
        let viewModel = FeaturedBannerEditorViewModel(
            repository: repository,
            mode: .edit(makeBanner(title: "Old", subtitle: "Old subtitle", imageURL: oldURL.absoluteString)),
            imageUploadService: images
        )

        viewModel.setSelectedImageData(Data([0x02]))

        let didSave = await viewModel.save(updatedBy: "owner-id")

        #expect(didSave == false)
        #expect(images.deletedURLs == [newURL])
        #expect(viewModel.errorMessage == AppStrings.FeaturedEditor.savePermissionError)
    }

    private func makeBanner(
        title: String,
        subtitle: String?,
        imageURL: String
    ) -> FeaturedBanner {
        FeaturedBanner(
            id: "banner-1",
            internalName: "Campaign",
            title: title,
            subtitle: subtitle,
            imageURL: imageURL,
            visibleSections: [.home],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            createdBy: "original-owner"
        )
    }
}
