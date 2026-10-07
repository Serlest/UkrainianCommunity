import Foundation

extension DocumentGuides {
    static let lostDocuments = DirectoryGuide(
        cardSummary: .init(ukrainian: "Поліція, консульство, відновлення й повернення в Україну", german: "Polizei, Konsulat, Ersatz und Rückkehr in die Ukraine"),
        introduction: .init(ukrainian: "Дії залежать від того, що втрачено: паспорт, картку перебування, водійське посвідчення або свідоцтво. Почніть із захисту своїх даних і підтвердження втрати.", german: "Das Vorgehen hängt vom verlorenen Pass, Aufenthaltstitel, Führerschein oder der Urkunde ab. Sichern Sie zuerst Ihre Daten und dokumentieren Sie den Verlust."),
        sections: [
            .init("police", "shield.lefthalf.filled", "Повідомте про втрату або крадіжку", "Verlust oder Diebstahl melden",
                  "Для втраченого чи викраденого офіційного посвідчення особи зверніться до місцевої поліції й отримайте підтвердження Anzeige; за австрійськими правилами повідомлення про втрату офіційного фото-ID потрібне. Запишіть номер документа, дату, місце й обставини. Якщо викрадено картки банку, заблокуйте їх окремо.",
                  "Melden Sie den Verlust oder Diebstahl eines amtlichen Lichtbildausweises bei der örtlichen Polizei und bewahren Sie die Anzeige auf; nach österreichischen Regeln ist eine Verlustanzeige für amtliche Fotoausweise erforderlich. Notieren Sie Dokumentnummer, Zeitpunkt, Ort und Umstände. Sperren Sie gestohlene Bankkarten gesondert."),
            .init("passport", "airplane", "Втрачено український паспорт", "Ukrainischer Pass verloren",
                  "Зверніться до українського консульства з поліцейським підтвердженням і наявними доказами особи та громадянства. Там з’ясують оформлення нового паспорта. Якщо потрібно лише терміново повернутися в Україну, консул може видати посвідчення на повернення після перевірки особи; воно не є звичайним паспортом для подорожей іншими країнами.",
                  "Wenden Sie sich mit Polizeibestätigung und vorhandenen Identitäts- und Staatsangehörigkeitsnachweisen an das ukrainische Konsulat. Dort klären Sie die Neuausstellung. Für eine dringende Rückkehr ausschließlich in die Ukraine kann der Konsul nach Identitätsprüfung ein Rückkehrdokument ausstellen; es ist kein normaler Reisepass für andere Reisen."),
            .init("residence", "person.text.rectangle", "Втрачено картку статусу", "Aufenthaltskarte verloren",
                  "Для Ausweis für Vertriebene зверніться до BFA; для іншого Aufenthaltstitel — до органу, що його видав (у Відні часто MA 35). Підготуйте паспорт, поліцейське підтвердження та дані картки. Уточніть тимчасовий доказ статусу і правила повторного в’їзду до Австрії перед поїздкою.",
                  "Beim Vertriebenenausweis wenden Sie sich an das BFA, bei einem anderen Aufenthaltstitel an die ausstellende Behörde (in Wien häufig MA 35). Halten Sie Pass, Polizeibestätigung und Kartendaten bereit. Fragen Sie vor Reisen nach vorläufigem Statusnachweis und Wiedereinreise."),
            .init("other", "doc.on.doc", "Права, свідоцтва, e-card", "Führerschein, Urkunden, e-card",
                  "Для українських прав перевірте відновлення через ГСЦ МВС і австрійську Führerscheinbehörde; з одним фото документа не сідайте за кермо. Українські свідоцтва можна запросити повторно через уповноважену установу. За новою австрійською Geburtsurkunde звертайтеся до Standesamt; для e-card — до страхової каси.",
                  "Für ukrainische Führerscheine klären Sie Ersatz beim ukrainischen MVS und der österreichischen Führerscheinbehörde; ein Foto allein berechtigt nicht zum Fahren. Ukrainische Urkunden können über ermächtigte Stellen neu beantragt werden. Österreichische Geburtsurkunden gibt das Standesamt erneut aus; wegen der e-card wenden Sie sich an die Krankenkasse.")
        ], sources: [lostAT, passportActions, returnCertificate, civilRecords, licenceUA,
                     DirectorySource(name: "BFA · Kontakt", url: "https://www.bfa.gv.at/kontakt/")]
    )

    static let consulateAustria = DirectoryGuide(
        cardSummary: .init(ukrainian: "Відень: адреса, контакти, запис і підготовка", german: "Wien: Adresse, Kontakt, Termin und Vorbereitung"),
        introduction: .init(ukrainian: "Для людей, які проживають в Австрії, перший контакт з українських консульських питань — Посольство України у Відні. Перевірте актуальну сторінку перед візитом.", german: "Für Menschen mit Wohnsitz in Österreich ist die ukrainische Botschaft in Wien die erste Anlaufstelle für Konsularfragen. Prüfen Sie vor dem Besuch die aktuelle amtliche Seite."),
        sections: [
            .init("address", "mappin.and.ellipse", "Адреса й зв’язок", "Adresse und Kontakt",
                  "Посольство України: Naaffgasse 23, 1180 Wien. Консульські питання: consul_at@mfa.gov.ua, телефон +43 1 479 71 72 22. На сторінці МЗС є актуальні канали й години телефонних консультацій; не плутайте посольство з Постійним представництвом України при міжнародних організаціях у Відні.",
                  "Ukrainische Botschaft: Naaffgasse 23, 1180 Wien. Konsularfragen: consul_at@mfa.gov.ua, Telefon +43 1 479 71 72 22. Die MFA-Seite nennt aktuelle Kontakte und telefonische Beratungszeiten. Verwechseln Sie die Botschaft nicht mit der Ständigen Vertretung bei internationalen Organisationen in Wien.", source: vienna),
            .init("booking", "calendar.badge.clock", "Запис і документи", "Termin und Unterlagen",
                  "Відкрийте сторінку конкретної послуги та систему «е-Консул». Перед записом перевірте особисту присутність, перелік оригіналів, оплату, фото й можливість видачі без запису. Для вразливих людей або технічної неможливості запису спитайте консульський відділ про доступний порядок; не купуйте «місце в черзі» у посередників.",
                  "Öffnen Sie die Seite der konkreten Leistung und „e-Consul“. Prüfen Sie persönliche Vorsprache, Originale, Gebühren, Fotos und Regeln zur Abholung ohne Termin. Bei besonderer Schutzbedürftigkeit oder technischen Problemen fragen Sie die Konsularabteilung nach dem vorgesehenen Weg; kaufen Sie keinen Termin von Vermittlern.", source: eConsul),
            .init("scope", "checklist", "Які питання вирішують", "Welche Anliegen bearbeitet werden",
                  "У консульстві уточнюйте закордонний паспорт, документи на повернення, окремі акти цивільного стану, повторні свідоцтва, нотаріальні дії й інші послуги. Внутрішню ID-картку посольство не виготовляє; австрійські свідоцтва й апостиль видають австрійські органи.",
                  "Beim Konsulat klären Sie Reisepass, Rückkehrdokument, bestimmte Personenstandsakte, neue ukrainische Urkunden, notarielle Handlungen und weitere Dienste. Die Botschaft stellt keine ukrainische Inlandskarte aus; österreichische Urkunden und Apostillen kommen von österreichischen Stellen.", source: passportActions)
        ], sources: [embassies, civilRecords]
    )
}
