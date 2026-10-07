import Foundation

extension DocumentGuides {
    static let consulatesNearby = DirectoryGuide(
        cardSummary: .init(ukrainian: "Мюнхен, Мілан, Братислава, Прага та інші адреси", german: "München, Mailand, Bratislava, Prag und weitere Adressen"),
        introduction: .init(ukrainian: "Це офіційні адреси українських установ у сусідніх країнах. Якщо ви живете в Австрії, не їдьте туди без підтвердження: консульська дія може залежати від округу проживання, запису й правил в’їзду до іншої країни.", german: "Dies sind amtliche Adressen ukrainischer Vertretungen in Nachbarländern. Bei Wohnsitz in Österreich reisen Sie nicht ohne Bestätigung an: Konsularbezirk, Termin und Einreiseregeln des anderen Landes können entscheidend sein."),
        sections: [
            .init("bratislava", "mappin", "Братислава · Словаччина", "Bratislava · Slowakei",
                  "Посольство України: Radvanská 35, 811 01 Bratislava. Консульський e-mail: consul_sk@mfa.gov.ua. На сторінці МЗС перевірте прийом і запитайте, чи обслужать резидента Австрії. Окремий «Паспортний сервіс» ДП «Документ» у Братиславі — інша установа.",
                  "Ukrainische Botschaft: Radvanská 35, 811 01 Bratislava. Konsular-E-Mail: consul_sk@mfa.gov.ua. Prüfen Sie den Empfang und fragen Sie, ob Personen mit Wohnsitz in Österreich bedient werden. Der getrennte Passservice von DP „Dokument“ in Bratislava ist eine andere Stelle.", source: slovakia),
            .init("munich", "mappin", "Мюнхен · Німеччина", "München · Deutschland",
                  "Генеральне консульство України: Riedenburger Straße 2, 81677 München. E-mail: gc_dem@mfa.gov.ua. Його офіційний округ — Баварія та Баден-Вюртемберг; проживання в Австрії не гарантує прийом, тому спершу отримайте підтвердження консульства.",
                  "Ukrainisches Generalkonsulat: Riedenburger Straße 2, 81677 München. E-Mail: gc_dem@mfa.gov.ua. Der amtliche Bezirk umfasst Bayern und Baden-Württemberg; Wohnsitz in Österreich garantiert keinen Termin. Holen Sie vorab eine Bestätigung des Konsulats ein.", source: germany),
            .init("milan", "mappin", "Мілан · Італія", "Mailand · Italien",
                  "Генеральне консульство України: via Ludovico di Breme 11, 20156 Milano. E-mail: gc_itm@mfa.gov.ua. Перевірте вид послуги, e-Консул і можливість прийому з адресою проживання в Австрії. У Мілані є також окремі центри паспортних послуг — не плутайте їх з консульством.",
                  "Ukrainisches Generalkonsulat: via Ludovico di Breme 11, 20156 Milano. E-Mail: gc_itm@mfa.gov.ua. Prüfen Sie Leistung, e-Consul und Annahme bei Wohnsitz in Österreich. In Mailand gibt es auch gesonderte Passdienste; verwechseln Sie sie nicht mit dem Konsulat.", source: italy),
            .init("prague", "mappin", "Прага · Чехія", "Prag · Tschechien",
                  "Посольство України: Charles de Gaulle 29, 160 00 Praha 6. Консульський e-mail: consul_cz@mfa.gov.ua. Прийом — за попереднім записом; окремо перевірте центри ДП «Документ» у Чехії, якщо потрібен лише паспорт або ID.",
                  "Ukrainische Botschaft: Charles de Gaulle 29, 160 00 Praha 6. Konsular-E-Mail: consul_cz@mfa.gov.ua. Vorsprache nach Termin; für Pass oder ID prüfen Sie auch getrennte DP-„Dokument“-Zentren in Tschechien.", source: czechia),
            .init("budapest", "mappin", "Будапешт · Угорщина", "Budapest · Ungarn",
                  "Посольство України: Istenhegyi út 84/B, 1125 Budapest. Консульський e-mail: consul_hu@mfa.gov.ua. На сторінці МЗС перевірте актуальну чергу й перелік дій; для мешканців Австрії запитайте про консульську компетенцію до поїздки.",
                  "Ukrainische Botschaft: Istenhegyi út 84/B, 1125 Budapest. Konsular-E-Mail: consul_hu@mfa.gov.ua. Prüfen Sie aktuelle Termine und Leistungen beim MFA; fragen Sie bei österreichischem Wohnsitz vorab nach der Zuständigkeit.", source: hungary),
            .init("ljubljana", "mappin", "Любляна · Словенія", "Ljubljana · Slowenien",
                  "Посольство України: Mivka 27, 1000 Ljubljana. E-mail: emb_si@mfa.gov.ua. Графік і порядок для вразливих осіб указані на офіційній сторінці; підтвердьте можливість прийому резидентів Австрії.",
                  "Ukrainische Botschaft: Mivka 27, 1000 Ljubljana. E-Mail: emb_si@mfa.gov.ua. Die amtliche Seite nennt Sprechzeiten und Regeln für besonders schutzbedürftige Personen; bestätigen Sie die Annahme bei Wohnsitz in Österreich.", source: slovenia),
            .init("bern", "mappin", "Берн · Швейцарія", "Bern · Schweiz",
                  "Посольство України: Feldeggweg 5, 3005 Bern. Консульський e-mail: consul_ch@mfa.gov.ua. Швейцарія не входить до ЄС; перед поїздкою окремо перевірте правила в’їзду й повернення до Австрії за вашим паспортом і статусом.",
                  "Ukrainische Botschaft: Feldeggweg 5, 3005 Bern. Konsular-E-Mail: consul_ch@mfa.gov.ua. Die Schweiz gehört nicht zur EU; prüfen Sie vor Reise Einreise und Rückkehr nach Österreich für Ihren Pass und Aufenthaltsstatus.", source: switzerland),
            .init("zagreb", "mappin", "Загреб · Хорватія", "Zagreb · Kroatien",
                  "Посольство України: Voćarska 52, 10000 Zagreb. Консульський e-mail: consul_hr@mfa.gov.ua. Перед поїздкою перевірте доступність потрібної послуги, запис та прийом людей з адресою в Австрії.",
                  "Ukrainische Botschaft: Voćarska 52, 10000 Zagreb. Konsular-E-Mail: consul_hr@mfa.gov.ua. Prüfen Sie vor der Reise Leistung, Termin und Annahme bei Wohnsitz in Österreich.", source: DirectorySource(name: "МЗС України · Хорватія", url: "https://mfa.gov.ua/embassies/horvatiya"))
        ], sources: [embassies, eConsul, passportService]
    )
}
