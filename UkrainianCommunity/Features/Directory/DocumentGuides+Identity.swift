import Foundation

extension DocumentGuides {
    static let identity = DirectoryGuide(
        cardSummary: .init(ukrainian: "Не плутайте посвідчення особи, право проживання і проїзний документ", german: "Identität, Aufenthalt und Reisedokument unterscheiden"),
        introduction: .init(ukrainian: "Для різних дій потрібні різні документи. Перш ніж замінювати документ, перевірте його строк, ціль використання й вимоги установи.", german: "Verschiedene Wege brauchen verschiedene Dokumente. Prüfen Sie vor einem Austausch Gültigkeit, Zweck und Anforderungen der zuständigen Stelle."),
        sections: [
            .init("passport", "airplane", "Для кордону", "Für die Grenze",
                  "Закордонний паспорт — основний український проїзний документ. Українська ID-картка, застосунок Дія, Meldezettel і Ausweis für Vertriebene не є його універсальною заміною для міжнародної подорожі. Перед поїздкою перевірте правила країни призначення і повернення до Австрії.",
                  "Der ukrainische Reisepass ist das zentrale Reisedokument. Ukrainische ID-Karte, Diia-App, Meldezettel und Vertriebenenausweis ersetzen ihn nicht allgemein für internationale Reisen. Prüfen Sie vor der Fahrt Regeln des Zielstaats und der Wiedereinreise nach Österreich."),
            .init("stay", "person.text.rectangle", "Для перебування в Австрії", "Für den Aufenthalt in Österreich",
                  "Посвідчення переміщеної особи або інший Aufenthaltstitel підтверджує конкретне право перебування; Meldebestätigung підтверджує адресу. Це різні речі. Під час заяв до органів тримайте разом паспорт, картку статусу й актуальне підтвердження адреси, якщо їх просять.",
                  "Vertriebenenausweis oder anderer Aufenthaltstitel dokumentieren ein konkretes Aufenthaltsrecht; die Meldebestätigung belegt die Adresse. Das sind verschiedene Dinge. Halten Sie bei Behördenwegen Pass, Statuskarte und aktuelle Meldebestätigung bereit, soweit verlangt."),
            .init("need", "checklist", "Що міняти, а що ні", "Was getauscht werden muss",
                  "Не потрібно автоматично міняти чинний паспорт, свідоцтво чи водійське посвідчення лише через переїзд до Австрії. Підстави для обміну — закінчення строку, зміна даних, пошкодження, втрата або вимога конкретної процедури. Для посвідчення водія правила залежать від тимчасового захисту; дивіться окрему тему.",
                  "Gültige Pässe, Urkunden oder Führerscheine müssen nicht allein wegen des Umzugs nach Österreich automatisch getauscht werden. Gründe sind Ablauf, geänderte Daten, Beschädigung, Verlust oder Anforderungen eines Verfahrens. Beim Führerschein hängt der Weg vom vorübergehenden Schutz ab; siehe das eigene Thema."),
            .init("copies", "doc.on.doc", "Зберігайте дані безпечно", "Unterlagen sicher aufbewahren",
                  "Зробіть копії важливих документів і зберігайте їх окремо від оригіналів. Для подання надішліть лише запитані сторінки через офіційний канал. Фото документа у телефоні допоможе відновити реквізити, але не замінює оригінал там, де його вимагають.",
                  "Bewahren Sie Kopien wichtiger Unterlagen getrennt von Originalen auf. Reichen Sie nur verlangte Seiten über amtliche Kanäle ein. Ein Foto hilft beim Wiederfinden von Daten, ersetzt aber kein Original, wenn die Behörde dieses verlangt.")
        ], sources: [passports, inlandID, lostAT]
    )

    static let passport = DirectoryGuide(
        cardSummary: .init(ukrainian: "Де оформити, коли обмінювати, як отримати готовий", german: "Wo beantragen, wann tauschen, wie abholen"),
        introduction: .init(ukrainian: "Український закордонний паспорт видають і за кордоном. Посольство та ДП «Документ» — різні точки обслуговування з різними записами.", german: "Ein ukrainischer Reisepass kann auch im Ausland beantragt werden. Botschaft und DP „Dokument“ sind verschiedene Stellen mit eigenen Terminwegen."),
        sections: [
            .init("where", "building.2", "Де подати", "Wo beantragen",
                  "В Україні звертайтеся до ДМС, ЦНАП або ДП «Документ». За кордоном — до української дипломатичної установи або доступного центру «Паспортний сервіс» ДП «Документ». Перелік центрів і послуг змінюється; перевірте найближчий центр та його запис перед поїздкою. У Відні є посольство; також МЗС називає центри у Братиславі та Празі.",
                  "In der Ukraine sind DMS, Verwaltungszentren oder DP „Dokument“ zuständig. Im Ausland können Sie eine ukrainische Vertretung oder einen verfügbaren Passservice von DP „Dokument“ nutzen. Standorte und Leistungen ändern sich; prüfen Sie Standort und Termin vor der Fahrt. In Wien gibt es die Botschaft; das Außenministerium nennt auch Zentren in Bratislava und Prag."),
            .init("when", "calendar", "Коли оформлювати новий", "Wann ein neuer Pass nötig ist",
                  "МЗС називає закінчення строку, зміну внесених даних, пошкодження або втрату підставами для оформлення чи обміну. Паспорт дитини до 16 років видають на чотири роки, від 16 років — на десять. Якщо документ ще дійсний і дані не змінилися, сам переїзд не зобов’язує міняти його.",
                  "Das Außenministerium nennt Ablauf, Änderung eingetragener Daten, Beschädigung oder Verlust als Gründe für Neuausstellung bzw. Austausch. Vor 16 Jahren gilt der Pass vier, ab 16 Jahren zehn Jahre. Bei gültigem Pass und unveränderten Daten zwingt der Umzug allein nicht zum Austausch."),
            .init("prepare", "doc.text", "Що підготувати", "Was vorbereiten",
                  "На сторінці обраної установи перевірте вимоги до заяви, чинного паспорта або іншого підтвердження особи, документів про зміну даних, фото, оплати й особистої присутності. Для чоловіків 18–60 років можуть діяти додаткові вимоги до актуальності військово-облікових даних; перевірте їх на сторінці МЗС перед записом.",
                  "Prüfen Sie bei der gewählten Stelle Anforderungen zu Antrag, altem Pass oder Identitätsnachweis, Nachweisen über Datenänderung, Foto, Gebühren und persönlicher Vorsprache. Für Männer von 18 bis 60 Jahren können zusätzliche Anforderungen an aktuelle Wehrregisterdaten gelten; prüfen Sie sie vor der Terminbuchung beim Außenministerium."),
            .init("delivery", "envelope", "Готовність і доставка", "Fertigstellung und Zustellung",
                  "Паспорт виготовляють в Україні, тому врахуйте доставку за кордон. МЗС має сторінки перевірки стану й отримання паспорта. Якщо документ оформлено в Україні, але ви виїхали до його видачі, МЗС описує окремий шлях доставки до закордонної установи; спочатку перевірте умови свого випадку.",
                  "Der Pass wird in der Ukraine hergestellt; planen Sie die Auslandszustellung ein. Das Außenministerium bietet Hinweise zur Statusprüfung und Abholung. Wurde der Pass in der Ukraine beantragt, aber vor Abholung reisten Sie aus, beschreibt das Ministerium einen eigenen Zustellweg zur Auslandsvertretung; prüfen Sie die Voraussetzungen Ihres Falls.")
        ], sources: [passports, passportService, passportActions, consularMilitary,
                     DirectorySource(name: "МЗС України · Доставка оформленого паспорта", url: "https://mfa.gov.ua/consul/forua/pass/mail")]
    )

    static let ukrainianID = DirectoryGuide(
        cardSummary: .init(ukrainian: "Внутрішній паспорт не оформлюють у посольстві", german: "Inlandspass wird nicht in der Botschaft ausgestellt"),
        introduction: .init(ukrainian: "ID-картка та паспорт-книжечка посвідчують особу в Україні. Порядок їх заміни відрізняється від закордонного паспорта.", german: "ID-Karte und früherer Inlandspass dienen als ukrainische Identitätsdokumente. Ihr Austausch unterscheidet sich vom Reisepass."),
        sections: [
            .init("where", "building.2", "Де оформлюють", "Wo ausgestellt wird",
                  "Посольство України не оформлює внутрішні ID-картки. В Україні звертайтеся до ДМС, ЦНАП або ДП «Документ». За кордоном послуги ID-картки доступні в окремих центрах ДП «Документ»; перевіряйте чинний перелік, вид послуги та документи на його сайті.",
                  "Die ukrainische Botschaft stellt keine Inlandspässe/ID-Karten aus. In der Ukraine sind DMS, Verwaltungszentren oder DP „Dokument“ zuständig. Im Ausland gibt es ID-Leistungen bei bestimmten DP-„Dokument“-Zentren; prüfen Sie aktuelle Standorte, Leistung und Unterlagen auf deren Website."),
            .init("replace", "arrow.triangle.2.circlepath", "Коли потрібен обмін", "Wann ein Austausch nötig ist",
                  "Перевірте строк ID-картки, цілісність і правильність особистих даних. Зміна прізвища, втрата або пошкодження вимагають з’ясувати порядок обміну. За воєнного стану можуть діяти спеціальні правила для прострочених українських документів усередині України; їх не слід автоматично вважати дозволом на міжнародну подорож.",
                  "Prüfen Sie Gültigkeit, Zustand und persönliche Angaben der ID-Karte. Bei Namensänderung, Verlust oder Beschädigung ist der Austausch zu klären. Während des Kriegsrechts können Sonderregeln für abgelaufene ukrainische Dokumente innerhalb der Ukraine gelten; daraus folgt keine allgemeine internationale Reiseberechtigung."),
            .init("first", "person.crop.rectangle", "Перша ID-картка за кордоном", "Erste ID-Karte im Ausland",
                  "Для оформлення вперше за кордоном, особливо після 18 років, ДМС встановлює окремі вимоги до підтвердження особи та фото-документів. Перевірте свою ситуацію до бронювання: наявність свідоцтва про народження не завжди достатня для дорослого заявника.",
                  "Für die erstmalige Ausstellung im Ausland, besonders nach dem 18. Geburtstag, gelten besondere DMS-Anforderungen an Identitätsnachweis und Lichtbilddokumente. Prüfen Sie Ihren Fall vor der Buchung; eine Geburtsurkunde allein reicht für Erwachsene nicht immer aus.")
        ], sources: [inlandID, dmsID, passportService]
    )
}
