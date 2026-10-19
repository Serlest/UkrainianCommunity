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
        id: "audit-banner", title: "Banner audit", actionType: .externalURL,
        externalURL: "https://example.com", visibleSections: [.home],
        createdAt: Date(), updatedAt: Date(), createdBy: "fixture"
    )
    var body: some View {
        ScrollView {
            VStack {
                Picker("Region", selection: $region) {
                    Text("Austria").tag(AustrianFederalState?.none)
                    Text("Tirol").tag(Optional(AustrianFederalState.tirol))
                    Text("Wien").tag(Optional(AustrianFederalState.wien))
                }.pickerStyle(.segmented)
                FeaturedBannerCarouselView(banners: [banner], section: .home,
                    isActive: !covered, selectedFederalState: region,
                    viewportFrame: viewport, onBannerTap: { _ in }) { measurement in
                        if measurement.kind == .impression { impressions += 1 } else { clicks += 1 }
                        regionValue = measurement.displayRegion ?? "unknown"
                    }
                Text("\(impressions):\(clicks):\(regionValue)")
                    .accessibilityIdentifier("bannerAudit.counts")
                Button("Cover") { covered = true }
                Spacer().frame(height: 1200)
            }.padding()
        }
        .featuredBannerViewport($viewport)
        .sheet(isPresented: $covered) { Text("Covered") }
    }
}

private struct BannerReportAuditRepository: BannerMeasurementReportRepository {
    func fetch(period: AnalyticsPeriod) async throws -> BannerMeasurementReport {
        let today = FirestoreBannerMeasurementReportRepository.utcDayRange(period: .today, now: Date()).1
        return BannerMeasurementReport(period: period, counts: [
            .init(day: today, bannerID: "serlest", section: .home, impressions: 1200, clicks: 47, displayRegion: "tirol"),
            .init(day: today, bannerID: "serlest", section: .events, impressions: 680, clicks: 31, displayRegion: "wien"),
            .init(day: today, bannerID: "uac", section: .directory, impressions: 420, clicks: 16, displayRegion: "allAustria"),
            .init(day: today, bannerID: "uac", section: .home, impressions: 100, clicks: 3),
        ])
    }
}
struct BannerReportAuditHarness: View {
    var body: some View {
        NavigationStack {
            BannerMeasurementReportView(repository: BannerReportAuditRepository(),
                bannerRepository: MockFeaturedBannerRepository(banners: []), initialPeriod: .sevenDays)
                .environment(\.locale, LocalizationStore.locale)
                .preferredColorScheme(AppAppearance.stored.colorScheme)
        }
    }
}
#endif
