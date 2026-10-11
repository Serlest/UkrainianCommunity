import Foundation

enum CareRegionalContent {
    private static let contacts: [AustrianFederalState: (phone: String, url: String)] = [
        .burgenland: ("05 09 44 1111", "https://www.soziale-dienste-burgenland.at/pflege-und-sozialberatung/pflegeberatung/"),
        .kaernten: ("0720 788 999", "https://www.ktn.gv.at/Themen-AZ/Uebersicht?subthema=180&thema=131"),
        .niederoesterreich: ("02742 9005 9095", "https://www.noe.gv.at/noe/Pflege/Pflegehotline.html"),
        .oberoesterreich: ("051 775 775", "https://www.pflegeinfo-ooe.at/"),
        .salzburg: ("0662 8042 3533", "https://www.salzburg.gv.at/pflegeberatung"),
        .steiermark: ("0800 500 176", "https://www.gesundheit.steiermark.at/cms/ziel/175114581/DE/"),
        .tirol: ("0800 400 160", "https://www.tirol.gv.at/gesundheit-vorsorge/pflege/beratungsstellen/"),
        .vorarlberg: ("05574 511 24105", "https://vorarlberg.at/-/hauskrankenpflege"),
        .wien: ("01 24 5 24", "https://www.fsw.at/p/pflege-betreuung")
    ]

    static func sections(for state: AustrianFederalState) -> [DirectoryGuideSection] {
        guard let contact = contacts[state] else { return [] }
        return [.init("regional-care", "phone", "Консультація з догляду у вашій землі", "Pflegeberatung im Bundesland",
                      "Для землі \(state.displayName) зателефонуйте за номером \(contact.phone) або відкрийте офіційну регіональну сторінку. Назвіть адресу, вік людини, потребу в медичному чи побутовому догляді та наявний ступінь Pflegegeld. Попросіть контакти постачальників, чергу, умови субсидії й ціну після неї. Години роботи перевірте перед дзвінком; для іншої землі виберіть її вручну.",
                      "Für \(state.displayName) unter \(contact.phone) anrufen oder die regionale Seite öffnen. Wohnort, Alter, Bedarf an medizinischer oder alltäglicher Hilfe und vorhandene Pflegegeldstufe nennen. Anbieter, Wartezeit, Förderbedingungen und Eigenbeitrag erfragen. Erreichbarkeit vor dem Anruf prüfen; für ein anderes Land dieses manuell wählen.",
                      phoneNumber: contact.phone,
                      source: DirectorySource(name: "\(state.displayName) · Pflegeberatung", url: contact.url))]
    }
}
