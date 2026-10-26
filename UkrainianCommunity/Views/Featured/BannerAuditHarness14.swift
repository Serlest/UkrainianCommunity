#if DEBUG && targetEnvironment(simulator)
import SwiftUI

struct BannerAuditHarness14: View {
    @State private var banners = Self.fixtures()
    @State private var repository = MockFeaturedBannerRepository(banners: fixtures())
    @State private var viewport = CGRect.zero
    @State private var events: [FeaturedBannerMeasurement] = []
    @State private var active = true
    static func fixtures() -> [FeaturedBanner] {
        let duration: Int = ProcessInfo.processInfo.environment["UITestBanner14Autoplay"] == "1" ? 3 : 12
        let now = Date()
        return (1...3).map { number in
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
            let remainingSeconds: TimeInterval = 2 * 86_400 + 8 * 3_600 + 32 * 60
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
        return FeaturedBanner(
            id: "banner14-\(number)", internalName: "Campaign \(number)",
            localizations: localizations, title: title,
            imageURL: "https://example.com/banner.jpg", actionType: .externalURL,
            externalURL: "https://example.com/event", visibleSections: sections,
            displayDurationSeconds: duration, createdAt: now, updatedAt: now,
            createdBy: "fixture", countdown: countdown
        )
    }
    var body: some View {
        NavigationStack {
            if ProcessInfo.processInfo.environment["UITestBanner14Scope"] == "management" {
                FeaturedBannerManagementView(repository:repository,newsRepository:MockNewsRepository(),eventRepository:MockEventRepository(),organizationRepository:MockOrganizationRepository(),measurementRepository:BannerReportAuditRepository())
            } else if ProcessInfo.processInfo.environment["UITestBanner14Scope"] == "editor" {
                FeaturedBannerEditorView(repository:repository,mode:.edit(Self.fixtures()[0]),newsRepository:MockNewsRepository(),eventRepository:MockEventRepository(),organizationRepository:MockOrganizationRepository()) {}
            } else {
                ScrollView {
                    VStack(spacing:20) {
                        FeaturedBannerCarouselView(banners:banners,section:.home,isActive:active,selectedFederalState:.tirol,viewportFrame:viewport,onBannerTap:{ _ in }) { events.append($0) }
                        Text(events.map { "\($0.bannerID):\($0.kind.rawValue)" }.joined(separator:","))
                            .font(.system(size: 12)).accessibilityIdentifier("banner14.events")
                        Button(BannerCountdownStrings.text("pause")) { active.toggle() }.accessibilityIdentifier("banner14.pause")
                        Spacer().frame(height:900)
                    }.padding()
                }.background(AppBackgroundView()).featuredBannerViewport($viewport)
            }
        }
        .environmentObject(AuthService.shared.authState)
        .environment(\.locale,LocalizationStore.locale)
        .preferredColorScheme(AppAppearance.stored.colorScheme)
    }
}
#endif
