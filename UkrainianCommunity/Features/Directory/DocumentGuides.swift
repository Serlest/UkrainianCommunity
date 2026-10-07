import Foundation

enum DocumentGuides {
    static let passports = DirectorySource(name: "МЗС України · Закордонний паспорт", url: "https://mfa.gov.ua/consul/forua/pass/port")
    static let passportActions = DirectorySource(name: "МЗС України · Паспортні дії", url: "https://mfa.gov.ua/consul/forua/pass")
    static let consularMilitary = DirectorySource(name: "МЗС України · Послуги чоловікам 18–60 років", url: "https://mfa.gov.ua/consul/forua/otrimannya-konsulskih-poslug-cholovikami-vikom-vid-18-do-60-rokiv")
    static let childPassport = DirectorySource(name: "МЗС України · Паспорт дитині до 16 років", url: "https://mfa.gov.ua/consul/forua/pass/port/do-16")
    static let inlandID = DirectorySource(name: "МЗС України · Внутрішній паспорт та ID", url: "https://mfa.gov.ua/consul/forua/pass/id")
    static let dmsID = DirectorySource(name: "ДМС України · ID-картка за кордоном", url: "https://dmsu.gov.ua/faq/vidpovidi-na-chasti-pitannya-na-period-voenogo-stanu/12529.html")
    static let passportService = DirectorySource(name: "ДП «Документ» · Центри", url: "https://pasport.org.ua/centers")
    static let civilRecords = DirectorySource(name: "МЗС України · Повторні свідоцтва і витяги", url: "https://mfa.gov.ua/consul/forua/reg/services-martial-law")
    static let civilRegistration = DirectorySource(name: "МЗС України · Акти цивільного стану", url: "https://mfa.gov.ua/consul/forua/reg")
    static let nameChange = DirectorySource(name: "МЗС України · Шлюб і зміна прізвища", url: "https://mfa.gov.ua/consul/forua/reg/shlyub")
    static let taxNumber = DirectorySource(name: "МЗС України · РНОКПП", url: "https://mfa.gov.ua/consul/forua/oformlennya-kartki-platnika-podatkiv-rnokpp")
    static let criminalUA = DirectorySource(name: "Дія · Витяг про несудимість", url: "https://diia.gov.ua/services/vityag-pro-nesudimist")
    static let notary = DirectorySource(name: "МЗС України · Нотаріальні дії", url: "https://mfa.gov.ua/consul/forua/legalization/notary")
    static let ukrainianApostille = DirectorySource(name: "МЗС України · Апостиль", url: "https://mfa.gov.ua/consul/forua/legalization/apostille")
    static let austrianApostille = DirectorySource(name: "BMEIA · Beglaubigung und Apostille", url: "https://www.bmeia.gv.at/reise-services/urkunden-und-beglaubigungen/beglaubigung-apostille")
    static let apostilleOffices = DirectorySource(name: "BMEIA · Zuständige Stellen und Kontakt", url: "https://www.bmeia.gv.at/reise-services/urkunden-und-beglaubigungen/beglaubigung-apostille/kontakt-beglaubigung")
    static let translators = DirectorySource(name: "Justiz · Gerichtsdolmetscherliste", url: "https://edikte.justiz.gv.at/edikte/ex/edparm3.nsf/h/SVPHLdf01")
    static let licenceEU = DirectorySource(name: "EU · Verordnung zu ukrainischen Führerscheinen", url: "https://eur-lex.europa.eu/eli/reg/2022/1280/oj?locale=de")
    static let licenceAT = DirectorySource(name: "Österreich · Ausländischen Führerschein umschreiben", url: "https://eausweise.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/fuehrerschein/3/Seite.040500")
    static let licenceUA = DirectorySource(name: "ГСЦ МВС · Обмін і відновлення посвідчення", url: "https://hsc.gov.ua/2026/03/16/yak-otrimati-abo-obminyati-posvidchennya-vodiya-pid-chas-vijni-ta-chi-mozhna-zrobiti-tse-onlajn/")
    static let birthAT = DirectorySource(name: "Österreich · Geburt eines Kindes", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/geburt-eines-kindes/1/Seite.080055")
    static let recordsAT = DirectorySource(name: "Österreich · Urkundenservice", url: "https://www.oesterreich.gv.at/de/landingpages/urkunden")
    static let criminalAT = DirectorySource(name: "Österreich · Strafregisterbescheinigung", url: "https://eausweise.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/strafregister/Seite.300020")
    static let lostAT = DirectorySource(name: "Österreich · Verlust von Dokumenten", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/verloren_gefunden/Seite.625000")
    static let returnCertificate = DirectorySource(name: "МЗС України · Посвідчення на повернення", url: "https://mfa.gov.ua/consul/forua/pass/pnp")
    static let eConsul = DirectorySource(name: "МЗС України · е-Консул", url: "https://id.e-consul.gov.ua/")
    static let embassies = DirectorySource(name: "МЗС України · Усі закордонні установи", url: "https://mfa.gov.ua/embassies")
    static let vienna = DirectorySource(name: "МЗС України · Австрія", url: "https://mfa.gov.ua/embassies/avstriyia")
    static let germany = DirectorySource(name: "МЗС України · Німеччина", url: "https://mfa.gov.ua/embassies/nimechchina")
    static let italy = DirectorySource(name: "МЗС України · Італія", url: "https://mfa.gov.ua/embassies/italiya")
    static let slovakia = DirectorySource(name: "МЗС України · Словаччина", url: "https://mfa.gov.ua/embassies/slovachina")
    static let czechia = DirectorySource(name: "МЗС України · Чехія", url: "https://mfa.gov.ua/embassies/chechiya")
    static let hungary = DirectorySource(name: "МЗС України · Угорщина", url: "https://mfa.gov.ua/embassies/ugorshchina")
    static let slovenia = DirectorySource(name: "МЗС України · Словенія", url: "https://mfa.gov.ua/embassies/sloveniya")
    static let switzerland = DirectorySource(name: "МЗС України · Швейцарія", url: "https://mfa.gov.ua/embassies/shvejcariya")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "identity": identity
        case "passport": passport
        case "ukrainian-id": ukrainianID
        case "child-documents": childDocuments
        case "civil-records": records
        case "name-change": names
        case "tax-number": ukrainianTaxNumber
        case "police-certificate": policeCertificate
        case "power-of-attorney": powerOfAttorney
        case "driving-licence": licence
        case "translations": translations
        case "apostille": apostille
        case "austrian-documents": austrianDocuments
        case "lost-documents": lostDocuments
        case "consulate-austria": consulateAustria
        case "consulates-nearby": consulatesNearby
        default: nil
        }
    }
}
