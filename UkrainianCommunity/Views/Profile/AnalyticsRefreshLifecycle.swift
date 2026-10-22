import SwiftUI

/// Polls the clock only while visible and active. Network work uses each model's
/// cache; midnight and foreground invalidate relative periods without a reload loop.
private struct AnalyticsRefreshLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let identity: String
    let refresh: () async -> Void
    private var dayKey: String {
        let now = Date()
        return AnalyticsFirestoreSchema.dailyDocumentID(for: now)
            + FirestoreBannerMeasurementReportRepository.utcDayRange(period: .today, now: now).0
    }
    func body(content: Content) -> some View {
        content.task(id: "\(scenePhase)|\(identity)") {
            guard scenePhase == .active else { return }
            await refresh()
            var day = dayKey
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard !Task.isCancelled else { return }
                if day != dayKey {
                    day = dayKey
                    await refresh()
                }
            }
        }
    }
}
extension View {
    func analyticsRefreshLifecycle(id: String = "", _ refresh: @escaping () async -> Void) -> some View {
        modifier(AnalyticsRefreshLifecycle(identity: id, refresh: refresh))
    }
}
