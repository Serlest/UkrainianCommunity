import Foundation

/// Regional entry points only for directory subjects that already have guides.
/// National rules remain in the guide; this catalog points to local offices.
enum DirectoryRegionalContent {
    private static let basicCarePhones: [AustrianFederalState: String] = [
        .burgenland: "02682 600-0", .kaernten: "050 536 13199",
        .niederoesterreich: "02742 9005 15000", .oberoesterreich: "0732 7720 15249",
        .salzburg: "0662 8042 5602", .steiermark: "0316 877 5458",
        .tirol: "0512 508 2592", .vorarlberg: "05574 511 24105"
    ]

    private static let citizenshipURLs: [AustrianFederalState: String] = [
        .burgenland: "https://www.burgenland.at/service/service-und-beratungsstellen/staatsbuergerschaft/",
        .kaernten: "https://www.ktn.gv.at/Verwaltung/Amt-der-Kaerntner-Landesregierung/Abteilung-1/Organisation?oid=2000082",
        .niederoesterreich: "https://www.noe.gv.at/noe/Persoenliche-Ausweise-Dokumente/Staatsbuergerschaft.html",
        .oberoesterreich: "https://www.land-oberoesterreich.gv.at/89565.htm",
        .salzburg: "https://www.salzburg.gv.at/themen/sicherheit/staatsbuergerschaft",
        .steiermark: "https://www.verwaltung.steiermark.at/cms/ziel/75773739/DE?kontakt=J",
        .tirol: "https://www.tirol.gv.at/gesellschaft-soziales/staatsbuergerschaft/",
        .vorarlberg: "https://vorarlberg.at/staatsb%C3%BCrgerschaft",
        .wien: "https://www.wien.gv.at/kontakt/ma35-referate-staatsbuergerschaft"
    ]

    private static let childWelfareURLs: [AustrianFederalState: String] = [
        .burgenland: "https://www.burgenland.at/verwaltung/landesverwaltung-im-ueberblick/gruppe-3/abteilung-6-soziales-und-pflege/hauptreferat-soziales/referat-kinder-und-jugendhilfe/",
        .kaernten: "https://www.ktn.gv.at/Service/Formulare-und-Leistungen/GS-L69",
        .niederoesterreich: "https://noe.gv.at/noe/Jugend/Kinder-_und_Jugendhilfe.html",
        .oberoesterreich: "https://www.land-oberoesterreich.gv.at/19992.htm",
        .salzburg: "https://www.salzburg.gv.at/dienststellen/abteilungen/20302",
        .steiermark: "https://www.verwaltung.steiermark.at/cms/ziel/75777334/DE/",
        .tirol: "https://www.tirol.gv.at/gesellschaft-soziales/inklusion-und-kinder-und-jugendhilfe/kinder-und-jugendhilfe/",
        .vorarlberg: "https://vorarlberg.at/-/kinder-und-jugendhilfe",
        .wien: "https://www.wien.gv.at/kontakt/ma11"
    ]

    static func applies(categoryID: String, topicID: String) -> Bool {
        switch categoryID {
        case "housing": HousingRegionalContent.applies(to: topicID)
        case "health": HealthRegionalContent.applies(to: topicID)
        case "mental-health": topicID == "crisis" || topicID == "counseling"
        case "insurance": topicID == "ukrainian-cover"
        case "social-support": ["benefits", "basic-support"].contains(topicID)
        case "community": topicID == "local-services"
        case "accessibility": ["disability", "assistive-devices"].contains(topicID)
        case "care": ["home-care", "care-services"].contains(topicID)
        case "seniors": topicID == "seniors"
        case "first-steps": topicID == "arrival"
        case "registration": ["housing-types", "protection-registration", "after-registration"].contains(topicID)
        case "residence": topicID == "temporary-protection"
        case "citizenship": ["overview", "documents", "application"].contains(topicID)
        case "safety": ["domestic-violence", "women", "children", "assault"].contains(topicID)
        default: false
        }
    }

    static func sections(categoryID: String, topicID: String, state: AustrianFederalState) -> [DirectoryGuideSection] {
        switch categoryID {
        case "housing": return HousingRegionalContent.sections(for: topicID, state: state)
        case "health": return HealthRegionalContent.sections(for: topicID, state: state)
        case "mental-health":
            return [.init("regional-mental-health", "heart.text.square", "Підтримка у вашій землі", "Hilfe in Ihrem Bundesland",
                          "На офіційній сторінці відкрийте служби землі \(state.displayName) й перевірте прямий номер та години роботи. При безпосередній небезпеці використовуйте 144; анонімна лінія 142 діє по всій Австрії.",
                          "Öffnen Sie auf der amtlichen Seite die Dienste für \(state.displayName) und prüfen Sie Nummer und Erreichbarkeit. Bei unmittelbarer Gefahr 144 wählen; die anonyme Nummer 142 gilt österreichweit.",
                          source: DirectorySource(name: "Gesundheitsportal · Krisendienste \(state.displayName)", url: "https://www.gesundheit.gv.at/leben/suizidpraevention/anlaufstellen/notrufnummern.html"))]
        case "insurance": return [basicCareSection(state)]
        case "social-support":
            if topicID == "basic-support" { return [basicCareSection(state)] }
            return [.init("regional-benefits", "building.columns", "Соціальна служба вашої землі", "Sozialstelle Ihres Bundeslandes",
                          "Для землі \(state.displayName) знайдіть компетентну Bezirksverwaltungsbehörde за адресою проживання. Перед поданням уточніть, чи ваш статус дає право на конкретну виплату, чи замість неї діє Grundversorgung, і попросіть перелік документів.",
                          "Für \(state.displayName) die Bezirksverwaltungsbehörde des Wohnorts suchen. Vor Antrag klären, ob Ihr Status Anspruch auf die konkrete Leistung eröffnet oder Grundversorgung einschlägig ist, und Unterlagenliste verlangen.",
                          source: DirectorySource(name: "oesterreich.gv.at · Sozialhilfeantrag", url: "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/4/Seite.1693912"))]
        case "community":
            return [.init("regional-integration", "person.2", "Інтеграційний центр вашої землі", "Integrationszentrum Ihres Bundeslandes",
                          "У списку ÖIF знайдіть центр землі \(state.displayName), перевірте адресу й запис. Загальна лінія 050 46 80 допоможе визначити відповідний центр.",
                          "In der ÖIF-Liste das Zentrum für \(state.displayName) suchen und Anschrift sowie Termin prüfen. Die Hotline 050 46 80 hilft bei der Zuordnung.",
                          phoneNumber: "050 46 80",
                          source: DirectorySource(name: "ÖIF · Standorte", url: "https://www.integrationsfonds.at/der-oeif/standorte/uebersicht-standorte/"))]
        case "accessibility":
            return [.init("regional-accessibility", "figure.roll", "Соціальне міністерство у вашій землі", "Sozialministeriumservice im Bundesland",
                          "На офіційній сторінці виберіть Landesstelle \(state.displayName): тут уточнюють Behindertenpass, додаткові записи й заявку до фонду підтримки. Перед відвідуванням перевірте години й доступність.",
                          "Auf der amtlichen Seite Landesstelle \(state.displayName) wählen: Dort Behindertenpass, Zusatzeintragungen und Unterstützungsfonds klären. Zeiten und Barrierefreiheit vor Besuch prüfen.",
                          source: DirectorySource(name: "Sozialministeriumservice · Landesstellen", url: "https://www.sozialministeriumservice.gv.at/Ueber_uns/Sozialministeriumservice/Landesstellen/Landesstellen_des_Sozialministeriumservice.de.html"))]
        case "care", "seniors":
            return [.init("regional-care", "house", "Догляд у вашій землі", "Pflege in Ihrem Bundesland",
                          "Для землі \(state.displayName) запитайте в Gemeinde, Bezirk або Magistrat про наявні мобільні служби, ціну після субсидії й місцеві заяви. Федеральна сторінка пояснює, хто відповідальний; конкретного постачальника перевіряйте за вашою адресою.",
                          "Für \(state.displayName) Gemeinde, Bezirk oder Magistrat nach mobilen Diensten, gefördertem Preis und örtlichem Antrag fragen. Die Bundesseite erklärt die Zuständigkeit; Anbieter am Wohnort prüfen.",
                          source: DirectorySource(name: "oesterreich.gv.at · Soziale Dienste", url: "https://www.oesterreich.gv.at/themen/pflege/soziale_dienste/Seite.1210200.html"))]
        case "first-steps", "registration":
            if topicID == "after-registration" { return [bfaSection(state)] }
            if topicID == "protection-registration" { return [policeRegistrationSection(state)] }
            return [basicCareSection(state)]
        case "residence":
            return [bfaSection(state), basicCareSection(state)]
        case "citizenship":
            guard let url = citizenshipURLs[state] else { return [] }
            return [.init("regional-citizenship", "building.columns", "Орган громадянства землі", "Staatsbürgerschaftsbehörde des Landes",
                          "Заяву розглядає земля вашого Hauptwohnsitz. Уточніть тут прийом, документи, оплату та зарахування періодів перебування до подання.",
                          "Zuständig ist das Bundesland Ihres Hauptwohnsitzes. Klären Sie hier Termin, Unterlagen, Gebühren und Anrechnung Ihrer Aufenthaltszeiten vor dem Antrag.",
                          source: DirectorySource(name: "\(state.displayName) · Staatsbürgerschaft", url: url))]
        case "safety":
            let url = "https://www.gewaltschutzzentrum.at/\(state.rawValue)/"
            let protection = DirectoryGuideSection("regional-protection", "hand.raised", "Центр захисту землі", "Gewaltschutzzentrum im Bundesland",
                          "Конфіденційна консультація для постраждалих від насильства; адреси та прямі телефони є на сайті центру. За безпосередньої небезпеки телефонуйте 133 або 112.",
                          "Vertrauliche Beratung für Gewaltbetroffene; Standorte und direkte Telefonnummern stehen auf der Website. Bei unmittelbarer Gefahr wählen Sie 133 oder 112.",
                          source: DirectorySource(name: "Gewaltschutzzentrum \(state.displayName)", url: url))
            guard topicID == "children", let childURL = childWelfareURLs[state] else { return [protection] }
            return [protection, .init("regional-children", "figure.child", "Захист дитини у вашій землі", "Kinder- und Jugendhilfe im Bundesland",
                                      "Якщо дитина потребує захисту, зверніться до Kinder- und Jugendhilfe землі або місцевої Bezirksverwaltungsbehörde. При гострій небезпеці — поліція 133; для дитини діє також анонімна лінія 147.",
                                      "Braucht ein Kind Schutz, kontaktieren Sie die Kinder- und Jugendhilfe des Landes oder die Bezirksverwaltungsbehörde. Bei akuter Gefahr Polizei 133; für Kinder gibt es auch die anonyme Hilfe 147.",
                                      source: DirectorySource(name: "\(state.displayName) · Kinder- und Jugendhilfe", url: childURL))]
        default: return []
        }
    }

    static func basicCareSection(_ state: AustrianFederalState) -> DirectoryGuideSection {
        DirectoryGuideSection("regional-basic-care", "house", "Базова допомога у землі", "Grundversorgung im Bundesland",
                              "BBU публікує актуальну таблицю органів усіх земель: там зазначено, куди подавати заяву при приватному й організованому проживанні. Номер нижче — контакт земельної служби; спершу перевірте порядок на сайті.",
                              "Die BBU veröffentlicht die Landesstellen und Antragswege für private und organisierte Unterkunft. Die Nummer unten gehört zur Landesstelle; prüfen Sie zuerst den aktuellen Ablauf auf der Website.",
                              phoneNumber: basicCarePhones[state],
                              source: DirectorySource(name: "BBU · Grundversorgung \(state.displayName)", url: "https://www.bbu.gv.at/ukraine-info-faq-deutsch"))
    }

    private static func policeRegistrationSection(_ state: AustrianFederalState) -> DirectoryGuideSection {
        DirectoryGuideSection("regional-registration", "checklist", "Пункт реєстрації поліції", "Polizeiliche Erfassungsstelle",
                              "На сторінці BMI знайдіть пункти у своїй землі, перевірте адресу, запис і години роботи. Поліцейська реєстрація для захисту відрізняється від Meldezettel і заяви на Grundversorgung.",
                              "Die BMI-Seite nennt die Erfassungsstellen Ihres Landes mit Anschrift, Termin und Zeiten. Polizeiliche Erfassung, Meldezettel und Antrag auf Grundversorgung sind getrennte Verfahren.",
                              source: DirectorySource(name: "BMI · Erfassungsstellen \(state.displayName)",
                                                      url: "https://www.bmi.gv.at/ukraine/erfassung_und_aufenthalt.html"))
    }

    private static func bfaSection(_ state: AustrianFederalState) -> DirectoryGuideSection {
        DirectoryGuideSection("regional-bfa", "person.text.rectangle", "Регіональне відділення BFA", "BFA-Regionaldirektion",
                              "Для посвідчення переміщеної особи й індивідуальної справи шукайте відділення BFA своєї землі в офіційному списку. Для запису на первинну реєстрацію потрібен пункт поліції — це інша служба.",
                              "Für Vertriebenenausweis und Einzelfall finden Sie die BFA-Regionaldirektion Ihres Landes in der amtlichen Liste. Die erste Erfassung erfolgt bei der Polizei, nicht beim BFA.",
                              source: DirectorySource(name: "BFA · \(state.displayName)", url: "https://www.bfa.gv.at/kontakt/"))
    }

}
