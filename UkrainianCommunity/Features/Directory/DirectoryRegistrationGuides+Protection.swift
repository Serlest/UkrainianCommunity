import Foundation

extension RegistrationGuides {
    static let protection = DirectoryGuide(
        cardSummary: .init(ukrainian: "Умови, пункт поліції, документи й процедура",
                           german: "Voraussetzungen, Polizeistelle, Unterlagen und Ablauf"),
        introduction: .init(ukrainian: "Для людей з України, які відповідають умовам тимчасового захисту, поліція проводить окрему реєстрацію. Meldezettel і заява на Grundversorgung — інші процедури.",
                            german: "Für Menschen aus der Ukraine mit Anspruch auf vorübergehenden Schutz erfasst die Polizei die Daten gesondert. Meldezettel und Antrag auf Grundversorgung sind andere Verfahren."),
        sections: [
            .init("eligibility", "person.crop.rectangle", "Перевірте, чи поширюється захист", "Anspruch auf Schutz prüfen",
                  "Спершу перевірте право на захист за громадянством, попереднім проживанням і статусом в Україні та сімейними обставинами. Для нової реєстрації діють правила щодо виконання військових обов’язків за українським правом; вони не обмежені чоловіками. Візьміть наявний доказ законного виїзду або виконання чи звільнення від обов’язків. Хто мав захист в Австрії станом на 4 серпня 2026 року й зберігав його безперервно, під цю нову вимогу не підпадає. Докладні умови — в темі «Тимчасовий захист» і FAQ BMI.",
                  "Prüfen Sie zuerst den Anspruch anhand von Staatsangehörigkeit, früherem Aufenthalt und Status in der Ukraine sowie Familienumständen. Bei neuer Erfassung gelten Regeln zur Erfüllung ukrainischer militärischer Pflichten; sie betreffen nicht nur Männer. Bringen Sie vorhandene Nachweise zur rechtmäßigen Ausreise oder zur Erfüllung beziehungsweise Befreiung mit. Wer spätestens am 4. August 2026 Schutz in Österreich hatte und ihn durchgehend behielt, fällt nicht unter die neue Anforderung. Details stehen unter „Vorübergehender Schutz“ und in den BMI-FAQ."),
            .init("other-country", "globe.europe.africa.fill", "Якщо був захист в іншій країні", "Wenn Sie in einem anderen Land geschützt waren",
                  "Повідомте про попередній тимчасовий захист. Для реєстрації в Австрії потрібно підтвердити, що захист в іншій країні вже не діє і там більше не виплачують допомогу. BMI наводить як приклад довідку про зняття з обліку, але допускає й інші докази. Самостійно оцінювати достатність документів не варто — уточніть це в органі реєстрації.",
                  "Geben Sie früheren vorübergehenden Schutz an. Für die Erfassung in Österreich ist nachzuweisen, dass der Schutz im anderen Staat beendet ist und dort keine Leistungen mehr bezogen werden. Das BMI nennt eine Abmeldebestätigung als Beispiel, lässt aber andere Nachweise zu. Klären Sie deren Eignung mit der Erfassungsstelle."),
            .init("office", "building.2.fill", "Знайдіть пункт поліції", "Polizeiliche Erfassungsstelle finden",
                  "На сторінці BMI є перелік Erfassungsstellen за федеральними землями з адресами, телефонами, годинами й доступністю. Перед візитом перевірте, чи потрібен запис: правила різняться між пунктами. Це не звичайний запис на Meldezettel.",
                  "Auf der BMI-Seite stehen die Erfassungsstellen nach Bundesland mit Adresse, Telefon, Zeiten und Barrierefreiheit. Prüfen Sie vor dem Besuch die Terminpflicht; sie unterscheidet sich je nach Stelle. Das ist kein Termin für den Meldezettel."),
            .init("papers", "doc.text.fill", "Візьміть наявні документи", "Vorhandene Unterlagen mitnehmen",
                  "Візьміть паспорт, свідоцтва про народження й шлюб та інші посвідчення особи, які маєте. Якщо чогось бракує, BMI радить усе одно пройти реєстрацію, якщо ви належите до відповідної групи. BFA може пізніше запросити додаткові відомості.",
                  "Nehmen Sie vorhandene Reisepässe, Geburts- und Heiratsurkunden sowie andere Ausweise mit. Fehlt etwas, empfiehlt das BMI die Erfassung dennoch, wenn Sie zur geschützten Gruppe gehören. Das BFA kann später weitere Angaben anfordern."),
            .init("process", "person.text.rectangle", "Що відбувається на місці", "Ablauf vor Ort",
                  "Поліція записує особисті дані та відомості з документів, фотографує кожну людину й просить заповнити та підписати форму. Від 14 років беруть відбитки пальців. Для посвідчення потрібна актуальна адреса для доставки.",
                  "Die Polizei erfasst Personendaten und Dokumente, fotografiert jede Person und lässt ein Formular ausfüllen und unterschreiben. Ab 14 Jahren werden Fingerabdrücke abgenommen. Für die Zustellung des Ausweises wird eine aktuelle Adresse benötigt.")
        ],
        sources: [registrationSource]
    )

    static let afterRegistration = DirectoryGuide(
        cardSummary: .init(ukrainian: "Доставка картки, неповні дані й контакт BFA",
                           german: "Zustellung, fehlende Angaben und BFA-Kontakt"),
        introduction: .init(ukrainian: "Після поліцейської реєстрації посвідчення переміщеної особи оформлює BFA. Окрему заяву на картку зазвичай подавати не потрібно.",
                            german: "Nach der polizeilichen Erfassung stellt das BFA den Ausweis für Vertriebene aus. Ein eigener Kartenantrag ist normalerweise nicht nötig."),
        sections: [
            .init("delivery", "envelope.fill", "Куди прийде посвідчення", "Wohin der Ausweis kommt",
                  "BFA надсилає картку на вашу зареєстровану адресу, адресу доставки, указану під час реєстрації, або уповноваженій особі. Доставка може тривати кілька тижнів. Переконайтеся, що адреса в Meldebehörde правильна, а ваше ім’я є на поштовій скриньці.",
                  "Das BFA sendet den Ausweis an die Meldeadresse, die bei der Erfassung angegebene Zustelladresse oder eine zustellbevollmächtigte Person. Die Zustellung kann einige Wochen dauern. Prüfen Sie Ihre Meldedaten und den Namen am Briefkasten."),
            .init("missing", "doc.questionmark.fill", "Якщо даних бракує", "Wenn Angaben fehlen",
                  "BFA може запросити вас для уточнення даних, нового фото або відбитків пальців. Не ігноруйте листи від BFA; підготуйте документи, про які вас попросять. Відсутність усіх документів під час першої реєстрації не є причиною відкладати її.",
                  "Das BFA kann Sie für weitere Angaben, ein neues Foto oder Fingerabdrücke kontaktieren. Beachten Sie Schreiben des BFA und bringen Sie die angeforderten Unterlagen mit. Fehlende Dokumente bei der ersten Erfassung sind kein Grund, sie aufzuschieben."),
            .init("delay", "phone.fill", "Якщо картка не надходить", "Wenn der Ausweis nicht ankommt",
                  "Спершу перевірте реєстрацію адреси та поштову скриньку. Якщо минуло кілька тижнів і звістки немає, зверніться до регіонального відділення BFA у своїй землі; контакти є на офіційній сторінці. Для конкретного випадку підготуйте ім’я, дату народження та номер IFA, якщо він вам відомий.",
                  "Prüfen Sie zuerst Wohnsitzmeldung und Briefkasten. Sind einige Wochen ohne Nachricht vergangen, wenden Sie sich an die BFA-Regionaldirektion Ihres Bundeslandes; Kontakte stehen auf der amtlichen Seite. Halten Sie für Ihren Fall Namen, Geburtsdatum und die IFA-Zahl bereit, falls bekannt."),
            .init("moving", "mappin.and.ellipse", "Якщо ви переїхали", "Wenn Sie umgezogen sind",
                  "Зареєструйте нову адресу протягом трьох днів після заселення. Актуальні дані потрібні, щоб BFA могло надіслати картку та звернутися до вас. Якщо доставка вже в процесі, повідомте BFA про зміну адреси.",
                  "Melden Sie die neue Adresse binnen drei Tagen nach dem Einzug. Aktuelle Daten sind nötig, damit das BFA die Karte zustellen und Sie erreichen kann. Läuft die Zustellung bereits, teilen Sie dem BFA den Umzug mit.")
        ],
        sources: [registrationSource, bfaContactSource, addressSource]
    )
}
