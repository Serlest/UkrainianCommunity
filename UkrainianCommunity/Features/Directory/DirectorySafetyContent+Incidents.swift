import Foundation

extension DirectorySafetyContent {
    static let incidentGuides: [String: SafetyGuide] = [
        "fire-gas": guide(
            "Окремі дії при пожежі, задимленні сходів, витоку газу та підозрі на чадний газ.",
            "Unterschiedliche Schritte bei Brand, verrauchten Fluchtwegen, Gasgeruch und Kohlenmonoxid.",
            [
                section(
                    "fire", "Пожежа у вашому приміщенні", "Brand in Ihrer Wohnung", "flame.fill",
                    "Викличте пожежну службу. Якщо шлях вільний від диму, виведіть людей, закрийте двері до осередку пожежі й виходьте сходами, не ліфтом. Не повертайтеся за речами й не намагайтеся гасити сильне полум’я або дим самостійно.",
                    "Rufen Sie die Feuerwehr. Ist der Fluchtweg rauchfrei, bringen Sie Menschen hinaus, schließen Sie die Tür zum Brandraum und benutzen Sie die Treppe, nicht den Aufzug. Kehren Sie nicht wegen Gegenständen zurück und versuchen Sie nicht, starken Brand oder Rauch selbst zu löschen.",
                    [fire]),
                section(
                    "smoke", "Якщо сходи заповнені димом", "Wenn das Stiegenhaus verraucht ist", "door.left.hand.closed",
                    "Не виходьте через задимлені сходи. Якщо ваша квартира не горить, залишайтеся всередині, щільно зачиніть двері, викличте пожежних і повідомте точну адресу та поверх. Чекайте їхніх вказівок і подайте знак із вікна; не стрибайте й не користуйтеся ліфтом.",
                    "Fliehen Sie nicht durch ein verrauchtetes Stiegenhaus. Brennt Ihre Wohnung nicht, bleiben Sie darin, schließen Sie die Türen dicht, rufen Sie die Feuerwehr und nennen Sie Adresse und Stockwerk. Folgen Sie ihren Anweisungen und machen Sie sich am Fenster bemerkbar; springen Sie nicht und benutzen Sie keinen Aufzug."
                ),
                section(
                    "gas", "Запах газу — без іскор", "Gasgeruch – Funken vermeiden", "wind",
                    "Не вмикайте й не вимикайте світло чи прилади, не користуйтеся дзвінком і телефоном усередині. Якщо це безпечно, відкрийте вікна, загасіть відкрите полум’я і перекрийте газ. Вийдіть із будівлі та телефонуйте аварійній газовій службі ззовні; при пожежі викличте також пожежних.",
                    "Schalten Sie im Gebäude weder Licht noch Geräte ein oder aus und benutzen Sie weder Klingel noch Telefon. Wenn gefahrlos möglich, Fenster öffnen, offene Flammen löschen und Gas abdrehen. Verlassen Sie das Gebäude und rufen Sie den Gasnotruf von draußen; bei Brand auch die Feuerwehr.",
                    [gas]),
                section(
                    "co", "Підозра на чадний газ", "Verdacht auf Kohlenmonoxid", "lungs.fill",
                    "Головний біль, запаморочення чи нудота у кількох людей одночасно біля газового приладу можуть бути ознакою отруєння чадним газом. Негайно вийдіть на свіже повітря й викличте швидку. Не повертайтеся всередину по інших без захисного обладнання; повідомте пожежних про небезпечне приміщення.",
                    "Kopfschmerzen, Schwindel oder Übelkeit bei mehreren Personen nahe einem Gasgerät können auf Kohlenmonoxid hinweisen. Gehen Sie sofort an die frische Luft und rufen Sie die Rettung. Kehren Sie nicht ohne Schutzausrüstung für andere zurück; informieren Sie die Feuerwehr über das gefährliche Gebäude.",
                    [ambulance, fire]),
            ], [
                DirectorySource(name: "Stadt Wien · Verhalten im Brandfall", url: "https://www.wien.gv.at/zusammenleben/feuerwehr-sicherheitstipps-brandfall"),
                DirectorySource(name: "Wiener Netze · Gasgeruch", url: "https://www.wienernetze.at/was-tun-bei-gasgeruch"),
                DirectorySource(name: "Gesundheitsportal · Kohlenmonoxid", url: "https://www.gesundheit.gv.at/krankheiten/vergiftungsinformation/vergiftung-kohlenmonoxid.html"),
                emergencySource,
            ]),
        "poisoning": guide(
            "Що робити при контакті з ліками, хімією, рослинами, грибами або небезпечними парами.",
            "Schritte nach Kontakt mit Medikamenten, Chemikalien, Pflanzen, Pilzen oder gefährlichen Dämpfen.",
            [
                section(
                    "life-threat", "Спершу оцініть стан", "Zuerst den Zustand prüfen", "cross.case.fill",
                    "Якщо людина непритомна, не дихає нормально або має тяжкі симптоми, негайно викличте швидку й виконуйте вказівки диспетчера. При випарах чи газі не заходьте в небезпечну зону за постраждалим: спершу захистіть себе та викличте спеціальні служби.",
                    "Ist die Person bewusstlos, atmet nicht normal oder zeigt schwere Symptome, sofort die Rettung alarmieren und der Leitstelle folgen. Betreten Sie bei Dämpfen oder Gas keinen Gefahrenbereich, um jemanden zu holen: Schützen Sie sich und rufen Sie Einsatzkräfte.",
                    [ambulance]),
                section(
                    "contact", "Якщо симптоми відсутні або легкі", "Bei fehlenden oder leichten Beschwerden", "drop.fill",
                    "При потраплянні речовини на шкіру зніміть забруднений одяг і промийте шкіру водою. При потраплянні в око промивайте його водою щонайменше 10–15 хвилин. При ковтанні очистіть рот; не викликайте блювання. Потім одразу зверніться до центру інформації про отруєння й дотримуйтеся його вказівок.",
                    "Bei Hautkontakt getränkte Kleidung ausziehen und die Haut mit Wasser spülen. Bei Augenkontakt mindestens 10–15 Minuten mit Wasser spülen. Nach Verschlucken den Mund reinigen; kein Erbrechen auslösen. Danach umgehend die Vergiftungsinformationszentrale anrufen und ihren Anweisungen folgen.",
                    [poison]),
                section(
                    "facts", "Що повідомити токсикологам", "Angaben für die Giftberatung", "list.clipboard.fill",
                    "Підготуйте упаковку або назву речовини, приблизну кількість, час і спосіб контакту. Назвіть вік, приблизну вагу й симптоми людини. Не чекайте симптомів після можливого проковтування дитиною ліків або батарейки — одразу запитайте фахівців, що робити.",
                    "Halten Sie Verpackung oder Stoffnamen, ungefähre Menge, Zeitpunkt und Art des Kontakts bereit. Nennen Sie Alter, ungefähres Gewicht und Beschwerden. Warten Sie nach möglichem Verschlucken von Medikamenten oder Knopfzellen durch ein Kind nicht auf Symptome, sondern fragen Sie sofort die Fachleute."
                ),
            ], [
                DirectorySource(name: "Gesundheitsportal · Vergiftung im Notfall", url: "https://www.gesundheit.gv.at/krankheiten/vergiftungsinformation/vergiftung-vorgehen-notfall.html"),
                DirectorySource(name: "Gesundheitsportal · Gefahren im Haushalt", url: "https://www.gesundheit.gv.at/krankheiten/vergiftungsinformation/vergiftung-gefahren-haushalt.html"),
            ]),
        "road-accident": guide(
            "Убезпечити місце, допомогти людям і повідомити про пригоду: дії залежать від того, чи є травми.",
            "Absichern, helfen, melden: unterschiedliche Schritte bei Verletzten und reinem Sachschaden.",
            [
                section(
                    "secure", "Місце пригоди та власна безпека", "Unfallstelle und Eigenschutz", "car.side.fill",
                    "Зупиніться, увімкніть аварійну сигналізацію й одягніть сигнальний жилет перед виходом на проїзну частину. Позначте місце трикутником, якщо це безпечно. На автомагістралі відійдіть від руху за огорожу; не переходьте смуги заради фото чи уламків.",
                    "Halten Sie an, schalten Sie die Warnblinkanlage ein und ziehen Sie vor dem Aussteigen auf die Fahrbahn die Warnweste an. Sichern Sie die Stelle mit dem Warndreieck, soweit dies sicher möglich ist. Auf der Autobahn Abstand zum Verkehr hinter der Leitschiene halten; überqueren Sie keine Fahrstreifen für Fotos oder Gegenstände."
                ),
                section(
                    "injured", "Якщо є постраждалі", "Wenn Menschen verletzt sind", "cross.case.fill",
                    "Негайно організуйте першу допомогу й викличте швидку; повідомте також поліцію. Назвіть дорогу, напрямок руху, кілометр або найближчий з’їзд, кількість постраждалих та небезпеки. При пожежі викличте пожежних.",
                    "Leisten oder organisieren Sie sofort Erste Hilfe und rufen Sie die Rettung; verständigen Sie auch die Polizei. Nennen Sie Straße, Fahrtrichtung, Kilometer oder nächste Ausfahrt, Zahl der Verletzten und Gefahren. Bei Brand die Feuerwehr rufen.",
                    [ambulance, police, fire]),
                section(
                    "property", "Якщо пошкоджене лише майно", "Wenn nur Sachschaden entstand", "doc.text.fill",
                    "Обміняйтеся і підтвердьте ім’я та адресу учасників, дані автомобілів і страховок; запишіть свідків та обставини. Поліцію можна не викликати, якщо немає травм і учасники довели одне одному ім’я та адресу. Якщо інша сторона поїхала або дані встановити не вдається, зверніться до поліції.",
                    "Tauschen Sie nachweislich Namen und Anschriften aus und notieren Sie Fahrzeug-, Versicherungs- und Zeugendaten sowie den Ablauf. Ohne Verletzte kann die Polizeimeldung entfallen, wenn Beteiligte einander Namen und Anschriften nachweisen. Fährt die andere Person weg oder lässt sich ihre Identität nicht feststellen, wenden Sie sich an die Polizei."
                ),
            ], [
                DirectorySource(name: "oesterreich.gv.at · Verkehrsunfall", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/unfall/4/Seite.2892001"),
                DirectorySource(name: "oesterreich.gv.at · Panne und Unfall", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/katastrophenfaelle/1/Seite.29500326"),
                emergencySource,
            ]),
    ]
}
