import Foundation

enum TransportGuides {
    private static let climate = DirectorySource(name: "KlimaTicket · Gültigkeit", url: "https://www.klimaticket.at/gueltigkeitskarte/")
    private static let regionalTickets = DirectorySource(name: "oesterreich.gv.at · KlimaTicket und regionale Tickets", url: "https://www.oesterreich.gv.at/de/themen/mobilitaet/klimaticket")
    private static let rail = DirectorySource(name: "ÖBB · Tickets und Fahrplan", url: "https://www.oebb.at/de/neuigkeiten/tickets-neuer-fahrplan")
    private static let railRights = DirectorySource(name: "apf · Fahrgastrechte Bahn", url: "https://www.apf.gv.at/bahn-allgemeines")
    private static let railDelay = DirectorySource(name: "ÖBB · Entschädigung bei Zugverspätung", url: "https://www.oebb.at/de/reiseplanung-services/nach-ihrer-reise/fahrgastrechte/zugverspaetungen")
    private static let busRights = DirectorySource(name: "apf · Fahrgastrechte Bus", url: "https://www.apf.gv.at/bus-fahrgastrechte")
    private static let busDelay = DirectorySource(name: "apf · Busverspätung und Ausfall", url: "https://www.apf.gv.at/bus-verspaetung-ausfall")
    private static let taxi = DirectorySource(name: "BMIMI · Gelegenheitsverkehr und Taxi", url: "https://www.bmimi.gv.at/themen/mobilitaet/transport/personen_gueter/recht/gelegenheitsverkehr.html")
    private static let mobility = DirectorySource(name: "ÖBB · Mobilitätsservice", url: "https://www.oebb.at/de/reiseplanung-services/barrierefrei-reisen/mobilitaetsservice")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "local-transport": localTransport
        case "rail": railGuide
        case "bus": bus
        case "taxi": taxiGuide
        case "accessible-travel": accessibleTravel
        default: nil
        }
    }

    private static let localTransport = DirectoryGuide(
        cardSummary: .init(ukrainian: "Місцевий Verkehrsverbund, квиток, зони й пересадки", german: "Verkehrsverbund, Ticket, Zonen und Umsteigen"),
        introduction: .init(ukrainian: "Автобуси, трамваї та міські поїзди входять до регіональних транспортних об’єднань. Умови квитка залежать від землі, маршруту й перевізника.", german: "Bus, Tram und Regionalbahn gehören zu Verkehrsverbünden. Ticketregeln hängen von Bundesland, Strecke und Anbieter ab."),
        sections: [
            .init("plan", "tram", "Знайдіть маршрут", "Verbindung finden", "У планувальнику вашого Verkehrsverbund введіть точну зупинку, дату, час і потребу в безбар’єрному маршруті. Перевірте пересадки, останній рейс та зміни розкладу перед виїздом. При поїздці між землями порівняйте місцевий та загальноавстрійський квиток.", "Im Planer Ihres Verkehrsverbunds genaue Haltestelle, Datum, Uhrzeit und Barrierefreiheit eingeben. Umstiege, letzte Fahrt und Änderungen vor Abfahrt prüfen. Bei länderübergreifender Fahrt Verbund- und österreichweites Ticket vergleichen.", source: regionalTickets),
            .init("ticket", "ticket", "Купіть правильний квиток", "Passendes Ticket kaufen", "Порівняйте разовий, денний, тижневий і річний тариф. Перевірте зони, початок дії, необхідність компостування та знижки для дітей, студентів чи людей з інвалідністю. Квиток або телефон із ним тримайте доступним на весь маршрут; безквитковий штраф може бути вищим за сам проїзд.", "Einzel-, Tages-, Wochen- und Jahrestarif vergleichen. Zonen, Gültigkeitsbeginn, Entwertung und Ermäßigungen für Kinder, Studierende oder Menschen mit Behinderung prüfen. Ticket während der ganzen Fahrt bereithalten; Strafe ohne gültiges Ticket kann deutlich höher sein.", source: regionalTickets),
            .init("climate", "map", "KlimaTicket не покриває все", "KlimaTicket hat Ausnahmen", "KlimaTicket Ö діє на більшості регулярних ліній, але окремі туристичні, спеціальні та аеропортові рейси виключені. Відкрийте офіційну карту винятків перед поїздкою; регіональний KlimaTicket має ще іншу територію дії. Для міжнародної ділянки перевіряйте квиток окремо.", "KlimaTicket Ö gilt in den meisten Linienverkehren, aber touristische, Sonder- und manche Flughafenlinien sind ausgenommen. Vor Fahrt amtliche Ausnahmeliste öffnen; regionale KlimaTickets haben anderes Gebiet. Internationale Abschnitte gesondert prüfen.", source: climate)
        ], sources: [regionalTickets, climate]
    )

    private static let railGuide = DirectoryGuide(
        cardSummary: .init(ukrainian: "Маршрут ÖBB, вид квитка, пересадки й права при затримці", german: "ÖBB-Verbindung, Ticketart, Umstieg und Rechte bei Verspätung"),
        introduction: .init(ukrainian: "Перед оплатою відрізняйте гнучкий квиток від поїздозв’язаного акційного. Перевіряйте перевізника й умови саме вашого тарифу.", german: "Vor der Zahlung flexible und zuggebundene Aktionstickets unterscheiden. Betreiber und Bedingungen Ihres Tarifs prüfen."),
        sections: [
            .init("route", "tram", "Сплануйте всю подорож", "Gesamte Reise planen", "Введіть початкову й кінцеву станції в ÖBB, перевірте дату, пересадки, час на перехід, колію та потребу в резервації місця. Для подорожі через кордон перевірте документи й різних перевізників. Безпосередньо перед виїздом повторно відкрийте актуальний розклад.", "Start und Ziel in ÖBB eingeben; Datum, Umstiege, Übergangszeit, Gleis und Reservierung prüfen. Grenzübertritt erfordert Dokumente und kann mehrere Betreiber betreffen. Kurz vor Abfahrt Live-Fahrplan erneut prüfen.", source: rail),
            .init("fare", "ticket", "Прочитайте правила тарифу", "Tarifbedingungen lesen", "Дешеві Sparschiene-квитки можуть бути прив’язані до поїзда та мати жорсткі умови повернення; інші варіанти гнучкіші. Перевірте ім’я пасажира, дату, вагон і окрему вартість резервації. Не вважайте, що всі квитки ÖBB можна безкоштовно скасувати.", "Sparschiene-Tickets können zuggebunden sein und eingeschränkte Stornorechte haben; andere Tarife sind flexibler. Namen, Datum, Wagen und Reservierungskosten prüfen. Kostenlose Stornierung nicht für jedes ÖBB-Ticket annehmen.", source: rail),
            .init("delay", "clock", "Затримка або скасування", "Verspätung oder Ausfall", "Збережіть квиток, номер поїзда, скриншот запізнення та підтвердження додаткових витрат. Спершу зверніться до перевізника з вимогою про альтернативний маршрут або відшкодування за чинними правилами. Якщо відповідь не вирішила справу, подайте скаргу до незалежної apf; права залежать від виду квитка й конкретної затримки.", "Ticket, Zugnummer, Verspätungsnachweis und Zusatzkosten aufbewahren. Zuerst beim Unternehmen nach Alternative oder Erstattung gemäß geltenden Regeln fragen. Bleibt das Problem offen, Schlichtung bei der unabhängigen apf beantragen; Anspruch hängt von Ticket und Verspätung ab.", source: railRights),
            .init("compensation", "eurosign.circle", "Конкретна компенсація за запізнення", "Konkrete Verspätungsentschädigung", "Для відповідного разового квитка ÖBB затримка прибуття від 60 хвилин зазвичай дає 25 % ціни, від 120 хвилин — 50 %. Підтвердження запізнення можна отримати у персоналу або онлайн протягом семи днів. Це інше право, ніж повернення квитка, коли поїздку не почали. Для сезонних і спеціальних квитків перевірте окремі правила ÖBB.", "Bei einem entsprechenden ÖBB-Einzelticket gibt es bei Ankunft ab 60 Minuten grundsätzlich 25 %, ab 120 Minuten 50 % des Fahrpreises. Verspätungsbestätigung beim Zugpersonal oder binnen sieben Tagen online holen. Das unterscheidet sich von Ticketerstattung bei Nichtantritt. Für Zeit- und Sondertickets eigene ÖBB-Regeln prüfen.", source: railDelay)
        ], sources: [rail, railRights, railDelay]
    )

    private static let bus = DirectoryGuide(
        cardSummary: .init(ukrainian: "Міжміський автобус, багаж, пересадки та скарги", german: "Fernbus, Gepäck, Umstieg und Beschwerde"),
        introduction: .init(ukrainian: "Міжміські автобуси можуть бути комерційними рейсами поза регіональним тарифом. Перед бронюванням читайте умови конкретного перевізника.", german: "Fernbusse können außerhalb des regionalen Verbundtarifs fahren. Vor Buchung Bedingungen des Betreibers lesen."),
        sections: [
            .init("book", "bus", "Перевірте весь маршрут", "Gesamte Strecke prüfen", "Знайдіть точну зупинку, платформу, час прибуття до посадки, кількість багажу й правила для дітей. Перевірте, чи потрібні документи для перетину кордону та чи пересадка гарантована одним договором. KlimaTicket Ö не діє на всіх міжміських автобусах.", "Genaue Haltestelle, Steig, Boardingzeit, Gepäck und Kinderregeln prüfen. Bei Grenzfahrt Dokumente und vertraglich gesicherte Anschlüsse klären. KlimaTicket Ö gilt nicht in jedem Fernbus.", source: busRights),
            .init("change", "arrow.triangle.2.circlepath", "Зміна плану", "Änderung der Reise", "Перед оплатою перевірте строк скасування, ваучер чи повернення коштів, зміну імені та додаткові збори. Під час пересадки закладіть запас часу; якщо рейси куплені окремо, пропущений другий автобус може не компенсуватися.", "Vor Zahlung Stornofrist, Gutschein oder Auszahlung, Namensänderung und Gebühren prüfen. Umsteigezeit einplanen; bei getrennten Buchungen ist der verpasste zweite Bus nicht zwingend ersetzt.", source: busRights),
            .init("rights", "doc.text", "При скасуванні й великій затримці", "Bei Ausfall oder erheblicher Verspätung", "Для регулярних міжміських ліній від 250 км діють ширші права пасажира; на коротших — обмежені. При скасуванні або прогнозованій затримці відправлення понад 120 хвилин запитайте перевізника про альтернативну подорож або повернення. У автобусному праві немає компенсації просто за прибуття із запізненням, як для поїзда. Збережіть квиток і повідомлення; спершу скарга перевізнику, далі apf.", "Für reguläre Fernbuslinien ab 250 km gelten weitergehende Rechte, darunter bei Ausfall oder voraussichtlich über 120 Minuten Abfahrtsverspätung Umleitung oder Erstattung. Unter 250 km gelten nur eingeschränkte Rechte. Anders als bei der Bahn gibt es keine pauschale Entschädigung bloß für verspätete Busankunft. Ticket und Hinweise sichern; zuerst Betreiber, danach apf kontaktieren.", source: busDelay)
        ], sources: [busRights, busDelay, climate]
    )

    private static let taxiGuide = DirectoryGuide(
        cardSummary: .init(ukrainian: "Ліцензоване таксі, тариф, домовлена ціна та чек", german: "Konzessioniertes Taxi, Tarif, Fixpreis und Beleg"),
        introduction: .init(ukrainian: "Правила тарифу можуть відрізнятися між містами й землями. Перед поїздкою дізнайтеся, який саме тариф або погоджена ціна діє.", german: "Taxitarife können je Stadt und Land verschieden sein. Vor Fahrt klären, ob Taxameter oder vereinbarter Fahrpreis gilt."),
        sections: [
            .init("order", "car", "Замовляйте перевірену машину", "Verlässliches Fahrzeug bestellen", "Користуйтеся офіційною стоянкою, диспетчерською або сервісом із даними перевізника. Звірте номер машини й ім’я водія з бронюванням, повідомте близьким маршрут, якщо їдете вночі. Якщо потрібне дитяче крісло або доступне авто, замовляйте заздалегідь.", "Offiziellen Standplatz, Zentrale oder Dienst mit Betreiberangaben nutzen. Fahrzeug und Fahrer mit Buchung abgleichen und bei Nacht die Route mitteilen. Kindersitz oder barrierefreies Fahrzeug vorbestellen.", source: taxi),
            .init("price", "eurosign.circle", "Ціна до початку", "Preis vor Abfahrt", "Назвіть адресу, запитайте, чи діє місцевий тариф таксометра або законно узгоджена фіксована ціна, а також про доплату за багаж чи очікування. Не припускайте, що в усій Австрії один тариф. Попросіть підтвердження погодженої ціни в додатку або повідомленні.", "Zieladresse nennen und nach örtlichem Taxameter-Tarif oder zulässig vereinbartem Fixpreis sowie Gepäck- und Wartezuschlägen fragen. Es gibt keinen österreichweit einheitlichen Taxitarif. Vereinbarten Preis im Auftrag oder in der App sichern.", source: taxi),
            .init("receipt", "doc.text", "Після поїздки", "Nach der Fahrt", "Попросіть чек із назвою компанії, датою, маршрутом і сумою. Якщо ціна інша, ніж погоджено, збережіть бронювання й чек і зверніться до компанії; за підозри на небезпеку — поліція 133. Не передавайте водію документи як заставу.", "Beleg mit Unternehmen, Datum, Strecke und Betrag verlangen. Bei abweichendem Preis Buchung und Beleg sichern und Betreiber kontaktieren; bei Gefahr Polizei 133. Dokumente nicht als Pfand abgeben.", source: taxi)
        ], sources: [taxi]
    )

    private static let accessibleTravel = DirectoryGuide(
        cardSummary: .init(ukrainian: "Допомога ÖBB, доступність пересадок і місце для візка", german: "ÖBB-Hilfe, barrierefreie Umstiege und Rollstuhlplatz"),
        introduction: .init(ukrainian: "Доступність одного поїзда не гарантує доступної пересадки або ліфта на станції. Плануйте весь маршрут разом із перевізником.", german: "Ein zugänglicher Zug garantiert keinen barrierefreien Umstieg oder funktionierenden Aufzug. Planen Sie die gesamte Reisekette."),
        sections: [
            .init("plan", "figure.roll", "Перевірте станції та вагони", "Bahnhöfe und Wagen prüfen", "Під час пошуку маршруту перевірте ліфти, висоту платформ, тип вагона, туалет і місце для візка. Уточніть, чи можна самостійно сісти й вийти та чи потрібен підйомник. Для регіональних автобусів перевірте доступність у місцевого Verkehrsverbund.", "Bei der Planung Lifte, Bahnsteighöhe, Wagenart, WC und Rollstuhlplatz prüfen. Klären, ob selbständiges Ein- und Aussteigen möglich ist und ob Hebehilfe nötig wird. Regionalbusse beim Verkehrsverbund prüfen.", source: mobility),
            .init("assist", "person.2", "Замовте допомогу", "Hilfe anmelden", "У ÖBB Mobilitätsservice повідомте дату, усі станції пересадки, вид обмеження, габарити засобу пересування та контакт. Офіційна сторінка називає строки попереднього запису, які різняться для внутрішніх і міжнародних поїздок; оформіть якомога раніше й дочекайтеся підтвердження. Узгодьте місце зустрічі на вокзалі.", "Dem ÖBB-Mobilitätsservice Datum, alle Umstiegsbahnhöfe, Bedarf, Maße des Hilfsmittels und Kontakt mitteilen. Die amtliche Seite nennt verschiedene Voranmeldefristen für Inland und Ausland; möglichst früh anmelden und Bestätigung abwarten. Treffpunkt am Bahnhof vereinbaren.", source: mobility),
            .init("disruption", "exclamationmark.triangle", "Якщо допомога або ліфт недоступні", "Wenn Hilfe oder Lift ausfallen", "Зв’яжіться із Mobilitätsservice до посадки, попросіть безпечний альтернативний маршрут і зафіксуйте проблему. Не погоджуйтеся на небезпечне перенесення візка. Збережіть квиток, переписку та витрати для скарги перевізнику і, якщо питання не вирішено, до apf.", "Vor Einstieg Mobilitätsservice kontaktieren, sichere Alternative verlangen und Vorfall dokumentieren. Unsicheres Tragen des Rollstuhls nicht akzeptieren. Ticket, Nachrichten und Kosten für Beschwerde beim Betreiber und gegebenenfalls apf sichern.", source: railRights)
        ], sources: [mobility, railRights]
    )
}
