import Foundation

extension ResidenceGuides {
    static let austrianFamilyGuide = DirectoryGuide(
        cardSummary: .init(ukrainian: "Шлюб, партнерство, діти й дозвіл Familienangehöriger", german: "Ehe, Partnerschaft, Kinder und Titel Familienangehöriger"),
        introduction: .init(ukrainian: "Якщо партнер — громадянин Австрії, що постійно живе тут і не використав право вільного пересування ЄС, для члена сім’ї з третьої країни зазвичай передбачений дозвіл «Familienangehöriger».", german: "Ist die Bezugsperson österreichischer Staatsbürger mit dauerhaftem Wohnsitz hier und ohne Nutzung der EU-Freizügigkeit, kommt für Drittstaatsangehörige meist der Titel „Familienangehöriger“ in Betracht."),
        sections: [
            .init("who", "person.2.fill", "Хто належить до сім’ї", "Wer zur Kernfamilie gehört",
                  "Подати можуть подружжя, зареєстровані партнери та неодружені неповнолітні діти, включно з усиновленими й пасинками. Подружжю або партнерам на день подання має бути щонайменше 21 рік. Для батьків, фактичних партнерів та інших родичів є окремий, зазвичай суворіший вид дозволу.",
                  "Antragsberechtigt sind Ehegatten, eingetragene Partner und ledige minderjährige Kinder einschließlich Adoptiv- und Stiefkinder. Ehegatten und Partner müssen bei Antragstellung mindestens 21 Jahre alt sein. Für Eltern, Lebenspartner und weitere Angehörige gibt es einen anderen, meist strengeren Titel."),
            .init("conditions", "checklist", "Умови та докази", "Voraussetzungen und Nachweise",
                  "Потрібні документ про шлюб або спорідненість, паспорт і фото, а також виконання загальних умов: забезпечення життя, страхування й належне житло. Для першого дозволу зазвичай потрібна німецька до в’їзду, якщо немає винятку. Можуть вимагати переклад чи легалізацію документів.",
                  "Benötigt werden Ehe- oder Verwandtschaftsurkunde, Pass und Foto sowie die allgemeinen Voraussetzungen: gesicherter Lebensunterhalt, Versicherung und geeignete Unterkunft. Beim Erstantrag ist grundsätzlich Deutsch vor Zuwanderung nötig, sofern keine Ausnahme greift. Übersetzung oder Beglaubigung kann verlangt werden."),
            .init("apply", "building.2", "Подання в Австрії чи за кордоном", "Antrag im Inland oder Ausland",
                  "Перша заява можлива в австрійському представництві за кордоном або після законного в’їзду під час законного перебування в Австрії. Подання в Австрії не дозволяє чекати рішення після завершення візи чи безвізу: якщо до того часу дозвіл не виданий, зазвичай потрібно виїхати. Шлюбний акт сам по собі не продовжує перебування.",
                  "Der Erstantrag ist bei der österreichischen Vertretung im Ausland oder nach rechtmäßiger Einreise während rechtmäßigen Aufenthalts in Österreich möglich. Der Inlandsantrag erlaubt kein Abwarten nach Ablauf von Visum oder visumfreier Zeit: Ist der Titel bis dahin nicht erteilt, ist grundsätzlich auszureisen. Die Heiratsurkunde verlängert den Aufenthalt nicht."),
            .init("rights", "briefcase", "Після видачі дозволу", "Nach Erteilung",
                  "«Familienangehöriger» дає строкове право жити в Австрії й необмежений доступ до роботи. Якщо австрійський партнер справді використав право вільного пересування ЄС та повернувся, може діяти інший маршрут — Aufenthaltskarte; перевірте окрему тему про сім’ю громадянина ЄС.",
                  "„Familienangehöriger“ erlaubt befristete Niederlassung und unbeschränkten Arbeitsmarktzugang. Hat die österreichische Bezugsperson tatsächlich die EU-Freizügigkeit ausgeübt und ist zurückgekehrt, kann stattdessen die Aufenthaltskarte einschlägig sein; prüfen Sie das eigene EU-Familienthema.")
        ], sources: [austrianFamily, conditions, firstApplication, thirdCountryFamily]
    )

    static let euFamilyGuide = DirectoryGuide(
        cardSummary: .init(ukrainian: "Право сім’ї громадянина ЄС, ЄЕЗ або Швейцарії", german: "Familienrecht bei EU-/EWR-/Schweizer Bürgern"),
        introduction: .init(ukrainian: "Це маршрут за правилами вільного пересування. Він відрізняється від дозволу для сім’ї австрійця, який не користувався таким правом.", german: "Dieser Weg beruht auf der Freizügigkeit. Er unterscheidet sich vom Titel für die Familie eines Österreichers ohne ausgeübte Freizügigkeit."),
        sections: [
            .init("sponsor", "globe.europe.africa", "Право особи, до якої ви переїжджаєте", "Recht der Bezugsperson",
                  "Громадянин ЄС / ЄЕЗ / Швейцарії може перебувати понад три місяці, якщо виконує умови права ЄС, наприклад працює, навчається або має достатні кошти й страхування. Йому потрібна Anmeldebescheinigung протягом чотирьох місяців після в’їзду. Окремо зареєструйте адресу проживання.",
                  "EU-/EWR-/Schweizer Bürger dürfen bei erfüllten unionsrechtlichen Bedingungen länger als drei Monate bleiben, etwa durch Arbeit, Studium oder ausreichende Mittel und Versicherung. Die Anmeldebescheinigung ist binnen vier Monaten nach Einreise zu beantragen. Die Wohnsitzmeldung ist gesondert erforderlich."),
            .init("card", "person.text.rectangle", "Якщо член сім’ї з третьої країни", "Wenn Angehörige Drittstaatsangehörige sind",
                  "Подружжя, зареєстровані партнери, діти до 21 року та певні утримувані старші діти чи батьки можуть мати похідне право перебування. Для перебування понад три місяці подайте заяву на Aufenthaltskarte в органі проживання; вона також підтверджує вільний доступ до роботи. Для дальших родичів діють окремі умови.",
                  "Ehegatten, eingetragene Partner, Kinder unter 21 Jahren und bestimmte unterhaltsberechtigte ältere Kinder oder Eltern können ein abgeleitetes Aufenthaltsrecht haben. Für mehr als drei Monate beantragen sie bei der Aufenthaltsbehörde eine Aufenthaltskarte; sie dokumentiert auch freien Arbeitsmarktzugang. Für weitere Angehörige gelten eigene Bedingungen."),
            .init("austrian", "arrow.uturn.backward", "Австрієць після життя в іншій країні ЄЕЗ", "Österreicher nach Aufenthalt im EWR-Ausland",
                  "Для родини громадянина Австрії цей маршрут можливий, якщо він реально скористався правом вільного пересування в іншій державі ЄЕЗ, а потім повернувся. Саме австрійське громадянство без такої історії не робить сім’ю автоматично учасниками цього маршруту.",
                  "Für Familien österreichischer Staatsbürger kommt dieser Weg in Betracht, wenn die Bezugsperson die Freizügigkeit tatsächlich in einem anderen EWR-Staat genutzt hat und danach zurückkehrte. Österreichische Staatsbürgerschaft allein eröffnet diesen Weg nicht automatisch."),
            .init("five", "calendar", "П’ять років", "Nach fünf Jahren",
                  "Після п’яти років безперервного правомірного перебування за цими правилами член сім’ї з третьої країни може подати на Daueraufenthaltskarte. Це інший документ, ніж Daueraufenthalt – EU за правилами для інших громадян третіх країн.",
                  "Nach fünf Jahren durchgehendem rechtmäßigem Aufenthalt nach diesen Regeln kann ein drittstaatsangehöriges Familienmitglied eine Daueraufenthaltskarte beantragen. Sie ist ein anderes Dokument als der Daueraufenthalt – EU nach den allgemeinen Drittstaatsregeln.")
        ], sources: [euFamily, austrianFamily]
    )
}
