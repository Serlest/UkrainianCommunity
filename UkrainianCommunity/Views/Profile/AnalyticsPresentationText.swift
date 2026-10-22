import Foundation

enum AnalyticsPresentationText {
    static var utcExplanation: String {
        LocalizationStore.language.rawValue == "de"
            ? "Bannerdaten: UTC, übrige Statistik: Wiener Zeit. Aktualisierung alle 5 Minuten."
            : "Банери — за UTC, решта аналітики — за часом Відня. Оновлення зведень — кожні 5 хвилин."
    }
    static func bannerPeriod(_ period: AnalyticsPeriod) -> String { "\(period.analyticsTitle) · UTC" }
    static var viennaTime: String {
        LocalizationStore.language.rawValue == "de" ? "Zeitzone: Wien" : "Часовий пояс: Відень"
    }
}
