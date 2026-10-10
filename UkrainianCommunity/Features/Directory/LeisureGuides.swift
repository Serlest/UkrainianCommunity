import Foundation

enum LeisureGuides {
    private static let movement = DirectorySource(name: "Gesundheitsportal · Bewegungsempfehlungen", url: "https://www.gesundheit.gv.at/leben/bewegung/gesund-durch-sport.html")
    private static let activity = DirectorySource(name: "Gesundheitsportal · Bewegung im Alltag", url: "https://www.gesundheit.gv.at/leben/bewegung/gesunde-bewegung/alltag.html")
    private static let children = DirectorySource(name: "Gesundheitsportal · Kinder und Bewegung", url: "https://www.gesundheit.gv.at/leben/bewegung/gesunde-bewegung/kinder-bewegung.html")
    private static let centers = DirectorySource(name: "ÖIF · Integrationszentren", url: "https://www.integrationsfonds.at/der-oeif/standorte/uebersicht-standorte/")

    static func guide(for topicID: String) -> DirectoryGuide? {
        guard topicID == "leisure" else { return nil }
        return DirectoryGuide(
            cardSummary: .init(ukrainian: "Знайти спорт, культуру й відпочинок у своїй місцевості", german: "Sport, Kultur und Erholung am Wohnort finden"),
            introduction: .init(ukrainian: "Для дозвілля важливі не лише події, а й регулярні доступні місця поруч із домом.", german: "Für Freizeit zählen neben Veranstaltungen auch regelmäßige, erreichbare Angebote in Wohnortnähe."),
            sections: [
                .init("local", "mappin.circle", "Почніть поруч із домом", "Am Wohnort beginnen", "Запитайте Gemeinde, бібліотеку, школу, спортивний Verein або інтеграційний центр про відкриті заняття та місця зустрічі. Перед відвідуванням уточніть вік, вартість, мову, доступність, потрібне спорядження та реєстрацію. Розклад локальних подій змінюється — перевіряйте у організатора.", "Gemeinde, Bibliothek, Schule, Sportverein oder Integrationszentrum nach offenen Angeboten fragen. Alter, Kosten, Sprache, Barrierefreiheit, Ausrüstung und Anmeldung vorab klären. Lokale Termine ändern sich; beim Veranstalter prüfen.", source: centers),
                .init("move", "figure.walk", "Рух без зайвих витрат", "Bewegung ohne hohe Kosten", "Прогулянки, ходьба й велосипед можуть бути частиною здорової активності. Починайте посильно, поступово збільшуйте навантаження; при хронічній хворобі обговоріть межі з лікарем. Перевірте безпечність маршруту, погоду й правила місцевості.", "Spazieren, Gehen und Radfahren können gesunde Bewegung sein. Belastung angepasst beginnen und steigern; bei chronischer Erkrankung ärztlich abstimmen. Wegsicherheit, Wetter und örtliche Regeln prüfen.", source: activity),
                .init("children", "figure.child", "Для дітей і підлітків", "Für Kinder und Jugendliche", "Питайте в школі й громаді про групи за віком, пробні заняття та знижки. Перед початком перевірте відповідальну особу, страхування, дорогу додому й потреби дитини. Дітям потрібний рух відповідно до віку та можливостей, без примусу до надмірного навантаження.", "Schule und Gemeinde nach altersgerechten Gruppen, Schnupperstunden und Ermäßigungen fragen. Betreuungsperson, Versicherung, Heimweg und Bedarf des Kindes vorab klären. Bewegung soll alters- und fähigkeitsgerecht sein, ohne Überforderung.", source: children)
            ], sources: [movement, activity, children, centers]
        )
    }
}
