#if DEBUG
import SwiftUI

/// Local UI fixtures: no live writes or account consent are simulated.
struct BannerMeasurementAuditHarness: View {
    @State private var viewport = CGRect.zero
    @State private var impressions = 0
    @State private var clicks = 0
    @State private var region: AustrianFederalState? = .tirol
    @State private var covered = false
    @State private var regionValue = ""
    private let banner = FeaturedBanner(
        id: "audit-banner", title: AppStrings.BannerReport.title, actionType: .externalURL,
        externalURL: "https://example.com", visibleSections: [.home],
        createdAt: Date(), updatedAt: Date(), createdBy: "fixture"
    )
    var body: some View {
        ScrollView {
            VStack {
                Picker(AppStrings.BannerReport.byRegion, selection: $region) {
                    Text(AppStrings.BannerReport.allAustriaRegion).tag(AustrianFederalState?.none)
                    Text(AustrianFederalState.tirol.displayName).tag(Optional(AustrianFederalState.tirol))
                    Text(AustrianFederalState.wien.displayName).tag(Optional(AustrianFederalState.wien))
                }.pickerStyle(.segmented)
                FeaturedBannerCarouselView(banners: [banner], section: .home,
                    isActive: !covered, selectedFederalState: region,
                    viewportFrame: viewport, onBannerTap: { _ in }) { measurement in
                        if measurement.kind == .impression { impressions += 1 } else { clicks += 1 }
                        regionValue = measurement.displayRegion ?? "unknown"
                    }
                Text("\(impressions):\(clicks):\(regionValue)")
                    .accessibilityIdentifier("bannerAudit.counts")
                Button(AppStrings.Action.open) { covered = true }
                Spacer().frame(height: 1200)
            }.padding()
        }
        .featuredBannerViewport($viewport)
        .sheet(isPresented: $covered) { Text(AppStrings.BannerReport.title) }
    }
}

struct BannerReportAuditRepository: BannerMeasurementReportRepository {
    func fetch(period: AnalyticsPeriod) async throws -> BannerMeasurementReport {
        let today = FirestoreBannerMeasurementReportRepository.utcDayRange(period: .today, now: Date()).1
        return BannerMeasurementReport(period: period, counts: [
            .init(day: today, bannerID: "serlest", section: .home, impressions: 1200, clicks: 47, displayRegion: "tirol"),
            .init(day: today, bannerID: "serlest", section: .events, impressions: 680, clicks: 31, displayRegion: "wien"),
            .init(day: today, bannerID: "uac", section: .directory, impressions: 420, clicks: 16, displayRegion: "allAustria"),
            .init(day: today, bannerID: "uac", section: .home, impressions: 100, clicks: 3),
            .init(day: today, bannerID: "deleted-fixture", section: .home, impressions: 10, clicks: 2),
        ])
    }
}
struct BannerReportAuditHarness: View {
    static func banners() -> [FeaturedBanner] {
        ["serlest", "uac", "zero"].map { id in
            FeaturedBanner(id: id, internalName: id == "zero" ? "Zero clicks" : id.uppercased(),
                title: id.uppercased(), actionType: .externalURL, externalURL: "https://example.com",
                visibleSections: [.home], isActive: id != "uac", createdAt: .now, updatedAt: .now, createdBy: "fixture")
        }
    }
    var body: some View {
        NavigationStack {
            if ProcessInfo.processInfo.environment["UITestAnalytics15State"] != nil {
                OwnerAnalyticsAudit15Harness()
            } else if ProcessInfo.processInfo.environment["UITestBannerReportScope"] == "editor" {
                FeaturedBannerEditorView(repository: MockFeaturedBannerRepository(banners: Self.banners()),
                    mode: .edit(Self.banners()[0]), measurementRepository: BannerReportAuditRepository()) {}
            } else if ProcessInfo.processInfo.environment["UITestBannerReportScope"] == "management" {
                FeaturedBannerManagementView(repository: MockFeaturedBannerRepository(banners: Self.banners()),
                    newsRepository: MockNewsRepository(), eventRepository: MockEventRepository(),
                    organizationRepository: MockOrganizationRepository(), measurementRepository: BannerReportAuditRepository())
            } else if ProcessInfo.processInfo.environment["UITestBannerReportScope"] == "overview" {
                ProfileDestinationLayout(title: AppStrings.OwnerAnalytics.title, introSubtitle: AppStrings.OwnerAnalytics.subtitle) {
                    RegisteredUserCountCard(load: { 45 })
                    BannerAnalyticsOverviewSection(period: .sevenDays, repository: BannerReportAuditRepository())
                }
            } else {
                BannerMeasurementReportView(repository: BannerReportAuditRepository(),
                    bannerRepository: MockFeaturedBannerRepository(banners: Self.banners()), initialPeriod: .sevenDays)
            }
        }
        .environmentObject(AuthService.shared.authState)
        .environment(\.locale, LocalizationStore.locale)
        .preferredColorScheme(AppAppearance.stored.colorScheme)
    }
}
#endif
