import CoreGraphics
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
    @Test func adaptiveBannerProcessingPreservesPortraitAspectRatio() async throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 600,
            height: 1200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 1200))
        let sourceImage = try #require(context.makeImage())

        let processed = try await ImageProcessingService.process(
            cgImage: sourceImage,
            profile: .adaptiveBanner
        )

        #expect(processed.renderedWidth == 600)
        #expect(processed.renderedHeight == 1200)
        #expect(processed.renderedWidth / processed.renderedHeight == 0.5)
    }

    @Test func mutationPayloadOmitsClearedTextAndUsesNewImage() throws {
        let banner = makeBanner(
            title: "   ",
            subtitle: "",
            imageURL: "https://example.com/new-image.jpg"
        )

        let payload = try FeaturedBannerMutationPayload(banner: banner)

        #expect(payload.title == nil)
        #expect(payload.subtitle == nil)
        #expect(payload.localizations.isEmpty)
        #expect(payload.imageURL == "https://example.com/new-image.jpg")
    }

    @Test func localizedBannerUsesSelectedLanguageAndFallsBackToUkrainian() {
        let banner = makeBanner(
            title: "Заголовок",
            subtitle: "Підзаголовок",
            imageURL: "https://example.com/banner.jpg",
            localizations: [
                "uk": FeaturedBannerLocalizedContent(title: "Українською", subtitle: "Опис"),
                "de": FeaturedBannerLocalizedContent(title: "Auf Deutsch", subtitle: "Beschreibung"),
            ]
        )
        #expect(banner.localizations.resolved(for: .german)?.title == "Auf Deutsch")
        #expect(banner.localizations.resolved(for: .german)?.subtitle == "Beschreibung")
        #expect(banner.localizations.resolved(for: .ukrainian)?.title == "Українською")
        #expect(banner.localizations.resolved(for: .ukrainian)?.subtitle == "Опис")
    }

    @Test func legacyBannerStillProvidesLocalizedText() {
        let banner = makeBanner(
            title: "Legacy title",
            subtitle: "Legacy subtitle",
            imageURL: "https://example.com/banner.jpg"
        )

        #expect(banner.localizedTitle == "Legacy title")
        #expect(banner.localizedSubtitle == "Legacy subtitle")
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

    @Test func duplicatedBannerCreatesInactiveCopyWithoutDeletingSharedImage() async throws {
        let imageURL = try #require(URL(string: "https://firebasestorage.googleapis.com/source.jpg"))
        let repository = RecordingBannerRepository()
        let images = RecordingBannerImageService(uploadedURL: imageURL)
        let source = makeBanner(title: "Source", subtitle: "Reusable", imageURL: imageURL.absoluteString)
        let viewModel = FeaturedBannerEditorViewModel(
            repository: repository,
            mode: .duplicate(source),
            imageUploadService: images
        )

        let didSave = await viewModel.save(updatedBy: "owner-id")

        #expect(didSave)
        let copy = try #require(repository.updatedBanner)
        #expect(copy.id != source.id)
        #expect(copy.title == source.title)
        #expect(copy.localizations["uk"]?.title == source.title)
        #expect(copy.imageURL == source.imageURL)
        #expect(copy.isActive == false)
        #expect(images.deletedURLs.isEmpty)
    }

    private func makeBanner(
        title: String,
        subtitle: String?,
        imageURL: String,
        localizations: [String: FeaturedBannerLocalizedContent] = [:]
    ) -> FeaturedBanner {
        FeaturedBanner(
            id: "banner-1",
            internalName: "Campaign",
            localizations: localizations,
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
