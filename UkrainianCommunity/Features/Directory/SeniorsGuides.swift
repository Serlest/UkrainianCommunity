import Foundation

enum SeniorsGuides {
    static let homeSafety = DirectorySource(name: "Gesundheitsportal · Sicheres Wohnen im Alter", url: "https://www.gesundheit.gv.at/leben/altern/wohnen-im-alter/sicherheit.html")
    static let alarm = DirectorySource(name: "oesterreich.gv.at · Hausnotrufsysteme", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/sicherheit_fuer_senioren/1")
    static let medicines = DirectorySource(name: "Gesundheitsportal · Wechselwirkungen", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/medikamente/gebrauchsinformation.html")
    static let nutrition = DirectorySource(name: "Gesundheitsportal · Mangelernährung im Alter", url: "https://www.gesundheit.gv.at/leben/altern/ernaehrung-im-alter/mangelernaehrung-senioren.html")
    static let housing = DirectorySource(name: "pflege.gv.at · Alternative Wohnformen", url: "https://pflege.gv.at/de/pflege-in-alternativen-wohnformen")
    static let loneliness = DirectorySource(name: "Gesundheitsportal · Einsamkeit", url: "https://www.gesundheit.gv.at/leben/lebenswelt/soziale-netzwerke/einsamkeit-ursachen-bewaeltigung.html")
    static let digital = DirectorySource(name: "Digital Austria · Digital Überall", url: "https://www.digitalaustria.gv.at/kompetenzen/digital-ueberall-angebote.html")
    static let proxy = DirectorySource(name: "oesterreich.gv.at · Vorsorgevollmacht", url: "https://www.oesterreich.gv.at/de/themen/gesetze_und_recht/erwachsenenvertretung_und_vorsorgevollmacht/4")
    static let directive = DirectorySource(name: "oesterreich.gv.at · Patientenverfügung", url: "https://www.oesterreich.gv.at/de/themen/gesundheit/patientenrechte/3")
    static let representation = DirectorySource(name: "oesterreich.gv.at · Erwachsenenvertretung", url: "https://www.oesterreich.gv.at/de/themen/gesetze_und_recht/erwachsenenvertretung_und_vorsorgevollmacht")

    static func guide(for topicID: String) -> DirectoryGuide? {
        guard topicID == "seniors" else { return nil }
        return DirectoryGuide(
            cardSummary: .init(ukrainian: "Безпечне житло, здоров’я, спілкування й рішення наперед", german: "Sicher wohnen, gesund bleiben, Kontakte und Vorsorge"),
            introduction: .init(ukrainian: "Почніть із того, що людина хоче робити сама і де їй справді потрібна підтримка. Вік сам по собі не позбавляє права вирішувати за себе. За потреби професійного догляду відкрийте окрему категорію «Догляд».", german: "Beginnen Sie mit dem, was die Person selbst tun möchte, und wo sie tatsächlich Unterstützung braucht. Das Alter allein nimmt niemandem die Entscheidungsfähigkeit. Für professionelle Pflege gibt es den eigenen Bereich „Pflege“."),
            sections: everydaySections + planningSections,
            sources: [homeSafety, alarm, medicines, nutrition, housing, loneliness, digital, proxy, directive, representation]
        )
    }
}
