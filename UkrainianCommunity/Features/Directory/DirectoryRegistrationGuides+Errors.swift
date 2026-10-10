import Foundation

extension RegistrationGuides {
    static let errors = DirectoryGuide(
        cardSummary: .init(ukrainian: "Що робити з помилкою в адресі, даних або посвідченні",
                           german: "Fehler bei Adresse, Meldedaten oder Ausweis beheben"),
        introduction: .init(ukrainian: "Спершу визначте, де саме помилка: у реєстрі адрес (ZMR) чи в посвідченні переміщеної особи. Це різні установи.",
                            german: "Prüfen Sie zuerst, wo der Fehler steht: im Melderegister (ZMR) oder im Ausweis für Vertriebene. Dafür sind verschiedene Stellen zuständig."),
        sections: [
            .init("check", "doc.text.magnifyingglass", "Перевірте підтвердження адреси", "Meldebestätigung prüfen",
                  "Після реєстрації звірте ім’я, дату народження, адресу й дату заселення в отриманому підтвердженні. Якщо документ загубили, нову Meldebestätigung можна запросити в Meldebehörde; це окрема послуга, яка може бути платною. Не плутайте її з безкоштовним підтвердженням під час первинної реєстрації.",
                  "Vergleichen Sie nach der Anmeldung Name, Geburtsdatum, Anschrift und Einzugsdatum auf der erhaltenen Bestätigung. Ist sie verloren, können Sie bei der Meldebehörde eine neue Meldebestätigung beantragen; das ist eine gesonderte, möglicherweise gebührenpflichtige Leistung. Sie ist nicht mit der kostenlosen Bestätigung bei der Anmeldung gleichzusetzen.", source: confirmationSource),
            .init("registry", "building.columns.fill", "Помилка в ZMR — до Meldebehörde", "ZMR-Fehler: zur Meldebehörde",
                  "Якщо неправильні дані вже в реєстрі або онлайн-сервіс показує хибну адресу, зверніться до відповідної Meldebehörde особисто. Візьміть документ особи, наявне підтвердження реєстрації та документ, що пояснює правильні дані. Офіційна довідка до онлайн-сервісу прямо вказує: помилкові відображені дані треба з’ясовувати в Meldeamt, а не просто повторювати онлайн-заяву.",
                  "Sind Daten im Register falsch oder zeigt der Online-Dienst eine falsche Adresse, wenden Sie sich an die zuständige Meldebehörde. Nehmen Sie Ausweis, vorhandene Meldebestätigung und einen Nachweis der richtigen Daten mit. Die amtliche Online-Hilfe verweist bei falsch angezeigten Daten ausdrücklich an das Meldeamt; senden Sie die Online-Meldung nicht bloß erneut ab.", source: digitalServiceSource),
            .init("card", "person.text.rectangle.fill", "Помилка або нове ім’я на картці — до BFA", "Fehler oder neuer Name auf der Karte: zum BFA",
                  "Якщо ім’я змінилося після отримання Ausweis für Vertriebene, повідомте BFA: за інформацією BMI, для вас мають видати нову картку. Якщо на картці помилка, зверніться до регіонального відділення BFA з карткою та документами, що підтверджують правильні дані. Уточніть спосіб подання й чи потрібен особистий візит; Meldebehörde не перевидає цю картку.",
                  "Hat sich Ihr Name nach Erhalt des Ausweises für Vertriebene geändert, informieren Sie das BFA: Laut BMI wird ein neuer Ausweis ausgestellt. Bei einem Fehler auf der Karte wenden Sie sich mit Ausweis und Nachweisen der richtigen Daten an die BFA-Regionaldirektion. Fragen Sie nach Einreichweg und persönlichem Termin; die Meldebehörde stellt diesen Ausweis nicht neu aus.", source: bfaNameSource)
        ],
        sources: [addressSource, bfaContactSource]
    )
}
