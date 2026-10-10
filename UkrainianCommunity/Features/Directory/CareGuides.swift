import Foundation

enum CareGuides {
    private static let apply = DirectorySource(name: "oesterreich.gv.at · Antrag auf Pflegegeld", url: "https://www.oesterreich.gv.at/de/themen/pflege/4/1/Seite.360517")
    private static let amounts = DirectorySource(name: "oesterreich.gv.at · Höhe des Pflegegeldes", url: "https://www.oesterreich.gv.at/de/themen/pflege/4/Seite.360516")
    private static let mobile = DirectorySource(name: "oesterreich.gv.at · Soziale Dienste", url: "https://www.oesterreich.gv.at/themen/pflege/soziale_dienste/Seite.1210200.html")
    private static let relatives = DirectorySource(name: "Gesundheitsportal · Pflegende Angehörige", url: "https://www.gesundheit.gv.at/leben/altern/wohnen-im-alter/pflegende-angehoerige-entlastungen-unterstuetzungen.html")
    private static let roundClock = DirectorySource(name: "Sozialministeriumservice · 24-Stunden-Betreuung", url: "https://www.sozialministeriumservice.gv.at/Angehoerige/Pflege_und_Betreuung/24-Stunden-Betreuung/24-Stunden-Betreuung.de.html")
    private static let home = DirectorySource(name: "oesterreich.gv.at · Kosten für Pflegeheime", url: "https://www.oesterreich.gv.at/de/themen/pflege/2/Seite.360542")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "home-care": return homeCare
        case "care-services": return careServices
        default: return nil
        }
    }

    private static let homeCare = DirectoryGuide(
        cardSummary: .init(ukrainian: "Оцінка потреби, Pflegegeld і підтримка близьких", german: "Pflegebedarf, Pflegegeld und Entlastung Angehöriger"),
        introduction: .init(ukrainian: "Потреба в догляді може виникнути у будь-якому віці. Спочатку зафіксуйте, що людина не може виконувати самостійно.", german: "Pflegebedarf kann in jedem Alter entstehen. Zuerst dokumentieren, was die Person nicht mehr selbst tun kann."),
        sections: [
            .init("assess", "list.clipboard", "Опишіть щоденну потребу", "Alltagsbedarf erfassen", "Протягом кількох днів записуйте допомогу з одяганням, їжею, гігієною, ліками й пересуванням та хто її надає. Обговоріть з лікарем медичні ризики й потребу в домашній медсестрі. Якщо стан раптово погіршується, зверніться по медичну допомогу, не чекаючи заяви на виплати.", "Einige Tage Hilfe bei Ankleiden, Essen, Hygiene, Medikamenten und Mobilität sowie helfende Personen notieren. Medizinische Risiken und Hauskrankenpflege mit Arzt besprechen. Bei akuter Verschlechterung medizinische Hilfe holen, nicht auf Leistungsantrag warten.", source: relatives),
            .init("allowance", "doc.text", "Подайте заявку на Pflegegeld", "Pflegegeld beantragen", "Заявку або прохання про підвищення подайте до компетентного страхового органу; можливе неформальне подання. Додайте актуальні висновки, заповніть отриману анкету й дочекайтеся оцінки вдома. Рішення надходить як Bescheid. Рівень залежить від встановленої потреби, а не лише від діагнозу; суми змінюються щороку.", "Antrag oder Erhöhungsantrag beim zuständigen Versicherungsträger einbringen, auch formlos möglich. Aktuelle Befunde beilegen, zugesandten Fragebogen ausfüllen und Hausbegutachtung abwarten. Entscheidung kommt per Bescheid. Stufe hängt vom festgestellten Pflegebedarf, nicht nur der Diagnose ab; Beträge ändern sich jährlich.", source: apply),
            .init("relief", "person.2", "Підтримайте того, хто доглядає", "Pflegende entlasten", "Попросіть консультацію про навчання догляду, заміну на час відпочинку та психосоціальну підтримку. Якщо близький працює, окремо перевірте можливості Pflegekarenz, Pflegeteilzeit й наслідки для доходу та страхування. Розподіліть контакти для екстреного випадку.", "Beratung zu Pflegetraining, Ersatzpflege und psychosozialer Entlastung nutzen. Bei Erwerbstätigkeit Pflegekarenz, Pflegeteilzeit und Folgen für Einkommen und Versicherung gesondert prüfen. Notfallkontakte in der Familie festlegen.", source: relatives)
        ], sources: [apply, amounts, relatives]
    )

    private static let careServices = DirectoryGuide(
        cardSummary: .init(ukrainian: "Мобільні служби, цілодобовий догляд і заклад", german: "Mobile Dienste, 24-Stunden-Betreuung und Heim"),
        introduction: .init(ukrainian: "Послуги організовують землі та громади, тому наявність, черга й особиста доплата залежать від місця.", german: "Länder und Gemeinden organisieren Angebote; Verfügbarkeit, Wartezeit und Eigenbeitrag hängen vom Ort ab."),
        sections: [
            .init("mobile", "house", "Почніть з підтримки вдома", "Zuerst Hilfe zu Hause prüfen", "У Gemeinde, Bezirk або Magistrat запитайте про Heimhilfe, Hauskrankenpflege, Essen auf Rädern і денний центр. Попросіть оцінку потреби, графік, письмову ціну після субсидії та порядок скасування. На соціальні послуги не завжди існує безумовне право.", "Bei Gemeinde, Bezirk oder Magistrat nach Heimhilfe, Hauskrankenpflege, Essen auf Rädern und Tageszentrum fragen. Bedarfserhebung, Dienstplan, Preis nach Förderung und Stornoregel schriftlich verlangen. Auf soziale Dienste besteht nicht immer ein Rechtsanspruch.", source: mobile),
            .init("fulltime", "clock", "Цілодобовий догляд", "24-Stunden-Betreuung", "Якщо потрібна постійна присутність, порівняйте модель із найманою та самозайнятою Betreuungskraft: договір, страховка, заміна, нічні години й обов’язки. Для державної дотації Sozialministeriumservice перевіряє умови, зокрема Pflegegeld; подайте заяву близько до початку догляду. Суми й межі перевірте на офіційній сторінці перед підписанням.", "Bei ständigem Bedarf Modelle mit angestellter oder selbständiger Betreuungskraft vergleichen: Vertrag, Versicherung, Ersatz, Nachtzeiten und Aufgaben. Sozialministeriumservice prüft Fördervoraussetzungen einschließlich Pflegegeld; Antrag zeitnah zum Betreuungsbeginn stellen. Aktuelle Beträge und Grenzen vor Unterschrift amtlich prüfen.", source: roundClock),
            .init("institution", "building.2", "Якщо потрібен заклад", "Wenn ein Heim nötig ist", "Попросіть у землі список закладів, умови прийому, рівень догляду, письмовий Heimvertrag та повний розрахунок. Пенсія, Pflegegeld та інші доходи можуть покривати витрати; при нестачі уточніть соціальну допомогу. Вартість залежить від землі та закладу, тому не переносіть ціни з іншого регіону.", "Bei Land Heime, Aufnahmebedingungen, Pflegestufe, schriftlichen Heimvertrag und vollständige Kostenrechnung erfragen. Pension, Pflegegeld und weitere Einkünfte können herangezogen werden; bei Lücke Sozialhilfe prüfen. Kosten unterscheiden sich nach Land und Heim.", source: home)
        ], sources: [mobile, roundClock, home]
    )
}
