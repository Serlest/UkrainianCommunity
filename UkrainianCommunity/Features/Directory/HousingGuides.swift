import Foundation

enum HousingGuides {
    static let bmi = DirectorySource(name: "BMI · Ukraine und Unterkunft", url: "https://www.bmi.gv.at/ukraine/erfassung_und_aufenthalt.html")
    static let accommodation = DirectorySource(name: "BMI · Unterkunft suchen", url: "https://www.bmi.gv.at/ukraine/suche_unterkunft.html")
    static let bbuArrival = DirectorySource(name: "BBU · Ukraine / Прибуття", url: "https://www.bbu.gv.at/ukraine")
    static let basic = DirectorySource(name: "BBU · Grundversorgung / Базова допомога", url: "https://www.bbu.gv.at/ukraine-info-faq-ukrainian")
    static let housingHelp = DirectorySource(name: "WOHNSCHIRM · Miete, Energie, Housing First", url: "https://wohnschirm.at/")
    static let akRent = DirectorySource(name: "Arbeiterkammer · Mietwohnung", url: "https://www.arbeiterkammer.at/beratung/konsument/bauenundwohnen/miete/Miete.html")
    static let akContract = DirectorySource(name: "Arbeiterkammer · Mietvertrag", url: "https://www.arbeiterkammer.at/beratung/konsument/bauenundwohnen/miete/Mietvertrag.html")
    static let akOffer = DirectorySource(name: "AK Vorarlberg · Mietanbot", url: "https://vbg.arbeiterkammer.at/mietanbot")
    static let purchaseOffer = DirectorySource(name: "AK Niederösterreich · Kaufanbot", url: "https://noe.arbeiterkammer.at/beratung/konsumentenschutz/wohnen/eigentum/wohnungskauf_neu.html")
    static let broker = DirectorySource(name: "Österreich.gv.at · Bestellerprinzip", url: "https://www.oesterreich.gv.at/de/themen/bauen_und_wohnen/wohnen/3/1/Seite.210222")
    static let deposit = DirectorySource(name: "Arbeiterkammer · Kaution", url: "https://arbeiterkammer.at/beratung/konsument/bauenundwohnen/miete/Kautionsstreitigkeiten.html")
    static let depositReturn = DirectorySource(name: "AK Oberösterreich · Mietkaution", url: "https://ooe.arbeiterkammer.at/beratung/wohnen/mieten/Mietkaution.html")
    static let transferPayment = DirectorySource(name: "AK Wien · Verbotene Ablösen", url: "https://wien.arbeiterkammer.at/beratung/Wohnen/abrechnung/Verbotene_Abloesen.html")
    static let rentalTerm = DirectorySource(name: "oesterreich.gv.at · Befristung von Mietverträgen", url: "https://www.oesterreich.gv.at/de/themen/bauen_und_wohnen/wohnen/3/Seite.210215")
    static let rentalIncrease = DirectorySource(name: "Arbeiterkammer · Mietpreisbremse 2026", url: "https://www.arbeiterkammer.at/beratung/konsument/bauenundwohnen/miete/Mietpreisbremse.html")
    static let defects = DirectorySource(name: "Arbeiterkammer · Mietzinsminderung", url: "https://www.arbeiterkammer.at/beratung/konsument/bauenundwohnen/miete/Miete_reduzieren.html")
    static let costs = DirectorySource(name: "Arbeiterkammer · Betriebskosten", url: "https://wien.arbeiterkammer.at/beratung/Wohnen/abrechnung/Mietzins.html")
    static let operatingCosts = DirectorySource(name: "AK Wien · Betriebskosten prüfen", url: "https://wien.arbeiterkammer.at/beratung/Wohnen/miete/Betriebskosten-pruefen-als-Mieter-in.html")
    static let energy = DirectorySource(name: "Österreich.gv.at · Energieausweis", url: "https://www.oesterreich.gv.at/de/themen/bauen_und_wohnen/wohnen/1/Seite.210470")
    static let oeAD = DirectorySource(name: "OeAD · Studierendenunterkünfte", url: "https://oead.at/en/to-austria/accommodation")
    static let oeADHomes = DirectorySource(name: "OeAD student housing · Angebote", url: "https://www.oeadstudenthousing.at/en/")
    static let viennaHousing = DirectorySource(name: "Stadt Wien · Wohnberatung", url: "https://www.wien.gv.at/wohnen/wohnberatung-wien")
    static let viennaSupport = DirectorySource(name: "Stadt Wien · Wohnbeihilfe", url: "https://www.wien.gv.at/amtswege/wohnbeihilfe-antrag")
    static let socialHousing = DirectorySource(name: "oesterreich.gv.at · Genossenschaftswohnungen", url: "https://www.oesterreich.gv.at/de/themen/bauen_und_wohnen/wohnen/Seite.210250")
    static let housingAidNational = DirectorySource(name: "oesterreich.gv.at · Wohnförderungen der Länder", url: "https://www.oesterreich.gv.at/de/themen/bauen_und_wohnen/wohnen/8/3/Seite.210172")
    static let moving = DirectorySource(name: "Österreich.gv.at · Wohnsitz anmelden", url: "https://www.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/an__abmeldung_des_wohnsitzes/Seite.1180200")
    static let afterMove = DirectorySource(name: "oesterreich.gv.at · Nach dem Umzug", url: "https://www.oesterreich.gv.at/de/lebenslagen/Ich-wohne-bald-in-einem-neuen-Zuhause/Nach-dem-Umzug")
    static let beforeMove = DirectorySource(name: "oesterreich.gv.at · Vor dem Umzug", url: "https://www.oesterreich.gv.at/de/lebenslagen/Ich-wohne-bald-in-einem-neuen-Zuhause/Vor-dem-Umzug")
    static let energyMove = DirectorySource(name: "E-Control · Strom und Gas ummelden", url: "https://www.e-control.at/konsumenten/wie-uebersiedeln")
    static let foreignBuyer = DirectorySource(name: "Österreich.gv.at · Ausländergrunderwerb", url: "https://www.oesterreich.gv.at/de/themen/bauen_und_wohnen/grundstueckskauf_und_grundbuch/grundstueckskauf/1/Seite.200041")
    static let purchaseCosts = DirectorySource(name: "Österreich.gv.at · Kaufnebenkosten", url: "https://eausweise.oesterreich.gv.at/de/themen/bauen_und_wohnen/wohnen/8/Seite.210150")
    static let escrow = DirectorySource(name: "Österreich.gv.at · Treuhandschaft", url: "https://www.oesterreich.gv.at/de/themen/bauen_und_wohnen/grundstueckskauf_und_grundbuch/grundstueckskauf/3/Seite.200054")
    static let registry = DirectorySource(name: "Österreich.gv.at · Grundbuchsauszug", url: "https://www.oesterreich.gv.at/de/themen/bauen_und_wohnen/grundstueckskauf_und_grundbuch/grundbuch/Seite.600420")
    static let willhaben = DirectorySource(name: "willhaben · Mietwohnungen", url: "https://www.willhaben.at/iad/immobilien/mietwohnungen/mietwohnung-angebote/")
    static let immoscout = DirectorySource(name: "ImmoScout24 Österreich · Immobilien", url: "https://www.immobilienscout24.at/")
    static let wgGesucht = DirectorySource(name: "WG-Gesucht · Zimmer", url: "https://www.wg-gesucht.de/")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "arrival-housing": arrival
        case "temporary-housing": temporary
        case "find-rental": search
        case "viewing": viewing
        case "rental-contract": contract
        case "rent-costs": rentCosts
        case "deposit": depositGuide
        case "rental-agents": agents
        case "tenant-rights": tenantRights
        case "ending-lease": ending
        case "shared-flat": shared
        case "student-housing": studentHomes
        case "social-housing": social
        case "housing-support": support
        case "buying": buying
        case "buying-costs": buyingCosts
        case "foreign-buyers": foreignBuyers
        case "moving": move
        default: nil
        }
    }
}
