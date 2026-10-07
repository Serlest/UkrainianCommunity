import Foundation

extension ResidenceGuides {
    static let studentResidence = DirectoryGuide(
        cardSummary: .init(ukrainian: "Вступ, кошти, збір 218 €, робота й продовження", german: "Zulassung, Mittel, 218 € Gebühr, Arbeit und Verlängerung"),
        introduction: .init(ukrainian: "Для навчання понад шість місяців громадянам третіх країн зазвичай потрібна Aufenthaltsbewilligung – Student. Це не те саме, що віза D для коротшого перебування.", german: "Für ein Studium über sechs Monate benötigen Drittstaatsangehörige meist eine Aufenthaltsbewilligung – Student. Sie ist nicht dasselbe wie ein Visum D für kürzere Aufenthalte."),
        sections: [
            .init("admission", "graduationcap", "Яке навчання підходить", "Welche Studien zählen",
                  "Потрібне зарахування на навчання, яке визнає закон: зокрема, звичайне навчання у виші або окремі передбачені види позачергового навчання. Просто мовні курси самі по собі не завжди є підставою. Університетська Zulassung і дозвіл на проживання — різні рішення.",
                  "Erforderlich ist die Zulassung zu einem gesetzlich erfassten Studium: etwa einem ordentlichen Hochschulstudium oder bestimmten außerordentlichen Studien. Reine Sprachkurse allein reichen nicht stets aus. Hochschulzulassung und Aufenthaltstitel sind verschiedene Entscheidungen."),
            .init("papers", "doc.text", "Документи й подання", "Unterlagen und Antrag",
                  "Підготуйте паспорт, фото, зарахування, підтвердження коштів та страхування з покриттям в Австрії. Для Student окремий доказ права на житло не є загальною умовою, але витрати на нього враховують при розрахунку коштів. Орган може запросити додаткові документи й переклади. Подати заяву можна особисто за кордоном або під час законного перебування в Австрії; перша заява не продовжує строк цього перебування.",
                  "Bereiten Sie Pass, Foto, Zulassung, Mittel und in Österreich wirksame Krankenversicherung vor. Beim Titel Student ist ein gesonderter Rechtsanspruch auf Unterkunft grundsätzlich nicht nachzuweisen; Wohnkosten zählen aber bei der Mittelberechnung. Die Behörde kann weitere Urkunden und Übersetzungen verlangen. Persönliche Antragstellung ist im Ausland oder während rechtmäßigen Aufenthalts im Inland möglich; der Erstantrag verlängert dessen Dauer nicht.", source: student),
            .init("costs", "eurosign.circle", "Кошти та збір у 2026 році", "Mittel und Gebühr 2026",
                  "Підтвердьте кошти на запитаний строк, максимум на 12 місяців наперед. У 2026 році базовий місячний орієнтир для студентів залежно від віку — 722,58 € або 1 308,39 €; витрати на житло понад установлену межу та страхування можуть збільшити потрібну суму. Збір за заяву — 218 €. Перед поданням відкрийте актуальний розрахунок OeAD: суми щороку змінюються.",
                  "Belegen Sie Mittel für die beantragte Dauer, höchstens zwölf Monate im Voraus. Der monatliche Basisrichtsatz für Studierende beträgt 2026 je nach Alter 722,58 € oder 1.308,39 €; Wohnkosten über dem Freibetrag und Versicherung können den Bedarf erhöhen. Die Antragsgebühr beträgt 218 €. Prüfen Sie vor Antrag die aktuelle OeAD-Berechnung: Beträge ändern sich jährlich.",
                  source: DirectorySource(name: "OeAD · Aufenthalt Student 2026", url: "https://oead.at/de/nach-oesterreich/einreise-und-aufenthalt/aufenthaltsbewilligung-student-kein-mobilitaetsprogramm")),
            .init("work", "briefcase", "Робота під час навчання", "Arbeit während des Studiums",
                  "Студентський дозвіл не є вільним доступом до ринку праці. Для найманої роботи роботодавцю зазвичай потрібна Beschäftigungsbewilligung від AMS, навіть за малого обсягу; для роботи до 20 годин на тиждень її можуть видати без перевірки ринку праці. Не починайте роботу до з’ясування потрібного дозволу.",
                  "Der Studierendentitel eröffnet keinen freien Arbeitsmarktzugang. Für unselbständige Arbeit braucht der Arbeitgeber grundsätzlich eine Beschäftigungsbewilligung des AMS, auch bei geringem Umfang; bis 20 Wochenstunden kann sie ohne Arbeitsmarktprüfung erteilt werden. Klären Sie die Bewilligung vor Arbeitsbeginn."),
            .init("renew", "calendar.badge.clock", "Продовження й навчальний успіх", "Verlängerung und Studienerfolg",
                  "Подайте продовження особисто не раніше ніж за три місяці до завершення картки й обов’язково до її закінчення. Потрібні, зокрема, актуальне підтвердження навчання та Studienerfolgsnachweis. Якщо прогресу бракує, з’ясуйте з органом можливі законні винятки до закінчення дозволу.",
                  "Beantragen Sie die Verlängerung persönlich frühestens drei Monate vor und jedenfalls vor Ablauf der Karte. Erforderlich sind unter anderem aktuelle Studienunterlagen und ein Studienerfolgsnachweis. Fehlt Studienerfolg, klären Sie mögliche gesetzliche Ausnahmen vor Ablauf mit der Behörde."),
            .init("graduate", "arrow.right.circle", "Після диплома", "Nach dem Abschluss",
                  "Після успішного завершення відповідного навчання студентський дозвіл можна за певних умов один раз продовжити на 12 місяців для пошуку роботи або заснування компанії. Можливий перехід на RWR-картку, Blue Card EU чи дозвіл дослідника, якщо виконані їхні умови. Зверніться до закінчення поточного документа.",
                  "Nach erfolgreichem Abschluss eines geeigneten Studiums kann der Studierendentitel unter Voraussetzungen einmalig um zwölf Monate für Arbeitssuche oder Unternehmensgründung verlängert werden. Ein Wechsel zu RWR-Karte, Blauer Karte EU oder Forschertitel ist bei erfüllten Bedingungen möglich. Handeln Sie vor Ablauf des aktuellen Dokuments.")
        ], sources: [student, studentWork, renewal]
    )

    static let workResidence = DirectoryGuide(
        cardSummary: .init(ukrainian: "Дозволи для кваліфікованої роботи й зміни роботодавця", german: "Titel für qualifizierte Arbeit und Arbeitgeberwechsel"),
        introduction: .init(ukrainian: "Шлях для роботи залежить від кваліфікації, пропозиції роботи, зарплати та виду діяльності. Тимчасовий захист уже дає окреме право працювати.", german: "Der Arbeitsweg hängt von Qualifikation, Stellenangebot, Entgelt und Tätigkeit ab. Vorübergehender Schutz gewährt bereits ein eigenes Arbeitsrecht."),
        sections: [
            .init("rwr", "briefcase.fill", "Rot-Weiß-Rot-Karte", "Rot-Weiß-Rot-Karte",
                  "RWR-картка призначена для визначених груп кваліфікованих працівників: дефіцитні професії, ключові спеціалісти, випускники австрійських вишів та інші групи. Зазвичай потрібна конкретна пропозиція роботи; AMS перевіряє відповідні умови. Картка, як правило, прив’язана до вказаного роботодавця й видається до 24 місяців.",
                  "Die RWR-Karte richtet sich an gesetzlich definierte Gruppen qualifizierter Arbeitskräfte: Mangelberufe, Schlüsselkräfte, Absolventen österreichischer Hochschulen und weitere Gruppen. Meist braucht es ein konkretes Angebot; das AMS prüft die Voraussetzungen. Die Karte ist grundsätzlich an den genannten Arbeitgeber gebunden und gilt bis zu 24 Monate."),
            .init("blue", "star.circle", "Blaue Karte EU", "Blaue Karte EU",
                  "Blue Card EU — окремий дозвіл для висококваліфікованої роботи з визначеними вимогами до освіти або досвіду, трудового договору та оплати. Не плутайте її з синьою карткою для переміщених з України. Офіційний портал порівнює робочі маршрути та поточні пороги.",
                  "Die Blaue Karte EU ist ein eigener Titel für hochqualifizierte Beschäftigung mit Vorgaben zu Ausbildung oder Erfahrung, Arbeitsvertrag und Entgelt. Sie ist nicht der blaue Ausweis für Vertriebene aus der Ukraine. Das amtliche Portal erläutert Arbeitswege und aktuelle Schwellen."),
            .init("change", "arrow.triangle.branch", "Зміна роботи", "Arbeitgeberwechsel",
                  "На RWR-картці зміна роботодавця протягом строку її дії зазвичай потребує нової картки. RWR+ дає необмежений доступ до ринку праці без прив’язки до роботодавця. Перед звільненням або новою роботою перевірте саме свій документ і правила переходу.",
                  "Mit einer RWR-Karte erfordert ein Arbeitgeberwechsel während ihrer Gültigkeit grundsätzlich eine neue Karte. Die RWR-Karte plus erlaubt unbeschränkten Arbeitsmarktzugang ohne Arbeitgeberbindung. Prüfen Sie Ihren konkreten Titel und den Wechsel vor Arbeitsbeginn."),
            .init("other", "person.crop.rectangle.stack", "Інші робочі підстави", "Andere Erwerbswege",
                  "Для дослідників, самозайнятих, підприємців, внутрішньокорпоративних переведень та короткострокової роботи існують інші дозволи. Обирайте підставу за реальною діяльністю; контракт сам по собі не створює права перебування.",
                  "Für Forschende, Selbständige, Unternehmensgründungen, konzerninterne Transfers und befristete Arbeit bestehen andere Titel. Wählen Sie nach der tatsächlichen Tätigkeit; ein Arbeitsvertrag allein schafft kein Aufenthaltsrecht.")
        ], sources: [work, rwrPlus, permits]
    )

    static let rwrPlusGuide = DirectoryGuide(
        cardSummary: .init(ukrainian: "Вільна робота; окремий перехід для переміщених", german: "Freier Arbeitsmarktzugang; Sonderweg für Vertriebene"),
        introduction: .init(ukrainian: "RWR+ — строковий дозвіл на оселення з вільним доступом до роботи. Підстави для його отримання різні; перехід із тимчасового захисту має спеціальні умови.", german: "Die RWR-Karte plus ist ein befristeter Niederlassungstitel mit freiem Arbeitsmarktzugang. Es gibt unterschiedliche Zugangswege; für Vertriebene gelten besondere Voraussetzungen."),
        sections: [
            .init("general", "person.2", "Звичайні шляхи", "Allgemeine Zugangswege",
                  "RWR+ можуть отримати, зокрема, члени сім’ї певних власників робочих дозволів та люди, які після RWR-картки або Blue Card EU відповідали умовам зайнятості щонайменше 21 місяць із попередніх 24. Конкретний шлях залежить від чинного дозволу й умов сімейного возз’єднання.",
                  "Eine RWR-Karte plus kommt unter anderem für Familienangehörige bestimmter Arbeitstitelinhaber oder nach RWR-Karte bzw. Blauer Karte EU bei mindestens 21 Monaten entsprechender Beschäftigung in den letzten 24 Monaten in Betracht. Der genaue Weg hängt vom bisherigen Titel und den Familienregeln ab."),
            .init("ukraine", "checklist", "Перехід із захисту для українців", "Umstieg aus dem Ukraine-Schutz",
                  "За спеціальним маршрутом потрібне чинне право перебування переміщеної особи та 12 місяців повного страхування через роботу в Австрії за останні 24 місяці; місяці можна сумувати. Також потрібні загальні умови NAG — достатні кошти, страхування, належне житло — і підтвердження німецької чи інтеграції. Порогові суми змінюються: відкрийте FAQ BMI перед поданням.",
                  "Der Sonderweg setzt das aktuelle Vertriebenenrecht und zwölf Monate vollversicherte Erwerbstätigkeit in Österreich innerhalb der letzten 24 Monate voraus; die Monate können zusammengerechnet werden. Hinzu kommen allgemeine NAG-Voraussetzungen – ausreichende Mittel, Versicherung, geeignete Unterkunft – sowie Deutsch- oder Integrationsnachweis. Geldbeträge ändern sich: Lesen Sie vor dem Antrag die BMI-FAQ."),
            .init("process", "building.2", "Заява й перевірка AMS", "Antrag und AMS-Prüfung",
                  "Заяву подають до органу з питань проживання за адресою в Австрії (у Відні MA 35). Орган перевіряє документи, а AMS підтверджує місяці повного страхування. Перехід добровільний; для переміщених він не має квоти. Якщо сім’я переїжджає пізніше, для неї діє окрема процедура возз’єднання.",
                  "Der Antrag geht an die Aufenthaltsbehörde am Wohnort (in Wien MA 35). Sie prüft die Unterlagen; das AMS bestätigt die vollversicherten Zeiten. Der Umstieg ist freiwillig und für Vertriebene nicht quotenpflichtig. Für später nachziehende Familienmitglieder gilt ein eigenes Verfahren."),
            .init("effect", "arrow.right.circle", "Що зміниться", "Was sich ändert",
                  "RWR+ потребує особистого продовження до закінчення картки. На відміну від тимчасового захисту, для отримання RWR+ не можна отримувати Grundversorgung. Після переходу можливе возз’єднання сім’ї та, за виконання умов, шлях до Daueraufenthalt – EU; попередні періоди захисту безпосередньо перед RWR+ можуть зараховуватися за правилами BMI.",
                  "Die RWR-Karte plus muss vor Ablauf persönlich verlängert werden. Für ihre Erteilung darf anders als beim vorübergehenden Schutz keine Grundversorgung bezogen werden. Der Titel ermöglicht Familiennachzug und bei erfüllten Bedingungen später Daueraufenthalt – EU; unmittelbar vorangehende Schutzzeiten können nach BMI-Regeln angerechnet werden.")
        ], sources: [protectionTransition, rwrPlus, conditions]
    )
}
