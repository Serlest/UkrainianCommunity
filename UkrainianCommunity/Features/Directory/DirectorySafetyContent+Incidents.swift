import Foundation

extension DirectorySafetyContent {
    static let incidentGuides: [String: SafetyGuide] = [
        "fire-gas": guide(
            "Перші дії при пожежі, димі та запаху газу.",
            "Erste Schritte bei Brand, Rauch und Gasgeruch.",
            [
                section(
                    "fire", "Пожежа або дим", "Brand oder Rauch", "flame.fill",
                    "Залиште небезпечну зону, попередьте інших, якщо це безпечно, і телефонуйте 122 з безпечного місця. Не повертайтеся всередину; виконуйте вказівки пожежної служби.",
                    "Verlassen Sie den Gefahrenbereich, warnen Sie andere, wenn es sicher ist, und rufen Sie 122 von einem sicheren Ort an. Gehen Sie nicht zurück; folgen Sie der Feuerwehr.",
                    [fire]),
                section(
                    "gas", "Запах газу", "Gasgeruch", "wind",
                    "Не запалюйте вогонь, не користуйтеся вимикачами, дзвінком або телефоном у приміщенні. Якщо безпечно, перекрийте газ; вийдіть із будівлі й ззовні телефонуйте 128. При пожежі також викликайте 122.",
                    "Keine Flammen entzünden und im Gebäude keine Schalter, Klingel oder Telefone benutzen. Wenn gefahrlos möglich, Gas abdrehen; Gebäude verlassen und von draußen 128 anrufen. Bei Brand zusätzlich 122 wählen.",
                    [gas, fire]),
                section(
                    "co", "Підозра на чадний газ", "Verdacht auf Kohlenmonoxid", "lungs.fill",
                    "Головний біль, запаморочення й нудота у кількох людей одночасно можуть бути ознакою отруєння чадним газом. Вийдіть на свіже повітря, не наражайтеся на небезпеку та викликайте 144; якщо приміщення небезпечне — також 122.",
                    "Kopfschmerzen, Schwindel und Übelkeit bei mehreren Personen können auf Kohlenmonoxid hinweisen. Gehen Sie an die frische Luft, gefährden Sie sich nicht selbst und rufen Sie 144; bei Gefahr im Gebäude auch 122.",
                    [ambulance, fire]),
            ],
            [
                DirectorySource(
                    name: "Wiener Netze · Was tun bei Gasgeruch",
                    url: "https://www.wienernetze.at/was-tun-bei-gasgeruch"),
                DirectorySource(
                    name: "Gesundheitsportal · Kohlenmonoxid",
                    url:
                        "https://www.gesundheit.gv.at/krankheiten/vergiftungsinformation/vergiftung-kohlenmonoxid.html"
                ), emergencySource,
            ]),
        "mountains-water": guide(
            "Куди дзвонити при нещасному випадку в горах, на озері чи річці.",
            "Notruf bei Unfällen am Berg, See oder Fluss.",
            [
                section(
                    "mountain", "У горах", "Am Berg", "mountain.2.fill",
                    "Забезпечте власну безпеку, назвіть точне місце та стан постраждалих. Телефонуйте гірській рятувальній службі 140; у Форарльберзі — 144. Номер 112 теж приймає екстрені виклики. Не наражайте себе на небезпеку на схилі чи під час лавини.",
                    "Sichern Sie sich selbst und nennen Sie Ort und Zustand der Betroffenen. Bergrettung: 140; in Vorarlberg: 144. Auch 112 nimmt Notrufe entgegen. Bringen Sie sich am Hang oder bei Lawinen nicht selbst in Gefahr.",
                    [mountain, europeanEmergency]),
                section(
                    "water", "На водоймі", "Am Gewässer", "water.waves",
                    "Покличте рятувальників на місці й телефонуйте 144 або 112. Повідомте назву водойми, берег/орієнтир і кількість людей. Допомагайте з берега лише так, щоб не стати ще одним постраждалим; дотримуйтеся вказівок диспетчера.",
                    "Rufen Sie Rettungskräfte vor Ort und wählen Sie 144 oder 112. Nennen Sie Gewässer, Ufer oder Orientierungspunkt und Zahl der Betroffenen. Helfen Sie vom Ufer nur ohne Eigengefährdung und folgen Sie der Leitstelle.",
                    [ambulance, europeanEmergency]),
            ],
            [
                DirectorySource(
                    name: "Österreichische Bergrettung · Notruf",
                    url: "https://bergrettung.at/tipps/notruf-absetzen/"),
                DirectorySource(
                    name: "Österreichische Wasserrettung · Einsatzdienst",
                    url: "https://sbg.owr.at/seeham/ueber-uns/fachbereiche/einsatzdienst/"),
                emergencySource,
            ]),
        "poisoning": guide(
            "При підозрі на отруєння ліками, хімією, рослинами чи грибами.",
            "Bei Verdacht auf Vergiftung durch Medikamente, Chemikalien, Pflanzen oder Pilze.",
            [
                section(
                    "first", "Зверніться по консультацію", "Sofort Rat holen",
                    "phone.arrow.up.right.fill",
                    "Телефонуйте до центру інформації про отруєння 01 406 43 43. Підготуйте назву речовини або упаковку, приблизну кількість, час контакту, вік і стан людини. Не викликайте блювання без вказівки фахівця.",
                    "Rufen Sie die Vergiftungsinformationszentrale 01 406 43 43 an. Halten Sie Stoffname oder Verpackung, ungefähre Menge, Zeitpunkt, Alter und Zustand bereit. Ohne fachliche Anweisung kein Erbrechen auslösen.",
                    [poison]),
                section(
                    "severe", "Тяжкі симптоми", "Schwere Symptome", "cross.case.fill",
                    "При втраті свідомості, порушенні дихання чи інших тяжких симптомах негайно викликайте 144. Виконуйте вказівки диспетчера; збережіть упаковку для медиків.",
                    "Bei Bewusstlosigkeit, Atemproblemen oder anderen schweren Symptomen sofort 144 rufen. Folgen Sie der Leitstelle und behalten Sie die Verpackung für das medizinische Personal.",
                    [ambulance]),
            ],
            [
                DirectorySource(
                    name: "Gesundheitsportal · Vergiftungsinformation",
                    url:
                        "https://www.gesundheit.gv.at/service/notruf/vergiftungsinformationszentrale.html"
                ),
                DirectorySource(
                    name: "Gesundheitsportal · Gefahren im Haushalt",
                    url:
                        "https://www.gesundheit.gv.at/krankheiten/vergiftungsinformation/vergiftung-gefahren-haushalt.html"
                ),
            ]),
        "disasters": guide(
            "Повінь, буря, лавина, землетрус, блекаут та офіційні попередження.",
            "Hochwasser, Sturm, Lawine, Erdbeben, Blackout und amtliche Warnungen.",
            [
                section(
                    "warning", "Попередження та евакуація", "Warnung und Evakuierung",
                    "exclamationmark.triangle.fill",
                    "Стежте за офіційними повідомленнями AT-Alert і місцевої влади. Виконуйте накази про евакуацію або укриття. Не заходьте у затоплені підвали й не перетинайте затоплені дороги; уникайте дерев, ліній електропередач і небезпечних схилів.",
                    "Beachten Sie AT-Alert und Mitteilungen der Behörden. Folgen Sie Anordnungen zu Evakuierung oder Schutz. Betreten Sie keine überfluteten Keller und queren Sie keine überschwemmten Straßen; meiden Sie Bäume, Stromleitungen und gefährliche Hänge."
                ),
                section(
                    "flood-storm", "Повінь і буря", "Hochwasser und Sturm", "cloud.heavyrain.fill",
                    "Залишайтеся в будівлі під час бурі, відійдіть від вікон. Уникайте водойм, затоплених підземних переходів і доріг; не спускайтеся до затопленого підвалу. Слухайте місцеві повідомлення й попереджайте близьких лише без ризику для себе.",
                    "Bleiben Sie bei Sturm im Gebäude und meiden Sie Fenster. Halten Sie Abstand zu Gewässern, überfluteten Unterführungen und Straßen; betreten Sie keinen überfluteten Keller. Beachten Sie lokale Meldungen und warnen Sie andere nur ohne Eigengefährdung."
                ),
                section(
                    "earthquake", "Землетрус", "Erdbeben", "waveform.path.ecg",
                    "У приміщенні тримайтеся подалі від вікон і дочекайтеся кінця поштовхів у захищеному місці. Надворі відійдіть від будівель та ліній електропередач. Після сильного землетрусу не входьте в пошкоджену будівлю, доки її не визнають безпечною.",
                    "Drinnen Abstand zu Fenstern halten und das Ende der Erschütterung an einem geschützten Ort abwarten. Draußen Abstand zu Gebäuden und Stromleitungen halten. Ein beschädigtes Gebäude nach starkem Beben erst nach Freigabe wieder betreten."
                ),
                section(
                    "blackout", "Тривале відключення світла", "Längerer Stromausfall",
                    "bolt.slash.fill",
                    "Майте вдома воду, їжу, потрібні ліки, ліхтар і батарейний радіоприймач; домовтеся з родиною про зв’язок без телефону. Під час блекауту слухайте офіційні повідомлення. Не використовуйте вугільний гриль або непридатні для приміщень пальники всередині: є ризик чадного газу.",
                    "Halten Sie Wasser, Lebensmittel, nötige Medikamente, Taschenlampe und Batterieradio bereit und vereinbaren Sie einen Treffpunkt ohne Telefon. Bei Blackout amtliche Meldungen beachten. Holzkohlegrills und ungeeignete Kocher nie drinnen nutzen: Kohlenmonoxidgefahr."
                ),
                section(
                    "urgent", "Коли потрібна допомога", "Wenn Hilfe nötig ist", "phone.fill",
                    "При безпосередній загрозі життю телефонуйте 112. При пожежі чи рятуванні — 122, при медичній невідкладній ситуації — 144. Назвіть місце та конкретну небезпеку.",
                    "Bei unmittelbarer Lebensgefahr 112 wählen. Bei Brand oder technischer Rettung 122, bei medizinischem Notfall 144. Nennen Sie Ort und konkrete Gefahr.",
                    [europeanEmergency, fire, ambulance]),
            ],
            [
                DirectorySource(
                    name: "oesterreich.gv.at · Selbstschutz im Katastrophenfall",
                    url:
                        "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/katastrophenfaelle/1"
                ),
                DirectorySource(
                    name: "oesterreich.gv.at · AT-Alert",
                    url:
                        "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/katastrophenfaelle/2/Seite.29500311"
                ),
                DirectorySource(
                    name: "oesterreich.gv.at · Blackout",
                    url:
                        "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/katastrophenfaelle/1/Seite.29500329"
                ),
            ]),
        "road-accident": guide(
            "Безпека та виклик допомоги після дорожньої пригоди.",
            "Sicherheit und Hilfe nach einem Verkehrsunfall.",
            [
                section(
                    "secure", "Спочатку безпека", "Zuerst Sicherheit", "car.side.fill",
                    "Зупиніться, убезпечте місце пригоди настільки, наскільки це можливо без ризику для себе, та перевірте, чи є постраждалі. На автомагістралі тримайтеся подалі від руху; виконуйте вказівки служб.",
                    "Halten Sie an, sichern Sie die Unfallstelle ohne Eigengefährdung und prüfen Sie, ob Menschen verletzt sind. Auf Autobahnen Abstand zum Verkehr halten und Anweisungen der Einsatzkräfte befolgen."
                ),
                section(
                    "call", "Викличте допомогу", "Hilfe rufen", "phone.fill",
                    "При травмах телефонуйте 144, при пожежі — 122. Якщо не знаєте, яка служба потрібна, телефонуйте 112. Повідомте місце (дорога, напрямок, кілометр), кількість постраждалих та небезпеку.",
                    "Bei Verletzten 144, bei Brand 122 anrufen. Wenn die zuständige Stelle unklar ist, 112 wählen. Nennen Sie Straße, Fahrtrichtung, Kilometer, Zahl der Verletzten und Gefahren.",
                    [ambulance, fire, europeanEmergency]),
            ],
            [
                DirectorySource(
                    name: "oesterreich.gv.at · Verkehrsunfall",
                    url:
                        "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/unfall/4/Seite.2892001"
                ), emergencySource,
            ]),
    ]
}
