import Foundation

extension DirectorySafetyContent {
    static let protectionGuides: [String: SafetyGuide] = [
        "emergency": guide(
            "Що робити та кому телефонувати в небезпечній ситуації.",
            "Was tun und wen bei Gefahr anrufen?",
            [
                section(
                    "call", "Викличте допомогу", "Hilfe rufen", "phone.fill",
                    "133 — поліція; 144 — швидка; 122 — пожежна служба; 112 — загальноєвропейський номер, якщо не знаєте, яка служба потрібна.",
                    "133 – Polizei; 144 – Rettung; 122 – Feuerwehr; 112 – Euro-Notruf, wenn Sie nicht wissen, welche Stelle zuständig ist.",
                    [police, ambulance, fire, europeanEmergency]),
                section(
                    "report", "Що сказати диспетчеру", "Was der Leitstelle sagen?",
                    "text.bubble.fill",
                    "Назвіть точне місце, що сталося, кількість постраждалих і свій номер. Не завершуйте розмову, доки диспетчер не скаже. Екстрені номери безкоштовні; 112 працює навіть без PIN-коду.",
                    "Nennen Sie den genauen Ort, das Geschehen, die Zahl der Betroffenen und Ihre Rückrufnummer. Legen Sie erst auf, wenn die Leitstelle es sagt. Notrufe sind kostenlos; 112 funktioniert auch ohne PIN."
                ),
                section(
                    "accessible", "Якщо не можете говорити", "Wenn Sprechen nicht möglich ist",
                    "text.bubble.fill",
                    "Офіційний застосунок DEC112 дозволяє надсилати текстовий екстрений виклик. Для людей із порушеннями слуху поліція також приймає SMS на 0800 133 133. Якщо загроза пов’язана з насильством і говорити небезпечно, у DEC112 є тихий виклик поліції; вкажіть точну адресу.",
                    "Mit der offiziellen App DEC112 ist ein textbasierter Notruf möglich. Gehörlose und hörbeeinträchtigte Menschen können die Polizei auch per SMS an 0800 133 133 erreichen. Bei Gewalt und Gefahr durch Sprechen ist in DEC112 ein stiller Polizeinotruf mit genauer Adresse möglich."
                ),
            ], [emergencySource]),
        "domestic-violence": guide(
            "Захист при насильстві вдома або з боку близької людини.",
            "Schutz bei Gewalt zu Hause oder durch nahestehende Personen.",
            [
                section(
                    "now", "Якщо небезпека зараз", "Bei akuter Gefahr",
                    "exclamationmark.shield.fill",
                    "Перейдіть у безпечне місце, якщо можете. Телефонуйте 133 або 112. Якщо говорити небезпечно, офіційний застосунок DEC112 підтримує текстовий і тихий виклик поліції; для тихого виклику потрібна точна адреса.",
                    "Gehen Sie möglichst an einen sicheren Ort. Wählen Sie 133 oder 112. Wenn Sprechen gefährlich ist, ermöglicht die offizielle App DEC112 Text- und stillen Polizeinotruf; für den stillen Notruf ist eine genaue Adresse nötig.",
                    [police, europeanEmergency]),
                section(
                    "support", "Конфіденційна підтримка", "Vertrauliche Unterstützung",
                    "hand.raised.heart.fill",
                    "Звернутися по пораду можна до прийняття рішення про подальші кроки. Центри захисту допомагають усім постраждалим; для жінок є жіноча гаряча лінія, для чоловіків — кризова консультація. Якщо телефон контролюють, користуйтеся безпечним пристроєм.",
                    "Beratung ist auch möglich, bevor Sie weitere Schritte entscheiden. Gewaltschutzzentren helfen allen Betroffenen; für Frauen gibt es die Frauenhelpline, für Männer eine Krisenberatung. Bei Überwachung Ihres Telefons nutzen Sie ein sicheres Gerät.",
                    [protectionCentre, womenHelpline, menHelpline]),
            ], [
                violenceSource,
                supportSource,
                DirectorySource(name: "Männerberatung 24/7", url: "https://maennerinfo.at/"),
                emergencySource,
            ]),
        "women": guide(
            "Куди звернутися при насильстві, переслідуванні чи загрозі.",
            "Hilfe bei Gewalt, Stalking oder Bedrohung.",
            [
                section(
                    "urgent", "Негайна загроза", "Unmittelbare Gefahr",
                    "exclamationmark.triangle.fill",
                    "Якщо вам або дітям загрожує небезпека, викличте поліцію. У разі травм телефонуйте швидкій допомозі.",
                    "Bei Gefahr für Sie oder Kinder die Polizei rufen. Bei Verletzungen die Rettung alarmieren.",
                    [police, ambulance]),
                section(
                    "help", "Порада і безпечне місце", "Beratung und Schutzunterkunft",
                    "heart.text.square.fill",
                    "Жіноча гаряча лінія працює цілодобово, безкоштовно, анонімно й конфіденційно. Вона допоможе знайти регіональну службу захисту. Можна звернутися й через центр захисту від насильства.",
                    "Die Frauenhelpline ist rund um die Uhr kostenlos, anonym und vertraulich erreichbar und vermittelt regionale Schutzeinrichtungen. Auch Gewaltschutzzentren beraten.",
                    [womenHelpline, protectionCentre]),
            ],
            [
                violenceSource,
                DirectorySource(
                    name: "Frauenhelpline · Angebot",
                    url: "https://www.frauenhelpline.at/de/angebot"),
            ]),
        "children": guide(
            "Допомога дитині, підлітку та дорослим, які помітили небезпеку.",
            "Hilfe für Kinder, Jugendliche und Erwachsene, die Gefahr bemerken.",
            [
                section(
                    "danger", "Дитині загрожує небезпека", "Kind in Gefahr",
                    "exclamationmark.shield.fill",
                    "У разі безпосередньої загрози або травми телефонуйте 133 чи 144. Дитина може піти до безпечного дорослого або людного місця та попросити допомоги.",
                    "Bei unmittelbarer Gefahr oder Verletzung 133 beziehungsweise 144 anrufen. Ein Kind kann sich an eine sichere erwachsene Person oder an einen belebten Ort wenden und um Hilfe bitten.",
                    [police, ambulance]),
                section(
                    "talk", "Поговорити конфіденційно", "Vertraulich sprechen",
                    "bubble.left.and.bubble.right.fill",
                    "147 Rat auf Draht допомагає дітям, підліткам і людям, які про них піклуються. При насильстві консультація анонімна й безкоштовна. Також можна звернутися до дитячо-молодіжної служби свого району або Kinder- und Jugendanwaltschaft землі.",
                    "147 Rat auf Draht hilft Kindern, Jugendlichen und Bezugspersonen. Bei Gewalt ist die Beratung anonym und kostenlos. Weitere Hilfe bieten die örtliche Kinder- und Jugendhilfe und die Kinder- und Jugendanwaltschaft des Bundeslandes.",
                    [children]),
                section(
                    "missing", "Якщо дитина зникла", "Wenn ein Kind vermisst wird", "figure.child",
                    "Негайно повідомте поліцію, якщо не знаєте, де дитина, і боїтеся за її безпеку. Чекати 24 години не потрібно. Підготуйте актуальне фото, опис одягу й останнє відоме місце. Лінія 116 000 надає підтримку щодо зниклих дітей.",
                    "Informieren Sie sofort die Polizei, wenn ein Kind verschwunden ist und Sie seine Sicherheit befürchten. Eine Wartefrist von 24 Stunden gibt es nicht. Halten Sie ein aktuelles Foto, Kleidung und letzten bekannten Ort bereit. Die Hotline 116 000 unterstützt bei vermissten Kindern.",
                    [police, missingChildren]),
            ],
            [
                DirectorySource(
                    name: "oesterreich.gv.at · Hilfe für Kinder",
                    url:
                        "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/hilfe-bei-gewalt/3/Seite.290114"
                ),
                DirectorySource(
                    name: "oesterreich.gv.at · Abgängigkeitsanzeige",
                    url:
                        "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/vermisst/Seite.2970010"
                ), emergencySource,
            ]),
        "discrimination": guide(
            "Допомога при дискримінації, сексуальних домаганнях і переслідуванні.",
            "Hilfe bei Diskriminierung, sexueller Belästigung und Nachstellung.",
            [
                section(
                    "threat", "Погрози або напад", "Drohung oder Angriff",
                    "exclamationmark.shield.fill",
                    "Якщо є негайна небезпека, телефонуйте поліції. Збережіть повідомлення, дати й інші докази, якщо це безпечно.",
                    "Bei akuter Gefahr die Polizei rufen. Nachrichten, Daten und andere Belege aufbewahren, sofern das sicher möglich ist.",
                    [police]),
                section(
                    "advice", "Незалежна консультація", "Unabhängige Beratung",
                    "person.crop.rectangle.stack.fill",
                    "Служба рівного ставлення безкоштовно й конфіденційно консультує щодо дискримінації на роботі, під час пошуку житла, у послугах та інших ситуаціях. Якщо ви постраждали від злочину, цілодобова служба підтримки потерпілих допоможе визначити наступні кроки.",
                    "Die Gleichbehandlungsanwaltschaft berät kostenlos und vertraulich zu Diskriminierung etwa bei Arbeit, Wohnungssuche und Dienstleistungen. Nach einer Straftat hilft der Opfer-Notruf rund um die Uhr bei den nächsten Schritten.",
                    [equality, victims]),
            ],
            [
                DirectorySource(
                    name: "Gleichbehandlungsanwaltschaft · Beratung",
                    url:
                        "https://www.gleichbehandlungsanwaltschaft.gv.at/unser-angebot/beratung-und-unterstuetzung.html"
                ),
                DirectorySource(
                    name: "oesterreich.gv.at · Beratungsstellen",
                    url:
                        "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/melde-und-beratungsstellen-in-oesterreich/melde__und_beratungsstellen"
                ),
            ]),
        "assault": guide(
            "Допомога після нападу, сексуального насильства чи іншого злочину — для кожної людини.",
            "Hilfe nach einem Angriff, sexualisierter Gewalt oder einer anderen Straftat – für alle.",
            [
                section(
                    "urgent", "Негайна небезпека", "Akute Gefahr", "exclamationmark.shield.fill",
                    "Відійдіть у безпечне місце й телефонуйте поліції 133 або 112. Якщо є травми чи потрібна термінова медична допомога — 144. Не повертайтеся до небезпечного місця за речами.",
                    "Gehen Sie an einen sicheren Ort und rufen Sie die Polizei unter 133 oder 112. Bei Verletzungen oder dringendem medizinischem Bedarf wählen Sie 144. Kehren Sie nicht wegen Gegenständen an einen gefährlichen Ort zurück.",
                    [police, ambulance]),
                section(
                    "support", "Підтримка після події", "Hilfe nach der Tat",
                    "hand.raised.heart.fill",
                    "Служба підтримки потерпілих цілодобово, безкоштовно й анонімно допомагає людям, яких безпосередньо або опосередковано торкнувся злочин. Розкажіть, що сталося; служба допоможе зорієнтуватися та знайти місцеву підтримку. Якщо безпечно, збережіть повідомлення й інші можливі докази.",
                    "Der Opfer-Notruf berät Betroffene und Angehörige rund um die Uhr kostenlos und anonym. Schildern Sie den Vorfall; die Stelle hilft bei der Orientierung und vermittelt regionale Unterstützung. Bewahren Sie Nachrichten und mögliche Belege auf, sofern das sicher ist.",
                    [victims]),
            ],
            [
                DirectorySource(
                    name: "oesterreich.gv.at · Opfer-Notruf",
                    url:
                        "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/melde-und-beratungsstellen-in-oesterreich/melde__und_beratungsstellen"
                ), violenceSource,
            ]),
        "mental-crisis": guide(
            "Підтримка під час психологічної кризи — для дорослих і дітей.",
            "Hilfe in psychischen Krisen für Erwachsene und Kinder.",
            [
                section(
                    "acute", "Негайна небезпека", "Akute Gefahr", "cross.case.fill",
                    "Якщо людина може завдати шкоди собі чи іншим або потребує негайної медичної допомоги, телефонуйте 144 чи 112. Залишайтеся поруч лише тоді, коли це безпечно.",
                    "Wenn jemand sich oder andere gefährden könnte oder sofort medizinische Hilfe braucht, 144 oder 112 wählen. Bleiben Sie nur dann bei der Person, wenn es sicher ist.",
                    [ambulance, europeanEmergency]),
                section(
                    "talk", "Поговорити з кимось", "Mit jemandem sprechen",
                    "heart.text.square.fill",
                    "Телефон довіри 142 підтримує людей у кризі. Діти й підлітки можуть телефонувати 147.",
                    "Die Telefonseelsorge 142 unterstützt Menschen in Krisen. Kinder und Jugendliche können 147 anrufen.",
                    [crisis, children]),
            ],
            [
                emergencySource,
                DirectorySource(
                    name: "oesterreich.gv.at · Beratungsstellen",
                    url:
                        "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/melde-und-beratungsstellen-in-oesterreich/melde__und_beratungsstellen"
                ),
            ]),
    ]
}
