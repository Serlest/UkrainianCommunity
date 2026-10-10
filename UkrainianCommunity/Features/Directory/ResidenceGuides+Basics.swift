import Foundation

extension ResidenceGuides {
    static let overview = DirectoryGuide(
        cardSummary: .init(ukrainian: "Віза, захист, дозвіл на проживання: різні підстави", german: "Visum, Schutz und Aufenthaltstitel unterscheiden"),
        introduction: .init(ukrainian: "Спершу визначте громадянство, мету й тривалість перебування та чинний документ. Від цього залежить правильна процедура.", german: "Klären Sie zuerst Staatsangehörigkeit, Aufenthaltszweck, Dauer und bestehendes Dokument. Daraus ergibt sich das passende Verfahren."),
        sections: [
            .init("short", "clock", "Коротка поїздка й віза", "Kurzaufenthalt und Visum",
                  "Шенгенська віза C стосується перебування до 90 днів у 180-денний період; національна віза D зазвичай покриває 91 день — шість місяців. Безвізовий в’їзд теж має власний строк. Віза або Meldezettel самі по собі не є дозволом на довгострокове проживання чи роботу.",
                  "Ein Schengen-Visum C betrifft bis zu 90 Tage in 180 Tagen; ein nationales Visum D gilt grundsätzlich für 91 Tage bis sechs Monate. Auch die visumfreie Einreise ist zeitlich begrenzt. Visum oder Meldezettel allein sind kein Titel für längeren Aufenthalt oder Arbeit."),
            .init("long", "person.text.rectangle", "Понад шість місяців", "Mehr als sechs Monate",
                  "Громадянам третіх країн зазвичай потрібен дозвіл відповідно до мети: навчання, робота, сім’я чи інша визначена законом підстава. Картка переміщеної особи є окремим режимом. Для громадян ЄС / ЄЕЗ / Швейцарії діють інші правила документування права на перебування.",
                  "Drittstaatsangehörige brauchen meist einen Titel für den konkreten Zweck: Studium, Arbeit, Familie oder einen anderen gesetzlich vorgesehenen Grund. Der Ausweis für Vertriebene beruht auf einem eigenen Schutzsystem. Für EU-/EWR-/Schweizer Bürger gelten andere Regeln zur Dokumentation des Aufenthaltsrechts."),
            .init("requirements", "checklist", "Що перевіряє орган", "Was die Behörde prüft",
                  "Залежно від дозволу перевіряють спеціальні умови та загальні вимоги: кошти, медичне страхування, житло, паспорт, іноді знання німецької. Є винятки: наприклад, для RWR-картки й Blue Card EU не вимагають окремого доказу коштів за загальним правилом NAG. Перевіряйте саме сторінку свого дозволу.",
                  "Je nach Titel prüft die Behörde besondere und allgemeine Voraussetzungen: Mittel, Krankenversicherung, Unterkunft, Pass und teils Deutschkenntnisse. Ausnahmen bestehen, etwa beim Nachweis des Lebensunterhalts für RWR-Karte und Blaue Karte EU. Maßgeblich ist die amtliche Seite zum konkreten Titel."),
            .init("apply", "building.2", "Куди подавати заяву", "Wo der Antrag gestellt wird",
                  "Першу заяву зазвичай подають особисто в австрійському представництві за кордоном. Для деяких груп дозволене подання під час законного перебування в Австрії. Подання першої заяви зазвичай не продовжує візу чи безвіз; перевірте це до закінчення строку. Компетентний орган в Австрії — Bezirkshauptmannschaft або Magistrat, у Відні MA 35.",
                  "Der Erstantrag wird grundsätzlich persönlich bei einer österreichischen Vertretung im Ausland gestellt. Bestimmte Gruppen können während rechtmäßigen Aufenthalts in Österreich beantragen. Ein Erstantrag verlängert Visum oder visumfreie Zeit grundsätzlich nicht. Im Inland ist die Bezirkshauptmannschaft oder der Magistrat zuständig, in Wien MA 35.")
        ], sources: [visa, permits, conditions, firstApplication]
    )

    static let temporaryProtection = DirectoryGuide(
        cardSummary: .init(ukrainian: "Хто має право, строк, робота й поїздки", german: "Anspruch, Dauer, Arbeit und Reisen"),
        introduction: .init(ukrainian: "Тимчасовий захист для переміщених з України — особливе право перебування. Його умови та зміни публікує МВД Австрії (BMI).", german: "Der vorübergehende Schutz für Vertriebene aus der Ukraine ist ein eigenes Aufenthaltsrecht. Voraussetzungen und Änderungen veröffentlicht das BMI."),
        sections: [
            .init("who", "person.crop.rectangle", "Кому може належати захист", "Wer geschützt sein kann",
                  "Право залежить від громадянства, проживання й статусу в Україні та родинного зв’язку. Для нових випадків з 4 серпня 2026 року BMI вимагає дотримання військових обов’язків за українським правом незалежно від віку й статі. За потреби доказом може бути штамп законного виїзду з України або підтвердження Міноборони України, зокрема в «Резерв+». Умова не стосується тих, хто мав захист в Австрії не пізніше 4 серпня 2026 року й безперервно зберігав його. За складних обставин уточніть докази в органі реєстрації.",
                  "Der Anspruch hängt von Staatsangehörigkeit, Aufenthalt und Status in der Ukraine sowie Familienbeziehungen ab. Für neue Fälle seit 4. August 2026 verlangt das BMI die Erfüllung ukrainischer militärischer Pflichten, unabhängig von Alter und Geschlecht. Als Nachweis kommen gegebenenfalls ein Stempel über die rechtmäßige Ausreise oder eine Bestätigung des ukrainischen Verteidigungsministeriums, auch in „Reserv+“, infrage. Wer spätestens am 4. August 2026 Schutz in Österreich hatte und ihn seither ununterbrochen behielt, ist ausgenommen. Klären Sie Sonderfälle mit der Erfassungsstelle."),
            .init("validity", "calendar", "Строк і посвідчення", "Dauer und Ausweis",
                  "За повідомленням BMI право тимчасового перебування продовжено до 4 березня 2028 року; загальний режим може бути припинений раніше рішенням на рівні ЄС. BFA видає Ausweis für Vertriebene після поліцейської реєстрації. Строк на старій картці не завжди показує актуальний строк права — звіряйте оголошення BMI. Реєстрація адреси відбувається окремо.",
                  "Laut BMI ist das vorübergehende Aufenthaltsrecht bis 4. März 2028 verlängert; eine frühere Beendigung auf EU-Ebene bleibt möglich. Nach polizeilicher Erfassung stellt das BFA den Ausweis für Vertriebene aus. Das Datum auf einer älteren Karte zeigt nicht immer die aktuelle Rechtslage; prüfen Sie BMI-Mitteilungen. Die Wohnsitzmeldung erfolgt gesondert."),
            .init("rights", "briefcase", "Робота, навчання, страхування", "Arbeit, Bildung und Versicherung",
                  "Захист дає вільний доступ до ринку праці. Діти можуть відвідувати школу. Медичне страхування не виникає лише через картку: перевірте страхування через роботу, сім’ю, самостійне страхування або Grundversorgung. Фінансова допомога оформлюється окремо за правилами федеральної землі.",
                  "Der Schutz eröffnet freien Arbeitsmarktzugang. Kinder können zur Schule gehen. Krankenversicherung entsteht nicht allein durch die Karte: Prüfen Sie Versicherung durch Arbeit, Familie, Selbstversicherung oder Grundversorgung. Finanzielle Hilfe wird im Bundesland gesondert beantragt."),
            .init("other-state", "globe.europe.africa", "Захист в іншій державі ЄС", "Schutz in einem anderen EU-Staat",
                  "Якщо ви вже мали тимчасовий захист в іншій країні, повідомте про це. Для реєстрації в Австрії BMI вимагає доказу припинення тамтешнього захисту й виплат. Перед переїздом уточніть процедуру зняття з обліку та збережіть письмові підтвердження.",
                  "Hatten Sie bereits vorübergehenden Schutz in einem anderen Staat, geben Sie dies an. Das BMI verlangt für die Erfassung in Österreich Nachweise, dass dortiger Schutz und Leistungen beendet wurden. Klären Sie vor dem Umzug die Abmeldung und bewahren Sie schriftliche Bestätigungen auf."),
            .init("travel", "airplane", "Подорожі й довга відсутність", "Reisen und längere Abwesenheit",
                  "Для поїздок потрібен дійсний проїзний документ; посвідчення переміщеної особи не замінює паспорт. Перед тривалим виїздом або переїздом перевірте вплив на право перебування, Grundversorgung і реєстрацію адреси в BMI та відповідних органах.",
                  "Für Reisen benötigen Sie ein gültiges Reisedokument; der Vertriebenenausweis ersetzt keinen Reisepass. Vor längerer Abwesenheit oder Umzug prüfen Sie Folgen für Aufenthaltsrecht, Grundversorgung und Wohnsitzmeldung beim BMI und den zuständigen Stellen.")
        ], sources: [protection, protectionTransition]
    )
}
