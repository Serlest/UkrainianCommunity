import Foundation

enum AnalyticsPresentationText {
    private static func text(_ key: String, _ fallback: String) -> String {
        LocalizationStore.localizedString(key, defaultValue: fallback, table: "AnalyticsAudit")
    }
    static var refreshCadence: String { text("cadence", "Банери: UTC, оновлення кожні 5 хв. Загальні зведення за 7 і 30 днів та зведення користувачів: час Відня, оновлення щогодини. Час останніх даних указано біля звіту.") }
    static var periodNote: String { text("periodNote", "Час Відня. Сьогодні — неповний день; порівняння з усім учорашнім днем. 7 і 30 днів включають сьогодні та порівнюються з попереднім таким самим періодом.") }
    static var searchScope: String { text("searchScope", "Пошук у завантаженому звіті. За 7 і 30 днів у рейтингу показано до 20 матеріалів кожного типу; це не пошук у всьому архіві.") }
    static var emptyPeriod: String { text("emptyPeriod", "За цей період даних ще немає. Якщо активність була нещодавно, оновіть звіт після наступного погодинного оновлення.") }
    static var currentNote: String { text("currentNote", "Облікові записи зараз, незалежно від обраного періоду.") }
    static var utcExplanation: String { text("bannerCadence", "Банери — за UTC. Зведення оновлюються кожні 5 хвилин.") }
    static var currentTitle: String { text("currentTitle", "Облікові записи зараз") }
    static var todayComparison: String { text("todayComparison", "Сьогодні ще триває. Порівняння — з усім учорашнім днем.") }
    static func bannerPeriod(_ period: AnalyticsPeriod) -> String { "\(period.analyticsTitle) · UTC" }
    static var viennaTime: String {
        LocalizationStore.language.rawValue == "de" ? "Zeitzone: Wien" : "Часовий пояс: Відень"
    }
}
