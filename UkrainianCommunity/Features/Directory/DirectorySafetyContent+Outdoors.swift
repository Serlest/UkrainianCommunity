import Foundation

extension DirectorySafetyContent {
    static let outdoorGuides: [String: SafetyGuide] = [
        "mountains-water": guide(
            "Рятувальний виклик у горах і на водоймах: номери, місце події та безпечні дії до прибуття допомоги.",
            "Notruf am Berg und Gewässer: Nummern, Unfallort und sichere Schritte bis Hilfe eintrifft.",
            [
                section(
                    "mountain", "Нещасний випадок у горах", "Unfall am Berg", "mountain.2.fill",
                    "Спочатку убезпечте себе й постраждалих від падіння, каміння або лавини. Викличте гірську рятувальну службу 140; у Форарльберзі використовуйте рятувальний номер 144. Якщо зв’язок із цією службою не вдається, спробуйте 112. Не залишайте постраждалого самого, якщо це безпечно.",
                    "Sichern Sie sich und Betroffene zuerst gegen Absturz, Steinschlag oder Lawinen. Wählen Sie die Bergrettung 140; in Vorarlberg gilt der Rettungsnotruf 144. Kommt keine Verbindung zustande, versuchen Sie 112. Lassen Sie Betroffene nicht allein, soweit dies sicher ist.",
                    [mountain, vorarlbergMountain, europeanEmergency]),
                section(
                    "location", "Як описати місце", "Den Ort beschreiben", "location.fill",
                    "Назвіть координати або GPS-позицію, маршрут, найближчу хижу чи підйомник, висоту і погодні умови. Повідомте кількість людей, тип травм і загрози для рятувальників. Не завершуйте розмову до дозволу диспетчера та економте заряд телефону.",
                    "Nennen Sie Koordinaten oder GPS-Position, Route, nächste Hütte oder Seilbahn, Höhe und Wetter. Beschreiben Sie Zahl der Menschen, Verletzungen und Gefahren für die Rettungskräfte. Beenden Sie den Anruf erst auf Anweisung und sparen Sie Akku."
                ),
                section(
                    "no-signal", "Якщо мобільного зв’язку немає", "Wenn kein Mobilfunknetz verfügbar ist", "antenna.radiowaves.left.and.right.slash",
                    "Спробуйте 112: виклик може пройти через іншу доступну мережу. Якщо взагалі немає покриття, спершу захистіть постраждалого, а тоді шукайте точку зв’язку без ризику для себе. Повідомте рятувальникам, якщо вам довелося відійти від місця події.",
                    "Versuchen Sie 112: Der Notruf kann über ein anderes verfügbares Netz funktionieren. Gibt es gar keinen Empfang, sichern Sie die verletzte Person zuerst und suchen Sie dann gefahrlos einen Empfangspunkt. Teilen Sie der Leitstelle mit, wenn Sie den Unfallort verlassen mussten."
                ),
                section(
                    "water", "На озері або річці", "Am See oder Fluss", "water.waves",
                    "Покличте рятувальників на місці й викличте швидку або 112. Назвіть водойму, берег, найближчий пляж чи пристань і кількість людей у воді. Не стрибайте у воду без підготовки: допомагайте з берега лише без ризику для себе. У Каринтії та Верхній Австрії водну рятувальну службу також викликають через земельну диспетчерську 130.",
                    "Alarmieren Sie Rettungskräfte vor Ort und wählen Sie Rettung oder 112. Nennen Sie Gewässer, Ufer, nächstes Strandbad oder Anlegestelle und Zahl der Personen im Wasser. Springen Sie nicht unvorbereitet hinein; helfen Sie vom Ufer nur ohne Eigengefährdung. In Kärnten und Oberösterreich wird die Wasserrettung auch über die Landeswarnzentrale 130 alarmiert.",
                    [ambulance, europeanEmergency, waterRescue]),
            ], [
                DirectorySource(name: "Österreichische Bergrettung · Notruf", url: "https://bergrettung.at/tipps/notruf-absetzen/"),
                DirectorySource(name: "Österreichische Wasserrettung · Alarmierung", url: "https://owr.at/bundesleitung/ueber-uns/fachbereiche/einsatzdienst/"),
                DirectorySource(name: "Wasserrettung Oberösterreich · Notruf 130", url: "https://ooe.owr.at/traun/ueber-uns/unsere-ortsstelle/"),
                emergencySource,
            ]),
        "disasters": guide(
            "Різні дії при офіційному попередженні, повені, бурі, землетрусі та тривалому знеструмленні.",
            "Unterschiedliche Schritte bei amtlicher Warnung, Hochwasser, Sturm, Erdbeben und längerem Stromausfall.",
            [
                section(
                    "warning", "Попередження та евакуація", "Warnung und Evakuierung", "exclamationmark.triangle.fill",
                    "Прочитайте повідомлення AT-Alert повністю: воно вказує територію, небезпеку й конкретну дію. Дотримуйтеся вказівок місцевої влади щодо укриття чи евакуації. Якщо зв’язок нестабільний, слухайте офіційне радіо; не вирушайте до небезпечної зони для перевірки чуток.",
                    "Lesen Sie AT-Alert vollständig: Die Meldung nennt Gebiet, Gefahr und konkrete Handlung. Befolgen Sie behördliche Anweisungen zu Schutz oder Evakuierung. Bei gestörter Kommunikation hören Sie amtliche Radiomeldungen und fahren Sie nicht wegen Gerüchten in das Gefahrengebiet."
                ),
                section(
                    "flood", "Повінь", "Hochwasser", "water.waves",
                    "Перенесіть важливі документи, ліки й необхідні речі вище, якщо ще є час і це безпечно. Не заходьте у затоплений підвал, не йдіть і не їдьте через воду. Припиніть використання води з-під крана, якщо влада повідомила про її забруднення; поверніться до будівлі лише після дозволу служб.",
                    "Bringen Sie wichtige Dokumente, Medikamente und Nötiges rechtzeitig in höhere Räume, soweit dies sicher ist. Betreten Sie keinen überfluteten Keller und gehen oder fahren Sie nicht durch Hochwasser. Nutzen Sie Leitungswasser nicht, wenn Behörden vor Verunreinigung warnen; kehren Sie erst nach Freigabe zurück."
                ),
                section(
                    "storm-quake", "Буря або землетрус", "Sturm oder Erdbeben", "cloud.bolt.fill",
                    "Під час бурі залишайтеся в захищеній будівлі, подалі від вікон, дерев і ліній електропередач. Під час землетрусу всередині відійдіть від вікон і дочекайтеся кінця поштовхів у захищеному місці; не біжіть сходами під час поштовхів. Після сильного землетрусу не входьте в пошкоджений будинок до перевірки фахівцями.",
                    "Bleiben Sie bei Sturm in einem sicheren Gebäude und meiden Sie Fenster, Bäume und Stromleitungen. Bei Erdbeben im Gebäude Abstand zu Fenstern halten und die Erschütterung an einem geschützten Platz abwarten; laufen Sie währenddessen nicht über die Treppe hinaus. Betreten Sie ein beschädigtes Gebäude nach einem starken Beben erst nach fachlicher Freigabe."
                ),
                section(
                    "blackout", "Тривалий блекаут", "Längerer Blackout", "bolt.slash.fill",
                    "Підготуйте воду, їжу без потреби в електриці, особисті ліки, ліхтар, батарейне радіо й план зв’язку з родиною. Під час знеструмлення перевіряйте офіційні радіоповідомлення та місцеві пункти допомоги. Не використовуйте вугільний гриль, генератор або пальник, не призначений для приміщення, усередині будинку: чадний газ не має запаху.",
                    "Halten Sie Wasser, ohne Strom nutzbare Lebensmittel, persönliche Medikamente, Taschenlampe, Batterieradio und einen Familienplan bereit. Bei Stromausfall amtliche Radiomeldungen und örtliche Anlaufstellen beachten. Holzkohlegrill, Generator oder nicht für Innenräume zugelassene Kocher nie im Gebäude betreiben: Kohlenmonoxid ist geruchlos."
                ),
                section(
                    "hazardous-air", "Хмара небезпечних речовин", "Gefahrstoffwolke", "wind",
                    "Якщо влада попереджає про забруднене повітря або хімічну аварію, зайдіть у будівлю, зачиніть вікна й двері, вимкніть вентиляцію та слухайте місцеве радіо. Залишайтеся всередині до відбою або іншої офіційної вказівки: самостійна втеча назовні може бути небезпечнішою. Не телефонуйте до екстрених служб лише за довідкою.",
                    "Warnen Behörden vor verunreinigter Luft oder einem Chemieunfall, gehen Sie ins Gebäude, schließen Sie Fenster und Türen, schalten Sie Lüftungen ab und hören Sie Lokalradio. Bleiben Sie bis zur Entwarnung oder einer anderen amtlichen Anweisung drinnen: Eine eigenmächtige Flucht kann gefährlicher sein. Rufen Sie Notrufstellen nicht nur für Auskünfte an."
                ),
                section(
                    "radiological", "Радіологічне попередження", "Radiologische Warnung", "radiation",
                    "При повідомленні про радіологічну небезпеку дотримуйтеся AT-Alert, сирен і вказівок влади через ORF та notfallschutz.gv.at. Укрийтеся в будівлі, якщо це наказано. Таблетки йодиду калію не приймайте самостійно: лише за прямою вказівкою органів влади для визначених груп і територій.",
                    "Bei radiologischer Warnung befolgen Sie AT-Alert, Sirenen sowie Anweisungen über ORF und notfallschutz.gv.at. Suchen Sie Schutz im Gebäude, wenn dies angeordnet wird. Kaliumiodid-Tabletten nicht eigenmächtig einnehmen: nur auf ausdrückliche Behördenanweisung für die betroffenen Gruppen und Gebiete."
                ),
                section(
                    "urgent", "Якщо є безпосередня небезпека", "Bei unmittelbarer Gefahr", "phone.fill",
                    "При загрозі життю телефонуйте 112. Для пожежі чи технічного порятунку викликайте пожежних, при медичній невідкладній ситуації — швидку. Назвіть конкретну небезпеку й місце; не використовуйте екстрений номер лише для запиту про електропостачання.",
                    "Bei Lebensgefahr wählen Sie 112. Für Brand oder technische Rettung die Feuerwehr, bei medizinischem Notfall die Rettung alarmieren. Nennen Sie konkrete Gefahr und Ort; nutzen Sie den Notruf nicht nur für Fragen zur Stromversorgung.",
                    [europeanEmergency, fire, ambulance]),
            ], [
                DirectorySource(name: "oesterreich.gv.at · Katastrophenfall", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/katastrophenfaelle/1"),
                DirectorySource(name: "oesterreich.gv.at · Hochwasser", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/katastrophenfaelle/1/Seite.29500323"),
                DirectorySource(name: "oesterreich.gv.at · Erdbeben", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/katastrophenfaelle/1/Seite.29500324"),
                DirectorySource(name: "oesterreich.gv.at · Blackout", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/katastrophenfaelle/1/Seite.29500329"),
                DirectorySource(name: "oesterreich.gv.at · Gefahrstoffwolke", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/katastrophenfaelle/1/Seite.29500322"),
                DirectorySource(name: "oesterreich.gv.at · Radiologischer Notfall", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/katastrophenfaelle/1/Seite.29500321"),
            ]),
    ]
}
