import Foundation

enum AccessibilityGuides {
    private static let pass = DirectorySource(name: "Sozialministeriumservice · Behindertenpass", url: "https://www.sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Behindertenpass_und_Parkausweis/Behindertenpass/Behindertenpass.de.html")
    private static let entries = DirectorySource(name: "Sozialministeriumservice · Zusatzeintragungen", url: "https://www.sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Behindertenpass_und_Parkausweis/Behindertenpass/zusatzeintragungen/zusatzeintragungen.de.html")
    private static let parking = DirectorySource(name: "Sozialministeriumservice · Parkausweis", url: "https://sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Behindertenpass_und_Parkausweis/Parkausweis/Parkausweis.de.html")
    private static let fund = DirectorySource(name: "Sozialministeriumservice · Unterstützungsfonds", url: "https://sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Finanzielle_Unterstuetzung/Sonstige_finanzielle_Vorteile/Unterstuetzungsfonds/Unterstuetzungsfonds.de.html")
    private static let mobility = DirectorySource(name: "ÖBB · Barrierefrei reisen", url: "https://www.oebb.at/de/reiseplanung-services/barrierefrei-reisen")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "disability": return disability
        case "accessible-services": return services
        case "assistive-devices": return devices
        default: return nil
        }
    }

    private static let disability = DirectoryGuide(
        cardSummary: .init(ukrainian: "Behindertenpass, підтвердження інвалідності й пільги", german: "Behindertenpass, Feststellung und mögliche Vorteile"),
        introduction: .init(ukrainian: "Іноземний документ про інвалідність не замінює автоматично австрійський Behindertenpass. Право та ступінь оцінює австрійська служба.", german: "Ein ausländischer Behindertenausweis ersetzt den österreichischen Behindertenpass nicht automatisch. Anspruch und Grad prüft die österreichische Stelle."),
        sections: [
            .init("eligibility", "person.crop.rectangle", "Перевірте право", "Anspruch prüfen", "Для Behindertenpass зазвичай потрібен ступінь інвалідності щонайменше 50 % та проживання або звичайне перебування в Австрії. Подайте заяву до земельного відділення Sozialministeriumservice; додайте медичні висновки, документи про особу та доступні переклади. Сама подача й видача посвідчення безплатні.", "Für den Behindertenpass sind grundsätzlich mindestens 50 % Grad der Behinderung und Wohnsitz oder gewöhnlicher Aufenthalt in Österreich nötig. Antrag bei Landesstelle des Sozialministeriumservice mit Befunden, Ausweis und verfügbaren Übersetzungen stellen. Antrag und Ausstellung sind gebührenfrei.", source: pass),
            .init("decision", "doc.text.magnifyingglass", "Отримайте рішення й перевірте записи", "Bescheid und Eintragungen prüfen", "Служба може провести медичну оцінку. Після рішення звірте ступінь, строк дії та потрібні додаткові записи: неможливість користуватися громадським транспортом, супровідна особа, знижка на проїзд. Ці записи вимагають окремих умов і не виникають автоматично.", "Es kann eine ärztliche Begutachtung geben. Nach Entscheidung Grad, Gültigkeit und benötigte Zusatzeintragungen prüfen: Unzumutbarkeit öffentlicher Verkehrsmittel, Begleitperson, Fahrpreisermäßigung. Dafür gelten eigene Voraussetzungen; Einträge entstehen nicht automatisch.", source: entries),
            .init("use", "checkmark.shield", "Використовуйте документ правильно", "Pass richtig nutzen", "Behindertenpass підтверджує інвалідність, але сам по собі не є Parkausweis і не дає будь-якої пільги без перевірки її умов. Для конкретної знижки чи послуги запитайте організатора, який саме запис або інший доказ потрібний.", "Behindertenpass bestätigt die Behinderung, ist aber nicht selbst Parkausweis und gewährt nicht jede Vergünstigung ohne deren Voraussetzungen. Beim jeweiligen Anbieter nach nötigem Eintrag oder Nachweis fragen.", source: pass)
        ], sources: [pass, entries]
    )

    private static let services = DirectoryGuide(
        cardSummary: .init(ukrainian: "Доступний транспорт, супровід і паркування", german: "Barrierefreie Wege, Begleitung und Parken"),
        introduction: .init(ukrainian: "Плануйте потрібну допомогу заздалегідь: ліфт, посадку, місце для візка та супровід потрібно перевіряти на конкретному маршруті.", german: "Benötigte Hilfe rechtzeitig planen: Lift, Einstieg, Rollstuhlplatz und Begleitung für die konkrete Strecke prüfen."),
        sections: [
            .init("trip", "tram", "Підготуйте поїздку", "Reise vorbereiten", "У ÖBB перевірте доступність станцій і поїзда, способи замовлення допомоги та актуальний строк попередження. Повідомте маршрут, дату, тип візка й необхідну підтримку; отримайте підтвердження. Для місцевого транспорту звірте дані в регіонального перевізника.", "Bei ÖBB Bahnhof und Zug, Anmeldung der Hilfe und aktuelle Vorlaufzeit prüfen. Strecke, Datum, Rollstuhltyp und Hilfe nennen; Bestätigung einholen. Für Nahverkehr beim regionalen Betreiber nachsehen.", source: mobility),
            .init("parking", "parkingsign.circle", "Паркування", "Parkausweis", "Parkausweis за §29b StVO видає Sozialministeriumservice без плати за наявності Behindertenpass із відповідним записом про неможливість користуватися транспортом або сліпоту. Подайте окрему заяву; не користуйтеся місцем для осіб з інвалідністю лише на підставі іноземного посвідчення без перевірки правил.", "Den kostenlosen Parkausweis nach §29b StVO stellt das Sozialministeriumservice bei Behindertenpass mit einschlägigem Eintrag zur Unzumutbarkeit öffentlicher Verkehrsmittel oder Blindheit aus. Separat beantragen; fremden Ausweis nicht ohne Prüfung der Regeln als Parkberechtigung annehmen.", source: parking),
            .init("access", "building.2", "Послуга недоступна?", "Dienst nicht zugänglich?", "Перед відвідуванням запитайте про безбар’єрний вхід, переклад жестовою мовою, доступний формат документів і можливу альтернативу. Опишіть конкретну перешкоду установі письмово й збережіть відповідь. За потреби зверніться по консультацію до Sozialministeriumservice.", "Vor Besuch nach stufenlosem Eingang, Gebärdensprachdolmetschung, zugänglichen Dokumenten und Alternativen fragen. Konkrete Barriere schriftlich melden und Antwort sichern. Bei Bedarf Sozialministeriumservice um Beratung bitten.", source: pass)
        ], sources: [mobility, parking, pass]
    )

    private static let devices = DirectoryGuide(
        cardSummary: .init(ukrainian: "Кому подати заявку на допоміжний засіб і коли не купувати завчасно", german: "Hilfsmittel finanzieren und vor Kauf klären"),
        introduction: .init(ukrainian: "Оплата візка, слухового, комунікаційного чи побутового засобу залежить від медичної потреби, страхування та програми фінансування.", german: "Finanzierung von Rollstuhl, Hör-, Kommunikations- oder Alltagshilfe hängt von Bedarf, Versicherung und Förderweg ab."),
        sections: [
            .init("medical", "cross.case", "Опис потреби", "Bedarf dokumentieren", "Попросіть лікаря або терапевта описати, який засіб потрібний, для чого й на який строк. Зберіть медичні висновки та кошторис. Спершу зверніться до свого страхування щодо рецепта, погодження, власної доплати й постачальника.", "Ärztin oder Therapeut soll Bedarf, Zweck und Dauer dokumentieren. Befunde und Kostenvoranschlag sammeln. Zuerst bei Krankenversicherung Rezept, Bewilligung, Selbstbehalt und Vertragspartner klären.", source: fund),
            .init("fund", "eurosign.circle", "Додаткове фінансування", "Weitere Förderung", "Якщо страхування не покриває витрати, перевірте земельну допомогу та Unterstützungsfonds Sozialministeriumservice. Фонд може підтримати комунікаційні засоби, адаптацію житла й мобільність у соціальній скруті, але немає автоматичного права на виплату. Заяву зазвичай подають до реалізації витрат.", "Falls Versicherung nicht zahlt, Landesförderung und Unterstützungsfonds des Sozialministeriumservice prüfen. Dieser kann bei sozialer Not Kommunikationshilfen, Wohnungsanpassung und Mobilität unterstützen, ohne automatischen Rechtsanspruch. Antrag grundsätzlich vor Durchführung stellen.", source: fund),
            .init("order", "checklist", "Послідовність дій", "Reihenfolge", "1. Медичний висновок. 2. Письмовий кошторис. 3. Запит до страхування та землі. 4. За потреби заявка до фонду. 5. Лише після з’ясування оплати замовлення. Візьміть письмове рішення й умови ремонту/повернення.", "1. Befund. 2. Schriftlicher Kostenvoranschlag. 3. Anfrage bei Versicherung und Land. 4. Gegebenenfalls Fondsantrag. 5. Erst nach Klärung der Finanzierung bestellen. Schriftliche Entscheidung und Reparatur-/Rückgaberegeln sichern.", source: fund)
        ], sources: [pass, fund]
    )
}
