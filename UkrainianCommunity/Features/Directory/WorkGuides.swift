import Foundation

enum WorkGuides {
    static let permission = DirectorySource(name: "AMS · Beschäftigung von Vertriebenen", url: "https://www.ams.at/regionen/osterreichweit/news/2023/04/keine-beschaeftigungsbewilligung-fuer-vertriebene")
    static let studentWork = DirectorySource(name: "Migration.gv.at · Arbeitsmarktzugang für Studierende", url: "https://www.migration.gv.at/de/formen-der-zuwanderung/temporaerer-aufenthalt/")
    static let displacedBusiness = DirectorySource(name: "BMI · Rot-Weiß-Rot – Karte plus für Vertriebene", url: "https://www.bmi.gv.at/ukraine/informationen_zum_umstieg_auf_eine_rot-_weiss_rot_karte_plus.html")
    static let ams = DirectorySource(name: "AMS · Beratung und Jobsuche", url: "https://www.ams.at/arbeitsuchende/arbeitslos-was-tun/beratung-im-ams")
    static let amsChanges = DirectorySource(name: "AMS · Meldepflichten", url: "https://www.ams.at/arbeitsuchende/arbeitslos-was-tun/ihre-meldepflichten")
    static let basicCare = DirectorySource(name: "BBU · Grundversorgung für Vertriebene", url: "https://www.bbu.gv.at/ukraine-info-faq-ukrainian")
    static let allJobs = DirectorySource(name: "AMS · alle jobs und eJob-Room", url: "https://www.ams.at/arbeitsuchende/arbeitslos-was-tun/jobsuche-online-und-mobil/ams-jobsuche-hilfe")
    static let application = DirectorySource(name: "AMS · Online-Bewerbung", url: "https://www.ams.at/arbeitsuchende/topicliste/online-bewerbung")
    static let contract = DirectorySource(name: "Arbeiterkammer · Arbeitsvertrag und Dienstzettel", url: "https://www.arbeiterkammer.at/beratung/arbeitundrecht/Arbeitsvertraege/Arbeitsvertrag_und_Dienstzettel.html")
    static let registration = DirectorySource(name: "USP · Anmeldung von Personal", url: "https://www.usp.gv.at/themen/mitarbeiter-und-gesundheit/einstellung-mitarbeiter-und-arten-der-beschaeftigung/weitere-informationen-einstellen-von-personal/anmeldung-dienstnehmer.html")
    static let pay = DirectorySource(name: "Arbeiterkammer · Lohn und Kollektivvertrag", url: "https://www.arbeiterkammer.at/beratung/arbeitundrecht/Arbeitsvertraege/So_viel_Lohn_steht_mir_zu.html")
    static let specialPay = DirectorySource(name: "Arbeiterkammer Kärnten · Weihnachts- und Urlaubsgeld", url: "https://kaernten.arbeiterkammer.at/beratung/arbeitundrecht/Arbeitsvertraege/Weihnachts-_und_Urlaubsgeld.html")
    static let workTime = DirectorySource(name: "Arbeiterkammer · Normalarbeitszeit und Pausen", url: "https://www.arbeiterkammer.at/beratung/arbeitundrecht/Arbeitszeit/Normalarbeitszeit/Normalarbeitszeit.html")
    static let holiday = DirectorySource(name: "Arbeiterkammer · Urlaubsanspruch", url: "https://www.arbeiterkammer.at/beratung/arbeitundrecht/Urlaub/So_viel_Urlaub_bekommen_Sie.html")
    static let sickLeave = DirectorySource(name: "Arbeiterkammer · Krankenstand", url: "https://www.arbeiterkammer.at/beratung/arbeitundrecht/krankheitundpflege/krankheit/Krankenstand.html")
    static let termination = DirectorySource(name: "Arbeiterkammer · Arbeitgeber-Kündigung", url: "https://www.arbeiterkammer.at/beratung/arbeitundrecht/beendigung/Arbeitgeber-Kuendigung.html")
    static let mutualTermination = DirectorySource(name: "Arbeiterkammer · Einvernehmliche Auflösung", url: "https://www.arbeiterkammer.at/beratung/arbeitundrecht/beendigung/Einvernehmliche_Aufloesung.html")
    static let startBusiness = DirectorySource(name: "USP · Gewerbeanmeldung", url: "https://www.usp.gv.at/gruendung/EAP/gewerbeanmeldung.html")
    static let svs = DirectorySource(name: "SVS · Versicherungsanmeldung", url: "https://www.svs.at/cdscontent/?contentid=10007.899587&portal=svsportal")
    static let newSelfEmployed = DirectorySource(name: "USP · Neue Selbständige", url: "https://www.usp.gv.at/themen/mitarbeiter-und-gesundheit/einstellung-mitarbeiter-und-arten-der-beschaeftigung/weitere-informationen-einstellen-von-personal/neue-selbststaendige.html")
    static let taxes = DirectorySource(name: "USP · Pflichten des Unternehmers", url: "https://www.usp.gv.at/themen/steuern-finanzen/steuerliche-rechte-und-pflichten/pflichten-des-unternehmers.html")
    static let smallBusiness = DirectorySource(name: "USP · Kleinunternehmerregelung", url: "https://www.usp.gv.at/themen/steuern-finanzen/umsatzsteuer-ueberblick/weitere-informationen-zur-umsatzsteuer/weitere-steuertatbestaende-und-befreiungen/kleinunternehmen.html")
    static let freeContract = DirectorySource(name: "USP · Freie Dienstnehmer", url: "https://www.usp.gv.at/themen/mitarbeiter-und-gesundheit/einstellung-mitarbeiter-und-arten-der-beschaeftigung/freie-dienstnehmer.html")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "work-rights": workRights
        case "job-search": jobSearch
        case "employee-rights": employeeRights
        case "self-employment": selfEmployment
        default: nil
        }
    }
}
