import Foundation

extension ResidenceGuides {
    static let statusChange = DirectoryGuide(
        cardSummary: .init(ukrainian: "Зміна мети, шлюб, робота або завершення навчання", german: "Zweckwechsel bei Ehe, Arbeit oder Studienabschluss"),
        introduction: .init(ukrainian: "Новий контракт, диплом або шлюб не замінюють рішення про новий дозвіл. З’ясуйте, чи потрібна зміна мети (Zweckänderung), нова заява або спеціальний перехід.", german: "Ein neuer Vertrag, Abschluss oder eine Ehe ersetzen keine Entscheidung über den neuen Titel. Klären Sie, ob Zweckänderung, Erstantrag oder ein besonderer Umstieg erforderlich ist."),
        sections: [
            .init("current", "person.text.rectangle", "Визначте чинну підставу", "Bestehenden Status bestimmen",
                  "Запишіть назву чинного документа, дату закінчення та статус людини, з якою хочете возз’єднатися. Перехід від Student до роботи, від робочої картки до RWR+ і від тимчасового захисту до RWR+ — різні процедури з різними умовами.",
                  "Notieren Sie Bezeichnung und Ablaufdatum Ihres Titels sowie den Status der Person, zu der Sie ziehen möchten. Der Wechsel von Student zu Arbeit, von RWR zu RWR-Karte plus und vom Vertriebenenschutz zu RWR-Karte plus sind verschiedene Verfahren."),
            .init("timing", "calendar.badge.clock", "Подайте до завершення дозволу", "Vor Ablauf beantragen",
                  "Якщо вже маєте дозвіл за NAG, подайте продовження особисто не раніше ніж за три місяці до закінчення та до його завершення. З ним можна поєднати заяву на зміну мети або виду дозволу до рішення першої інстанції. Зберігайте підтвердження своєчасного подання.",
                  "Bei einem bestehenden NAG-Titel beantragen Sie die Verlängerung persönlich frühestens drei Monate vor und vor dessen Ablauf. Damit lässt sich bis zur erstinstanzlichen Entscheidung ein Antrag auf Änderung von Zweck oder Titel verbinden. Bewahren Sie den Nachweis des rechtzeitigen Antrags auf."),
            .init("first", "exclamationmark.circle", "Перша заява й законне перебування", "Erstantrag und rechtmäßiger Aufenthalt",
                  "Якщо це перша заява на дозвіл, правила інші: подати її в Австрії можуть лише визначені групи та під час законного перебування. Віза або безвіз зазвичай не продовжуються через подання. Не починайте нову роботу лише на підставі квитанції про заяву; перевірте чинне право працювати.",
                  "Beim Erstantrag gelten andere Regeln: Im Inland dürfen nur bestimmte Gruppen während rechtmäßigen Aufenthalts beantragen. Visum oder visumfreie Zeit werden durch den Antrag grundsätzlich nicht verlängert. Beginnen Sie eine neue Beschäftigung nicht allein aufgrund einer Antragsbestätigung; prüfen Sie das bestehende Arbeitsrecht."),
            .init("protection", "shield", "Окремо для переміщених", "Sonderfall Vertriebene",
                  "Для осіб із тимчасовим захистом BMI описує спеціальний перехід на RWR+ за умови 12 місяців повного страхування через роботу за останні 24 місяці та інших вимог. Це не звичайне продовження картки переміщеної особи. Інші цілі — навчання, сім’я, робота — мають окремі правові правила; до подання з’ясуйте актуально допустимий шлях у органу.",
                  "Für Vertriebene beschreibt das BMI einen Sonderumstieg zur RWR-Karte plus nach zwölf Monaten vollversicherter Erwerbstätigkeit in den letzten 24 Monaten und weiteren Voraussetzungen. Das ist keine normale Verlängerung des Vertriebenenausweises. Studium, Familie und Arbeit haben eigene Regeln; klären Sie den aktuell zulässigen Weg vor Antragstellung mit der Behörde.")
        ], sources: [renewal, firstApplication, protectionTransition, student]
    )

    static let residenceRenewal = DirectoryGuide(
        cardSummary: .init(ukrainian: "Строк подання, право під час розгляду й зміна мети", german: "Frist, Rechte während des Verfahrens und Zweckänderung"),
        introduction: .init(ukrainian: "Це про продовження вже виданого дозволу на проживання за NAG. Посвідчення переміщеної особи продовжується за окремими правилами BMI.", german: "Dies betrifft die Verlängerung eines bereits erteilten NAG-Aufenthaltstitels. Für den Vertriebenenausweis gelten eigene BMI-Regeln."),
        sections: [
            .init("deadline", "calendar.badge.exclamationmark", "Коли подавати", "Wann beantragen",
                  "Подайте особисто до закінчення чинного дозволу, але не раніше ніж за три місяці до цієї дати. Компетентний орган — за вашим місцем проживання в Австрії. Пізню заяву зазвичай розглядають як першу; вузькі винятки стосуються непередбачуваної чи неминучої перешкоди та короткого строку після її усунення.",
                  "Beantragen Sie persönlich vor Ablauf des Titels, jedoch frühestens drei Monate davor, bei der Behörde Ihres österreichischen Wohnorts. Ein später Antrag gilt grundsätzlich als Erstantrag; enge Ausnahmen betreffen ein unabwendbares oder unvorhergesehenes Hindernis und eine kurze Frist nach dessen Wegfall."),
            .init("pending", "hourglass", "Поки орган розглядає заяву", "Während der Bearbeitung",
                  "Своєчасна заява зберігає право перебування до рішення, а доступ до ринку праці залишається таким, як за попереднім дозволом. Збережіть підтвердження подання. Для поїздок за кордон під час розгляду уточніть у органу, чи потрібна платна Notvignette для повернення.",
                  "Ein rechtzeitiger Antrag erhält das Aufenthaltsrecht bis zur Entscheidung; der Arbeitsmarktzugang bleibt wie beim bisherigen Titel. Bewahren Sie den Einreichnachweis auf. Fragen Sie vor Auslandsreisen während des Verfahrens nach einer gegebenenfalls nötigen gebührenpflichtigen Notvignette für die Wiedereinreise."),
            .init("proof", "doc.text", "Підтвердьте умови заново", "Voraussetzungen erneut nachweisen",
                  "При продовженні перевіряють загальні й спеціальні умови вашого дозволу, іноді виконання інтеграційних вимог. Для студентів потрібен доказ навчального успіху; для сімейних дозволів — актуальні сімейні та фінансові документи. Точний перелік залежить від виду картки.",
                  "Bei der Verlängerung werden allgemeine und besondere Voraussetzungen des Titels, gegebenenfalls die Integrationsvereinbarung, erneut geprüft. Studierende brauchen Studienerfolgsnachweise; bei Familientiteln sind aktuelle Familien- und Finanzunterlagen relevant. Die Liste hängt vom konkreten Titel ab."),
            .init("new-purpose", "arrow.triangle.branch", "Якщо мета змінилася", "Wenn der Zweck wechselt",
                  "Повідомте про нову роботу, завершення навчання чи зміну сімейної ситуації й перевірте Zweckänderung. Її можна поєднати зі своєчасним продовженням. Права за новою підставою не виникають автоматично лише від подання заяви.",
                  "Melden Sie neue Arbeit, Studienabschluss oder geänderte Familienverhältnisse und prüfen Sie eine Zweckänderung. Sie kann mit einer rechtzeitigen Verlängerung verbunden werden. Rechte aus dem neuen Zweck entstehen nicht automatisch schon durch Antragstellung.")
        ], sources: [renewal, student, permits]
    )

    static let permanentResidence = DirectoryGuide(
        cardSummary: .init(ukrainian: "П’ять років, інтеграція й особливості захисту", german: "Fünf Jahre, Integration und Besonderheiten beim Schutz"),
        introduction: .init(ukrainian: "Daueraufenthalt – EU є окремим дозволом для громадян третіх країн після тривалого законного оселення. Він не виникає автоматично після п’яти років.", german: "Daueraufenthalt – EU ist ein eigener Titel für Drittstaatsangehörige nach längerer rechtmäßiger Niederlassung. Er entsteht nicht automatisch nach fünf Jahren."),
        sections: [
            .init("five", "calendar", "Основні умови", "Grundvoraussetzungen",
                  "Зазвичай потрібні п’ять років безперервного фактичного й законного оселення в Австрії, виконаний модуль 2 інтеграційної угоди та загальні умови дозволу. Перерви й поїздки за межі ЄЕЗ можуть впливати на підрахунок. Попросіть орган перевірити саме ваші періоди й документи.",
                  "Grundsätzlich sind fünf Jahre durchgehende tatsächliche und rechtmäßige Niederlassung in Österreich, Modul 2 der Integrationsvereinbarung und allgemeine Voraussetzungen nötig. Unterbrechungen und Aufenthalte außerhalb des EWR können die Berechnung beeinflussen. Lassen Sie Ihre Zeiten und Unterlagen individuell prüfen."),
            .init("study", "graduationcap", "Навчання не завжди є оселенням", "Studium ist nicht immer Niederlassung",
                  "Тимчасова Aufenthaltsbewilligung – Student відрізняється від дозволу на оселення. Після переходу на дозвіл для оселення студентські періоди за визначених умов можуть зараховуватися лише наполовину. Не рахуйте їх як повні роки; збережіть попередні картки й попросіть орган перевірити обчислення.",
                  "Die befristete Aufenthaltsbewilligung – Student unterscheidet sich von einem Niederlassungstitel. Nach einem Wechsel zu einem Niederlassungstitel können Studienzeiten unter bestimmten Voraussetzungen nur zur Hälfte angerechnet werden. Zählen Sie diese nicht als volle Jahre; bewahren Sie frühere Karten auf und lassen Sie die Berechnung prüfen."),
            .init("ukraine", "shield", "Попередній тимчасовий захист", "Früherer vorübergehender Schutz",
                  "Із посвідчення переміщеної особи безпосередньо перейти на Daueraufenthalt – EU не можна. Після одержання спеціальної RWR+ попередні безпосередні періоди тимчасового захисту можуть зараховуватися до п’ятирічного строку за правилами BMI. Перевірте точний розрахунок у органу до подання.",
                  "Vom Vertriebenenausweis ist kein direkter Wechsel zu Daueraufenthalt – EU möglich. Nach Erteilung der besonderen RWR-Karte plus können unmittelbar vorangehende Zeiten des vorübergehenden Schutzes nach BMI-Regeln auf fünf Jahre angerechnet werden. Lassen Sie die genaue Berechnung vor Antragstellung prüfen."),
            .init("different", "person.2", "Сім’я громадянина ЄС", "Familie von EU-Bürgern",
                  "Для членів сім’ї громадян ЄС / ЄЕЗ / Швейцарії, які перебувають за правом вільного пересування, після п’яти років передбачена Daueraufenthaltskarte. Це інша процедура й інший документ, ніж Daueraufenthalt – EU.",
                  "Für Familienangehörige von EU-/EWR-/Schweizer Bürgern mit unionsrechtlichem Aufenthaltsrecht gibt es nach fünf Jahren die Daueraufenthaltskarte. Das ist ein anderes Verfahren und Dokument als Daueraufenthalt – EU."),
            .init("apply", "building.2", "Заява й тривала відсутність", "Antrag und längere Abwesenheit",
                  "Подайте заяву особисто під час чинності теперішнього дозволу. Право Daueraufenthalt – EU є безстроковим, але картку треба оновлювати. Тривала відсутність поза ЄЕЗ може припинити право навіть до закінчення строку картки; перед переїздом чи довгою подорожжю перевірте офіційні межі й винятки.",
                  "Stellen Sie den Antrag persönlich während der Gültigkeit Ihres aktuellen Titels. Das Daueraufenthaltsrecht ist unbefristet, die Karte muss jedoch erneuert werden. Längere Abwesenheit außerhalb des EWR kann das Recht auch vor Ablauf der Karte beenden; prüfen Sie vor Umzug oder langer Reise amtliche Fristen und Ausnahmen.")
        ], sources: [permanent, protectionTransition, euFamily, conditions,
                     DirectorySource(name: "BMI · RWR-Karte für Studienabsolventen", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/2/2/Seite.120229")]
    )
}
