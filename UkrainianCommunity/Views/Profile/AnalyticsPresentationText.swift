import Foundation

enum AnalyticsPresentationText {
    static var utcExplanation: String {
        LocalizationStore.language.rawValue == "de"
            ? "Banner: Kalendertage in UTC. Die übrigen Auswertungen verwenden Wiener Zeit. Zusammenfassungen werden alle 5 Minuten aktualisiert."
            : "Банери: календарні дні за UTC. Решта аналітики — за часом Відня. Зведення оновлюються кожні 5 хвилин."
    }
    static func bannerPeriod(_ period: AnalyticsPeriod) -> String { "\(period.analyticsTitle) · UTC" }
    static var viennaTime: String {
        LocalizationStore.language.rawValue == "de" ? "Zeitzone: Wien" : "Часовий пояс: Відень"
    }
}
