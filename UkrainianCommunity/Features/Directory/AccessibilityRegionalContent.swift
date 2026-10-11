import Foundation

enum AccessibilityRegionalContent {
    private static let officePages: [AustrianFederalState: String] = [
        .burgenland: "Burgenland/Sozialministeriumservice___Landesstelle_Burgenland.de.html",
        .kaernten: "Kaernten/Sozialministeriumservice___Landesstelle_Kaernten.de.html",
        .niederoesterreich: "Niederoesterreich/Sozialministeriumservice___Landesstelle_Niederoesterreic.de.html",
        .oberoesterreich: "Oberoesterreich/Sozialministeriumservice___Landesstelle_Oberoesterreich.de.html",
        .salzburg: "Salzburg/Sozialministeriumservice___Landesstelle_Salzburg.de.html",
        .steiermark: "Steiermark/Sozialministeriumservice___Landesstelle_Steiermark.de.html",
        .tirol: "Tirol/Sozialministeriumservice___Landesstelle_Tirol.de.html",
        .vorarlberg: "Vorarlberg/Sozialministeriumservice___Landesstelle_Vorarlberg.de.html",
        .wien: "Wien/Sozialministeriumservice___Landesstelle_Wien.de.html"
    ]

    static func sections(for state: AustrianFederalState) -> [DirectoryGuideSection] {
        guard let page = officePages[state] else { return [] }
        let source = DirectorySource(
            name: "Sozialministeriumservice · Landesstelle \(state.displayName)",
            url: "https://www.sozialministeriumservice.gv.at/Ueber_uns/Sozialministeriumservice/Landesstellen/\(page)"
        )
        return [.init("regional-accessibility", "figure.roll", "Відділення у вашій землі", "Landesstelle in Ihrem Bundesland",
                      "Для землі \(state.displayName) відкрийте прямий контакт Sozialministeriumservice: тут приймають заявки на Behindertenpass, Parkausweis, додаткові записи та фонд підтримки. Звірте адресу, години консультацій і потребу в записі перед відвідуванням. Якщо фактично проживаєте в іншій землі, оберіть її вручну.",
                      "Für \(state.displayName) den direkten Kontakt der Landesstelle öffnen: Dort können Behindertenpass, Parkausweis, Zusatzeintragungen und Unterstützungsfonds beantragt werden. Adresse, Beratungszeiten und Terminbedarf vor Besuch prüfen. Bei tatsächlichem Aufenthalt in einem anderen Land dieses manuell wählen.", source: source)]
    }
}
