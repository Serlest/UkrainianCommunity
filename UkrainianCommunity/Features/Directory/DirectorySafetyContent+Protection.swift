import Foundation

extension DirectorySafetyContent {
    static let protectionGuides: [String: SafetyGuide] = [
        "emergency": guide(
            "Визначте службу, передайте місце події та дійте за вказівками диспетчера.",
            "Wählen Sie den richtigen Notruf, nennen Sie den Ort und folgen Sie der Leitstelle.",
            [
                section(
                    "choose", "Яку службу викликати", "Welchen Notruf wählen", "phone.fill",
                    "Поліція — при насильстві або загрозі; швидка — при тяжкій травмі чи раптовому погіршенні здоров’я; пожежна служба — при пожежі та технічному порятунку. Якщо не знаєте, яка служба потрібна, телефонуйте 112. Екстрені дзвінки безкоштовні.",
                    "Polizei bei Gewalt oder Gefahr, Rettung bei schwerer Verletzung oder akuter Erkrankung, Feuerwehr bei Brand oder technischer Rettung. Wenn die zuständige Stelle unklar ist, wählen Sie 112. Notrufe sind kostenlos.",
                    [police, ambulance, fire, europeanEmergency]),
                section(
                    "report", "Що сказати диспетчеру", "Was die Leitstelle wissen muss", "text.bubble.fill",
                    "Спочатку назвіть місце: адресу, поверх або орієнтир. Потім коротко скажіть, що сталося, скільки людей постраждало і які є небезпеки. Назвіть номер для зворотного дзвінка, відповідайте на запитання й не завершуйте виклик самостійно.",
                    "Nennen Sie zuerst Ort, Adresse, Stockwerk oder einen Orientierungspunkt. Beschreiben Sie dann kurz das Ereignis, die Zahl der Betroffenen und weitere Gefahren. Geben Sie eine Rückrufnummer an, beantworten Sie Fragen und beenden Sie das Gespräch erst auf Anweisung."
                ),
                section(
                    "waiting", "Поки їде допомога", "Bis Hilfe eintrifft", "cross.case.fill",
                    "Не заходьте в небезпечну зону. Якщо людина не реагує, викличте швидку й перевірте нормальне дихання. За відсутності нормального дихання починайте натискання на грудну клітку та виконуйте вказівки диспетчера; якщо дихає нормально, спостерігайте за диханням до прибуття допомоги.",
                    "Betreten Sie keinen Gefahrenbereich. Reagiert eine Person nicht, rufen Sie die Rettung und prüfen Sie die normale Atmung. Fehlt normale Atmung, beginnen Sie mit der Herzdruckmassage und folgen Sie der Leitstelle; bei normaler Atmung beobachten Sie die Person bis Hilfe eintrifft."
                ),
                section(
                    "accessible", "Якщо говорити неможливо", "Wenn Sprechen nicht möglich ist", "text.bubble.fill",
                    "Офіційний застосунок DEC112 передає текстовий екстрений виклик. Люди з порушенням слуху можуть також надіслати SMS поліції на 0800 133 133. При загрозі насильства тихий виклик поліції через DEC112 потребує точної адреси в застосунку або чаті; краще налаштувати його заздалегідь.",
                    "Die offizielle App DEC112 ermöglicht einen textbasierten Notruf. Gehörlose und hörbeeinträchtigte Menschen können die Polizei auch per SMS unter 0800 133 133 erreichen. Für den stillen Polizeinotruf bei Gewalt braucht DEC112 eine genaue Adresse in der App oder im Chat; richten Sie die App möglichst vorher ein."
                ),
            ], [
                emergencySource,
                DirectorySource(name: "Gesundheitsportal · Erste Hilfe", url: "https://www.gesundheit.gv.at/krankheiten/erste-hilfe/wiederbelebung-erwachsene.html"),
            ]),
        "domestic-violence": guide(
            "Негайний захист, поліцейська заборона наближення та допомога після насильства вдома.",
            "Akuter Schutz, polizeiliches Annäherungsverbot und Hilfe nach häuslicher Gewalt.",
            [
                section(
                    "now", "Якщо небезпека зараз", "Bei akuter Gefahr", "exclamationmark.shield.fill",
                    "Перейдіть з дітьми в безпечне місце, якщо це можливо без ризику. Викличте поліцію; при травмах також швидку. Якщо говорити небезпечно, у DEC112 є тихий виклик поліції, для якого потрібна точна адреса.",
                    "Gehen Sie mit Kindern an einen sicheren Ort, sofern das gefahrlos möglich ist. Rufen Sie die Polizei, bei Verletzungen auch die Rettung. Wenn Sprechen gefährlich ist, bietet DEC112 einen stillen Polizeinotruf mit genauer Adresse.",
                    [police, ambulance]),
                section(
                    "police-order", "Що може зробити поліція", "Was die Polizei tun kann", "shield.fill",
                    "Поліція може заборонити кривднику входити до житла та наближатися до вас на 100 м. Заборона зазвичай діє два тижні; при заяві до Bezirksgericht про судовий захист протягом цього строку вона подовжується щонайбільше до чотирьох тижнів. При порушенні заборони негайно телефонуйте поліції.",
                    "Die Polizei kann der gefährdenden Person das Betreten der Wohnung und eine Annäherung auf 100 m untersagen. Das Verbot gilt grundsätzlich zwei Wochen; bei rechtzeitigem Antrag auf eine einstweilige Verfügung beim Bezirksgericht verlängert es sich höchstens auf vier Wochen. Bei einem Verstoß sofort die Polizei rufen."
                ),
                section(
                    "next", "Захист після перших днів", "Schutz nach den ersten Tagen", "hand.raised.heart.fill",
                    "Центр захисту від насильства консультує незалежно від статі, допомагає з планом безпеки, зверненням до суду й супроводом у процедурах. Зверніться якомога раніше, щоб не пропустити строк поліцейської заборони. Зберігайте документи, повідомлення й медичні записи лише там, де кривдник не має доступу.",
                    "Ein Gewaltschutzzentrum berät unabhängig vom Geschlecht, hilft beim Sicherheitsplan, bei Gerichtsanträgen und bei Verfahren. Kontaktieren Sie es frühzeitig wegen der Frist des polizeilichen Verbots. Bewahren Sie Unterlagen, Nachrichten und ärztliche Befunde nur an einem sicheren Ort auf.",
                    [protectionCentre]),
                section(
                    "private-help", "Як отримати допомогу безпечно", "Sicher Hilfe suchen", "lock.shield.fill",
                    "Якщо ваш телефон контролюють, скористайтеся безпечним пристроєм або попросіть довірену людину зателефонувати. Жіноча лінія допоможе знайти прихисток; чоловіки можуть звернутися до цілодобової кризової лінії. Для дитини безпечним контактом є також 147.",
                    "Wenn Ihr Telefon überwacht wird, nutzen Sie ein sicheres Gerät oder bitten Sie eine Vertrauensperson um einen Anruf. Die Frauenhelpline vermittelt Schutzunterkünfte; Männer erreichen eine rund um die Uhr besetzte Krisenberatung. Kinder können sich auch an 147 wenden.",
                    [womenHelpline, menHelpline, children]),
            ], [
                violenceSource, supportSource,
                DirectorySource(name: "Männerberatung 24/7", url: "https://maennerinfo.at/"),
            ]),
        "women": guide(
            "Конфіденційна консультація, прихисток із дітьми та спеціалізована допомога жінкам.",
            "Vertrauliche Beratung, Schutzunterkunft mit Kindern und spezialisierte Hilfe für Frauen.",
            [
                section(
                    "helpline", "Перший конфіденційний контакт", "Erster vertraulicher Kontakt", "phone.fill",
                    "Жіноча гаряча лінія працює цілодобово й безкоштовно. Можна звернутися навіть без заяви до поліції або коли ви ще не вирішили, що робити. Консультантка допоможе оцінити небезпеку, права та наступний безпечний крок; доступні різні мови, але години консультацій окремими мовами відрізняються.",
                    "Die Frauenhelpline ist rund um die Uhr kostenlos erreichbar. Sie können auch ohne Anzeige und vor einer Entscheidung anrufen. Die Beraterin hilft, Gefahr, Rechte und den nächsten sicheren Schritt einzuschätzen; mehrere Sprachen sind möglich, deren Beratungszeiten sich jedoch unterscheiden.",
                    [womenHelpline]),
                section(
                    "shelter", "Якщо вдома залишатися небезпечно", "Wenn Zuhause nicht sicher ist", "house.fill",
                    "Попросіть лінію підібрати найближчий Frauenhaus або іншу захисну оселю. Такі місця приймають жінок та їхніх дітей і допомагають із подальшими кроками. Не повідомляйте кривднику адресу прихистку; порядок прийому та вільні місця уточнюйте через службу.",
                    "Bitten Sie die Helpline um Vermittlung an ein Frauenhaus oder eine andere Schutzunterkunft in Ihrer Nähe. Diese Einrichtungen bieten Frauen und ihren Kindern Schutz und Unterstützung. Teilen Sie der gefährdenden Person die Adresse nicht mit; Aufnahme und freie Plätze klärt die Beratungsstelle."
                ),
                section(
                    "specialized", "Після сексуального насильства або переслідування", "Nach sexualisierter Gewalt oder Stalking", "heart.text.square.fill",
                    "Спеціалізовані консультаційні центри допомагають жінкам і дівчатам після сексуального насильства безкоштовно та конфіденційно, за потреби з перекладачкою. Вони пояснюють медичну допомогу, заяву й супровід. Центри захисту допомагають також при переслідуванні та зверненні до поліції чи суду.",
                    "Spezialisierte Beratungsstellen unterstützen Frauen und Mädchen nach sexualisierter Gewalt kostenlos und vertraulich, bei Bedarf mit Dolmetscherin. Sie erklären medizinische Versorgung, Anzeige und Begleitung. Gewaltschutzzentren helfen auch bei Stalking und bei Polizei oder Gericht.",
                    [protectionCentre]),
            ], [
                DirectorySource(name: "oesterreich.gv.at · Frauenhelpline", url: "https://eausweise.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/hilfe-bei-gewalt/2/Seite.290501/frauenhelpline"),
                DirectorySource(name: "Frauenhelpline · Sprachen", url: "https://www.frauenhelpline.at/de/unsere-sprachen"),
                DirectorySource(name: "oesterreich.gv.at · Hilfe für Frauen", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/hilfe-bei-gewalt/2"),
            ]),
        "children": guide(
            "Що робити дитині, близьким і свідкам насильства; куди звертатися, якщо дитина зникла.",
            "Was Kinder, Angehörige und Zeug:innen bei Gewalt tun können und was bei Vermissten gilt.",
            [
                section(
                    "danger", "Небезпека або травма зараз", "Akute Gefahr oder Verletzung", "exclamationmark.shield.fill",
                    "Дитина може піти до безпечної дорослої людини або в людне місце й попросити викликати допомогу. При насильстві викликайте поліцію, при тяжкій травмі — швидку. Не залишайте дитину з людиною, від якої виходить загроза, якщо можете убезпечити її без ризику.",
                    "Ein Kind kann zu einer sicheren erwachsenen Person oder an einen belebten Ort gehen und um Hilfe bitten. Bei Gewalt die Polizei, bei schwerer Verletzung die Rettung rufen. Lassen Sie das Kind möglichst nicht bei der gefährdenden Person, sofern Sie es sicher schützen können.",
                    [police, ambulance]),
                section(
                    "child-help", "Дитині потрібна розмова", "Wenn ein Kind reden möchte", "bubble.left.and.bubble.right.fill",
                    "147 Rat auf Draht безкоштовно й анонімно консультує дітей та підлітків. Дитині не потрібно самій визначати, чи сталося правопорушення: достатньо описати, що відбувається. Дорослі, які непокояться за дитину, теж можуть отримати пораду.",
                    "147 Rat auf Draht berät Kinder und Jugendliche kostenlos und anonym. Ein Kind muss nicht selbst beurteilen, ob eine Straftat vorliegt; es kann erzählen, was geschieht. Auch besorgte Erwachsene können Rat einholen.",
                    [children]),
                section(
                    "adult-help", "Якщо ви помітили ризик для дитини", "Wenn Sie eine Gefährdung bemerken", "person.2.fill",
                    "Не ігноруйте ознаки насильства або нехтування. Зверніться до Kinder- und Jugendhilfe за місцем проживання дитини: служба оцінює ризик і організовує допомогу. Для незалежної поради є Kinder- und Jugendanwaltschaft федеральної землі; при негайній небезпеці звертайтеся до поліції.",
                    "Ignorieren Sie Hinweise auf Gewalt oder Vernachlässigung nicht. Wenden Sie sich an die örtliche Kinder- und Jugendhilfe: Sie prüft die Gefährdung und organisiert Hilfe. Unabhängige Beratung bietet die Kinder- und Jugendanwaltschaft des Bundeslands; bei akuter Gefahr die Polizei rufen."
                ),
                section(
                    "missing", "Якщо дитина зникла", "Wenn ein Kind vermisst wird", "figure.child",
                    "Якщо ви не знаєте, де дитина, і непокоїтеся за її безпеку, повідомте поліцію одразу: чекати 24 години не потрібно. Підготуйте свіже фото, опис одягу, останнє відоме місце й час. Лінія 116 000 надає підтримку родині, але не замінює повідомлення поліції.",
                    "Ist ein Kind verschwunden und Sie sorgen sich um seine Sicherheit, informieren Sie die Polizei sofort: Eine Wartezeit von 24 Stunden gibt es nicht. Halten Sie ein aktuelles Foto, Kleidung, letzten Ort und Zeitpunkt bereit. Die Hotline 116 000 unterstützt Angehörige, ersetzt aber nicht die Polizeimeldung.",
                    [police, missingChildren]),
            ], [
                DirectorySource(name: "oesterreich.gv.at · Hilfe für Kinder", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/hilfe-bei-gewalt/3/Seite.290114"),
                DirectorySource(name: "oesterreich.gv.at · Vermisstenanzeige", url: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/vermisst/Seite.2970010"),
                DirectorySource(name: "Gewaltinfo · Kinder- und Jugendhilfe", url: "https://www.gewaltinfo.at/recht/mitteilungspflicht-an-die-kinder-und-jugendhilfe.html"),
            ]),
    ]
}
