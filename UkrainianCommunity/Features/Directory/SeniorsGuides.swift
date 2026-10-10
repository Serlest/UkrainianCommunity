import Foundation

enum SeniorsGuides {
    private static let pension = DirectorySource(name: "Pensionsversicherung · Versicherungszeiten", url: "https://www.pv.at/web/pension/ihr-weg-zur-pension/ueberpruefung-der-versicherungszeiten")
    private static let care = DirectorySource(name: "oesterreich.gv.at · Soziale Dienste", url: "https://www.oesterreich.gv.at/themen/pflege/soziale_dienste/Seite.1210200.html")
    private static let health = DirectorySource(name: "Gesundheitsportal · Bewegung im Alter", url: "https://www.gesundheit.gv.at/leben/altern/bewegung-senioren.html")
    private static let fall = DirectorySource(name: "Gesundheitsportal · Stürze im Alter", url: "https://www.gesundheit.gv.at/leben/altern/wohnen-im-alter/sicherheit.html")

    static func guide(for topicID: String) -> DirectoryGuide? {
        guard topicID == "seniors" else { return nil }
        return DirectoryGuide(
            cardSummary: .init(ukrainian: "Здоров’я, пенсія, спілкування й догляд у старшому віці", german: "Gesundheit, Pension, Kontakte und Betreuung im Alter"),
            introduction: .init(ukrainian: "Старший вік сам по собі не визначає право на виплати чи догляд. З’ясуйте потребу, страховий стаж, доходи та місцеві послуги окремо.", german: "Alter allein bestimmt weder Leistung noch Pflegeanspruch. Bedarf, Versicherungszeiten, Einkommen und örtliche Dienste getrennt prüfen."),
            sections: [
                .init("health", "heart.text.square", "Зберігайте самостійність", "Selbständigkeit erhalten", "Заплануйте з лікарем контроль ліків, зору, слуху та ризику падінь. Посильний рух, силові й координаційні вправи можуть підтримувати функції; обсяг узгодьте з лікарем при хворобах. Удома перевірте освітлення, килими та поручні.", "Mit Arzt Medikamente, Sehen, Hören und Sturzrisiko besprechen. Angepasste Bewegung, Kraft und Koordination unterstützen Funktionen; bei Krankheit Umfang ärztlich klären. Zu Hause Licht, Teppiche und Haltegriffe prüfen.", source: health),
                .init("pension", "eurosign.circle", "Перевірте дохід", "Einkommen prüfen", "До виходу на пенсію звірте австрійські страхові місяці в PV й повідомте про стаж в Україні чи інших країнах. Окремо перевірте медичне страхування та право на соціальну допомогу; іноземна пенсія може впливати на перевірку доходу. За індивідуальним розрахунком зверніться до PV.", "Vor Pensionsbeginn österreichische Versicherungszeiten bei PV prüfen und ukrainische sowie andere Auslandszeiten melden. Krankenversicherung und mögliche Sozialhilfe separat klären; ausländische Pension kann bei Einkommensprüfung zählen. Individuelle Berechnung bei PV erfragen.", source: pension),
                .init("support", "person.2", "Організуйте допомогу", "Hilfe organisieren", "Якщо важко з покупками, приготуванням їжі чи гігієною, у громаді або Bezirksverwaltungsbehörde запитайте про мобільні служби й денний центр. Узгодьте з близькими контакт на випадок хвороби, список ліків і доступ до важливих документів. За значного догляду перевірте розділ Pflegegeld.", "Bei Schwierigkeiten mit Einkauf, Mahlzeiten oder Hygiene Gemeinde oder Bezirksverwaltungsbehörde nach mobilen Diensten und Tageszentrum fragen. Mit Vertrauenspersonen Krankheitskontakt, Medikamentenliste und Zugang zu wichtigen Dokumenten klären. Bei höherem Pflegebedarf Pflegegeld prüfen.", source: care),
                .init("contacts", "person.3", "Уникайте ізоляції", "Kontakte pflegen", "Запитайте у Gemeinde, бібліотеці, клубі чи сусідському центрі про зустрічі й активності для старших людей. Перед участю перевірте доступність і вартість. Якщо людина в кризі або не може подбати про себе, потрібна медична або соціальна оцінка, а не лише зустрічі.", "Bei Gemeinde, Bibliothek, Verein oder Nachbarschaftszentrum nach Angeboten für Ältere fragen. Barrierefreiheit und Kosten vor Teilnahme klären. Bei Krise oder fehlender Selbstversorgung braucht es medizinische oder soziale Abklärung, nicht nur Begegnungsangebote.", source: care)
            ], sources: [pension, care, health, fall]
        )
    }
}
