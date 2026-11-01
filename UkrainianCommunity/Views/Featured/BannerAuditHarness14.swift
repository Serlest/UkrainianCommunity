#if DEBUG && targetEnvironment(simulator)
import CryptoKit
import SwiftUI
import UIKit

struct BannerAuditHarness14: View {
    static let artwork: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 900)).image { context in
        let palette = ProcessInfo.processInfo.environment["UITestBanner14ArtworkPalette"] ?? "orange"
        let background: UIColor = palette == "light" ? .white : (palette == "dark" ? .black : .systemOrange)
        background.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        if palette == "orange" {
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 90))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 810, width: 1600, height: 90))
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 100), .foregroundColor: UIColor.black]
        ("1600 × 900" as NSString).draw(at: CGPoint(x: 360, y: 350), withAttributes: attributes)
    }
    @State private var banners = Self.fixtures()
    @State private var repository = MockFeaturedBannerRepository(banners: fixtures())
    @State private var viewport = CGRect.zero
    @State private var events: [FeaturedBannerMeasurement] = []
    @State private var active = true
    @State private var openedBannerID = ""
    static let videoFixture: FeaturedBannerVideoPresentation? = {
        guard ProcessInfo.processInfo.environment["UITestBannerVideoFixture"] == "1" else { return nil }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let input = ProcessInfo.processInfo.environment["UITestBannerVideoFixturePath"].map { URL(fileURLWithPath: $0) } ?? caches.appendingPathComponent("uac-banner-video-fixture.mp4")
        guard let data = try? Data(contentsOf: input) else { preconditionFailure("Missing isolated video fixture") }
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let directory = caches.appendingPathComponent("FeaturedBanners/video-v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(sha).appendingPathExtension("mp4"), options: .atomic)
        let id = SHA256.hash(data: Data(("banner14-1:" + sha).utf8)).map { String(format: "%02x", $0) }.joined()
        let hasAudio = ProcessInfo.processInfo.environment["UITestBannerVideoSilent"] != "1"
        return FeaturedBannerVideoPresentation(assetID: id,
            descriptor: .init(schemaVersion: 1, assetPath: "featuredBannerVideos/banner14-1/\(sha).mp4", sha256: sha, byteCount: data.count,
                width: 640, height: 360, durationSeconds: 2, framesPerSecond: 30, codec: "h264", hasAudio: hasAudio, audioCodec: hasAudio ? "aac" : nil),
            playbackURL: "https://firebasestorage.googleapis.com/v0/b/fixture.test/o/featuredBannerVideos%2Fbanner14-1%2F\(sha).mp4?alt=media&token=fixture")
    }()
    static func fixtures() -> [FeaturedBanner] {
        let duration: Int = ProcessInfo.processInfo.environment["UITestBanner14Autoplay"] == "1" ? 3 : 12
        let now = Date()
        let numbers = videoFixture != nil && ProcessInfo.processInfo.environment["UITestBannerVideoCarousel"] != "1" ? 1...1 : 1...3
        return numbers.map { number in
            fixture(number: number, now: now, duration: duration)
        }
    }

    private static func fixture(number: Int, now: Date, duration: Int) -> FeaturedBanner {
        let title = "Зустріч нашої громади \(number)"
        let localizations: [String: FeaturedBannerLocalizedContent] = [
            "uk": FeaturedBannerLocalizedContent(title: title, subtitle: "Важливі події поруч із вами"),
            "de": FeaturedBannerLocalizedContent(
                title: "Ein Treffen unserer Gemeinschaft \(number)",
                subtitle: "Wichtige Veranstaltungen in Ihrer Nähe"
            )
        ]
        let countdown: FeaturedBannerCountdown?
        if number == 1 {
            // Two days, eight hours and 32 minutes. A literal also avoids an
            // expensive numeric-overload search in the pinned CI compiler.
            let remainingSeconds: TimeInterval = 203_520
            countdown = FeaturedBannerCountdown(
                targetDate: now.addingTimeInterval(remainingSeconds),
                label: "До зустрічі громади",
                germanLabel: "Bis zum Gemeinschaftstreffen",
                completion: .showStarted
            )
        } else {
            countdown = nil
        }
        let sections: Set<FeaturedBannerVisibleSection> = [.home, .events, .organizations, .directory]
        var banner = FeaturedBanner(
            id: "banner14-\(number)", internalName: "Campaign \(number)",
            localizations: localizations, title: title,
            imageURL: "https://example.com/banner.jpg", actionType: .externalURL,
            externalURL: "https://example.com/event", visibleSections: sections,
            displayDurationSeconds: duration, createdAt: now, updatedAt: now,
            createdBy: "fixture", countdown: countdown
        )
        if number == 1, let videoFixture { banner.video = videoFixture; banner.videoPresentationVersion = 3 }
        return banner
    }
    var body: some View {
        NavigationStack {
            if ProcessInfo.processInfo.environment["UITestBanner14Scope"] == "startupCache" {
                BannerStartupAuditHarness()
            } else if ProcessInfo.processInfo.environment["UITestBanner14Scope"] == "management" {
                FeaturedBannerManagementView(repository:repository,newsRepository:MockNewsRepository(),eventRepository:MockEventRepository(),organizationRepository:MockOrganizationRepository(),measurementRepository:BannerReportAuditRepository())
            } else if ProcessInfo.processInfo.environment["UITestBanner14Scope"] == "video-editor" {
                FeaturedBannerEditorView(repository:repository,mode:.edit(Self.fixtures()[0]),newsRepository:MockNewsRepository(),eventRepository:MockEventRepository(),organizationRepository:MockOrganizationRepository(),videoAvailability:{ true }) {}
            } else if ProcessInfo.processInfo.environment["UITestBanner14Scope"] == "editor" {
                FeaturedBannerEditorView(repository:repository,mode:.edit(Self.fixtures()[0]),newsRepository:MockNewsRepository(),eventRepository:MockEventRepository(),organizationRepository:MockOrganizationRepository()) {}
            } else {
                ScrollView {
                    VStack(spacing:20) {
                        FeaturedBannerCarouselView(banners:banners,section:.home,isActive:active,selectedFederalState:.tirol,viewportFrame:viewport,onBannerTap:{ openedBannerID = $0.id }) { events.append($0) }
                        Text(openedBannerID).accessibilityIdentifier("bannerVideo.openedLink")
                        Text(events.map { "\($0.bannerID):\($0.kind.rawValue)" }.joined(separator:","))
                            .font(.system(size: 12)).accessibilityIdentifier("banner14.events")
                        Button(BannerCountdownStrings.text("pause")) { active.toggle() }.accessibilityIdentifier("banner14.pause")
                        Color.clear.containerRelativeFrame(.vertical) { height, _ in max(900, height * 2) }
                    }.padding()
                }.background(AppBackgroundView()).featuredBannerViewport($viewport)
            }
        }
        .environmentObject(AuthService.shared.authState)
        .environment(\.locale,LocalizationStore.locale)
        .transformEnvironment(\.dynamicTypeSize) { size in
            if ProcessInfo.processInfo.environment["UITestBannerVideoLargeText"] == "1" { size = .accessibility3 }
        }
        .preferredColorScheme(AppAppearance.stored.colorScheme)
    }
}
#endif
