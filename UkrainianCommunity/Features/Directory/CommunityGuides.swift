import Foundation

enum CommunityGuides {
    private static let authoritySearch = DirectorySource(name: "oesterreich.gv.at · Behördensuche", url: "https://www.oesterreich.gv.at/de/orgsearch")
    private static let centers = DirectorySource(name: "ÖIF · Standorte in Österreich", url: "https://www.integrationsfonds.at/der-oeif/standorte/uebersicht-standorte/")
    private static let ukraine = DirectorySource(name: "ÖIF · Ukraine", url: "https://www.integrationsfonds.at/ukraine/")
    private static let volunteering = DirectorySource(name: "Freiwilligenweb · Freiwilligenzentren", url: "https://www.freiwilligenweb.at/nuetzliches/freiwilligenzentren/")
    private static let rights = DirectorySource(name: "Freiwilligenweb · Rechtliche Rahmenbedingungen", url: "https://www.freiwilligenweb.at/freiwilliges-engagement/rechtliche-rahmenbedingungen/")
    private static let volunteerRecord = DirectorySource(name: "Freiwilligenweb · Freiwilligen-Nachweis", url: "https://www.freiwilligenweb.at/freiwilliges-engagement/freiwilligen-nachweis/")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "local-services": return localServices
        case "community": return community
        case "volunteering": return volunteeringGuide
        default: return nil
        }
    }

    private static let localServices = DirectoryGuide(
        cardSummary: .init(ukrainian: "Контакти громади, землі й інтеграційного центру", german: "Gemeinde, Land und Integrationszentrum finden"),
        introduction: .init(ukrainian: "Більшість побутових послуг прив’язані до адреси. Почніть із Gemeinde або Magistrat та інтеграційного центру своєї землі.", german: "Viele Alltagsangebote hängen vom Wohnort ab. Beginnen Sie bei Gemeinde oder Magistrat und dem Integrationszentrum Ihres Landes."),
        sections: [
            .init("locate", "mappin.and.ellipse", "Визначте місцеву установу", "Zuständige Stelle finden", "Випишіть вашу Gemeinde, Bezirk і Bundesland з Meldezettel. За питаннями адреси, школи, догляду, місцевих пільг і відходів зверніться до Bürgerservice громади; компетенція та правила можуть відрізнятися. Попросіть письмову назву відповідального відділу та список документів.", "Gemeinde, Bezirk und Bundesland vom Meldezettel notieren. Für Wohnsitz, Schule, Betreuung, lokale Leistungen und Abfall beim Bürgerservice der Gemeinde fragen; Zuständigkeit und Regeln unterscheiden sich. Zuständige Abteilung und Unterlagen schriftlich bestätigen lassen.", source: authoritySearch),
            .init("integration", "person.2.badge.gearshape", "Зверніться до ÖIF", "ÖIF kontaktieren", "ÖIF має інтеграційні центри в усіх дев’яти землях. На офіційній сторінці знайдіть актуальну адресу й запис; центральна лінія 050 46 80. Уточніть консультацію щодо мови, курсів, інтеграції та доступних програм саме для вашого статусу.", "Der ÖIF hat Integrationszentren in allen neun Ländern. Aktuelle Adresse und Termin auf der offiziellen Seite suchen; zentrale Hotline 050 46 80. Beratung zu Sprache, Kursen, Integration und Angeboten für den eigenen Status erfragen.", phoneNumber: "050 46 80", source: centers),
            .init("prepare", "checklist", "Підготуйте звернення", "Termin vorbereiten", "Запишіть одне конкретне питання, номер справи, адресу, статус перебування та попередні листи. Якщо установа не відповідає, попросіть письмовий контакт або іншу компетентну установу; зберігайте дату й ім’я співрозмовника.", "Konkrete Frage, Geschäftszahl, Adresse, Aufenthaltsstatus und frühere Schreiben bereithalten. Wenn die Stelle nicht zuständig ist, schriftlichen Kontakt der zuständigen Stelle erfragen; Datum und Ansprechperson notieren.", source: ukraine)
        ], sources: [authoritySearch, centers, ukraine]
    )

    private static let community = DirectoryGuide(
        cardSummary: .init(ukrainian: "Курси, зустрічі й безпечні місцеві контакти", german: "Kurse, Begegnung und verlässliche lokale Kontakte"),
        introduction: .init(ukrainian: "Спільнота допомагає знайти людей та орієнтацію, але чутливі правові й медичні відповіді перевіряйте в компетентній установі.", german: "Gemeinschaft schafft Kontakte und Orientierung; sensible Rechts- und Gesundheitsfragen bei zuständigen Stellen prüfen."),
        sections: [
            .init("meet", "person.3", "Знайдіть події й курси", "Angebote finden", "Запитайте в ÖIF-центрі, Gemeinde, бібліотеці або місцевому Verein про відкриті зустрічі, мовні тандеми, сімейні та спортивні групи. Уточніть вартість, реєстрацію, доступність і мову до відвідування.", "Bei ÖIF-Zentrum, Gemeinde, Bibliothek oder örtlichem Verein nach offenen Treffen, Sprachtandems, Familien- und Sportgruppen fragen. Kosten, Anmeldung, Barrierefreiheit und Sprache vor Besuch klären.", source: centers),
            .init("verify", "checkmark.shield", "Перевірте організатора", "Veranstalter prüfen", "Офіційні консультації ÖIF знаходьте лише через його сайт. Для приватних груп перевіряйте адресу, ім’я організатора та умови участі. Нікому в чаті не надсилайте фото паспорта, банківські дані або гроші за обіцянку роботи чи житла.", "Offizielle ÖIF-Beratung nur über dessen Website finden. Bei privaten Gruppen Anschrift, Veranstalter und Teilnahmebedingungen prüfen. Passfoto, Bankdaten oder Geld für versprochene Arbeit oder Wohnung nicht in Chats senden.", source: ukraine),
            .init("belong", "bubble.left.and.bubble.right", "Знайдіть підтримку за потребою", "Passende Unterstützung suchen", "Якщо потрібна допомога з адаптацією, мовою чи контактом з місцевими службами, опишіть запит інтеграційному центру й попросіть актуальну пропозицію у своїй землі. При загрозі безпеці використовуйте екстрені контакти, а не груповий чат.", "Für Orientierung, Sprache oder örtliche Kontakte Bedarf dem Integrationszentrum schildern und aktuelles Landesangebot erfragen. Bei akuter Gefahr Notruf statt Gruppenchat nutzen.", source: centers)
        ], sources: [centers, ukraine]
    )

    private static let volunteeringGuide = DirectoryGuide(
        cardSummary: .init(ukrainian: "Як знайти волонтерство й перевірити умови", german: "Freiwilligenarbeit finden und Rahmen klären"),
        introduction: .init(ukrainian: "Волонтерство може дати досвід і контакти. Воно не повинно приховувати неоплачувану звичайну роботу.", german: "Ehrenamt kann Erfahrung und Kontakte bringen. Es darf reguläre unbezahlte Arbeit nicht verdecken."),
        sections: [
            .init("find", "hand.raised", "Знайдіть перевірене місце", "Passende Stelle finden", "Офіційний Freiwilligenweb перелічує регіональні Freiwilligenzentren, які допомагають обрати діяльність. Розкажіть про мову, час, навички та обмеження; попросіть опис завдань, ім’я відповідальної особи та адресу.", "Das Freiwilligenweb listet regionale Freiwilligenzentren, die bei der Auswahl helfen. Sprache, Zeit, Fähigkeiten und Grenzen nennen; Aufgabenbeschreibung, Kontaktperson und Ort erfragen.", source: volunteering),
            .init("conditions", "doc.text", "Уточніть умови й захист", "Bedingungen und Schutz klären", "Перед початком письмово з’ясуйте години, навчання, відшкодування витрат, страхування від нещасних випадків і відповідальність. Захист залежить від організації та форми участі; не припускайте, що кожна добровільна дія автоматично застрахована.", "Vor Beginn Stunden, Einschulung, Auslagenersatz, Unfall- und Haftpflichtschutz schriftlich klären. Schutz hängt von Organisation und Form des Engagements ab; nicht jede freiwillige Tätigkeit ist automatisch versichert.", source: rights),
            .init("record", "checkmark.seal", "Збережіть підтвердження досвіду", "Erfahrung nachweisen", "Після початку попросіть організацію вести облік завдань і годин. На Freiwilligenweb є паперовий і цифровий Freiwilligenpass та підтвердження навичок, які заповнюють разом волонтер і організація. Такий документ може допомогти при заявці на роботу, але не замінює професійного допуску чи диплома.", "Nach Beginn Tätigkeiten und Stunden mit der Organisation dokumentieren. Freiwilligenweb bietet papiergebundenen und digitalen Freiwilligenpass sowie Kompetenznachweis, die Freiwillige und Organisation gemeinsam erstellen. Das kann Bewerbungen unterstützen, ersetzt aber keine Berufszulassung oder einen Abschluss.", source: volunteerRecord),
            .init("rights", "person.crop.rectangle", "Відрізняйте від роботи", "Von Beschäftigung abgrenzen", "Якщо є фіксовані зміни, вказівки керівника й діяльність замість оплачуваної посади, попросіть пояснити правовий статус. Для роботи та виплат перевірте правила у відповідних розділах; за сумніву зверніться до Arbeiterkammer.", "Bei festen Schichten, Weisungen und Ersatz einer bezahlten Stelle den rechtlichen Status erklären lassen. Für Arbeit und Leistungen die jeweiligen Regeln prüfen; im Zweifel Arbeiterkammer kontaktieren.", source: rights)
        ], sources: [volunteering, rights, volunteerRecord]
    )
}
