import Foundation

enum FinanceGuides {
    static let bank = DirectorySource(name: "FMA · Basiskonto", url: "https://www.fma.gv.at/konto/basiskonto/")
    static let phishing = DirectorySource(name: "FMA · Phishing und Kontoschutz", url: "https://redenwiruebergeld.fma.gv.at/phishing/")
    static let taxDeadline = DirectorySource(name: "BMF · Verfahren und Fristen", url: "https://www.bmf.gv.at/themen/steuern/arbeitnehmerveranlagung/verfahren-arbeitnehmerinnenveranlagung/verfahren-beim-finanzamt.html")
    static let mandatoryTax = DirectorySource(name: "BMF · Pflichtveranlagung", url: "https://www.bmf.gv.at/public/informationen/pflichtveranlagung.html")
    static let taxExpenses = DirectorySource(name: "BMF · Werbungskosten und Belege", url: "https://www.bmf.gv.at/themen/steuern/arbeitnehmerveranlagung/was-kann-ich-geltend-machen/werbungskosten/werbungskosten-ueberblick.html")
    static let taxTreaty = DirectorySource(name: "BMF · Doppelbesteuerungsabkommen", url: "https://www.bmf.gv.at/themen/steuern/internationales-steuerrecht/doppelbesteuerungsabkommen/dba-liste.html")
    static let taxAppeal = DirectorySource(name: "BMF · Beschwerde gegen Bescheide", url: "https://www.bmf.gv.at/themen/steuern/fristen-verfahren/beschwerde-zahlungserleichterung-nachsicht.html")
    static let pension = DirectorySource(name: "Pensionsversicherung · Versicherungszeiten im Ausland", url: "https://www.pv.at/web/pension/ihr-weg-zur-pension/zwischenstaatliche-pensionsversicherung")
    static let pensionRecord = DirectorySource(name: "Pensionsversicherung · Versicherungszeiten prüfen", url: "https://www.pv.at/web/pension/ihr-weg-zur-pension/ueberpruefung-der-versicherungszeiten")
    static let pensionApplication = DirectorySource(name: "Pensionsversicherung · Pensionsantrag stellen", url: "https://www.pv.at/web/pension/ihr-weg-zur-pension/pensionsantrag-stellen")
    static let pensionLowIncome = DirectorySource(name: "oesterreich.gv.at · Geringfügige Beschäftigung", url: "https://www.oesterreich.gv.at/de/lexicon/G/Seite.990083")
    static let ukrainianPension = DirectorySource(name: "ПФУ · Подання заяви на пенсію", url: "https://www.pfu.gov.ua/2180486-yak-podaty-zayavu-na-pryznachennya-pensiyi-onlajn/")
    static let ukrainianIdentification = DirectorySource(name: "ПФУ · Ідентифікація пенсіонерів за кордоном", url: "https://www.pfu.gov.ua/zk/724194-fizychna-identyfikatsiya-pensioneriv-yaki-perebuvayut-za-kordonom-algorytm-dij/")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "banking": banking
        case "taxes": taxes
        case "pension": pensionGuide
        default: nil
        }
    }
}
