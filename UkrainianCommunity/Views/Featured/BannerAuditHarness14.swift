#if DEBUG && targetEnvironment(simulator)
import SwiftUI

struct BannerAuditHarness14: View {
    @State private var banners = Self.fixtures()
    @State private var repository = MockFeaturedBannerRepository(banners: fixtures())
    @State private var viewport = CGRect.zero
    @State private var events: [FeaturedBannerMeasurement] = []
    @State private var active = true
    static func fixtures() -> [FeaturedBanner] {
        (1...3).map { n in
            FeaturedBanner(id:"banner14-\(n)",internalName:"Campaign \(n)",
                localizations:["uk":.init(title:"Зустріч нашої громади \(n)",subtitle:"Важливі події поруч із вами"),"de":.init(title:"Ein Treffen unserer Gemeinschaft \(n)",subtitle:"Wichtige Veranstaltungen in Ihrer Nähe")],
                title:"Зустріч нашої громади \(n)",imageURL:"https://example.com/banner.jpg",actionType:.externalURL,externalURL:"https://example.com/event",visibleSections:[.home,.events,.organizations,.directory],displayDurationSeconds:ProcessInfo.processInfo.environment["UITestBanner14Autoplay"] == "1" ? 3 : 12,
                createdAt:.now,updatedAt:.now,createdBy:"fixture",countdown:n == 1 ? .init(targetDate:Date().addingTimeInterval(2*86400+8*3600+32*60),label:"До зустрічі громади",germanLabel:"Bis zum Gemeinschaftstreffen",completion:.showStarted):nil)
        }
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
