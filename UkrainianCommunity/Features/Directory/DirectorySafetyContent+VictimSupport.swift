import Foundation

extension DirectorySafetyContent {
    static let victimSupportGuides: [String: SafetyGuide] = [
        "assault": guide(
            "Перші кроки після нападу чи сексуального насильства, медична допомога й підтримка потерпілих.",
            "Erste Schritte nach einem Angriff oder sexualisierter Gewalt, medizinische Hilfe und Opferberatung.",
            [
                section(
                    "urgent", "Спершу — безпечне місце", "Zuerst an einen sicheren Ort", "exclamationmark.shield.fill",
                    "Відійдіть від нападника й викличте поліцію, якщо загроза триває. При травмах або невідкладній потребі у медичній допомозі викликайте швидку. Не повертайтеся за речами до небезпечного місця.",
                    "Entfernen Sie sich von der angreifenden Person und rufen Sie bei fortdauernder Gefahr die Polizei. Bei Verletzungen oder akutem medizinischem Bedarf die Rettung alarmieren. Kehren Sie nicht wegen Gegenständen an einen gefährlichen Ort zurück.",
                    [police, ambulance]),
                section(
                    "medical", "Медична допомога й документація", "Medizinische Hilfe und Dokumentation", "cross.case.fill",
                    "Зверніться до лікарні або лікаря після фізичного чи сексуального нападу, навіть якщо видимих травм мало. Попросіть задокументувати ушкодження та обговоріть із медиками необхідне лікування і збереження можливих доказів. При сексуальному насильстві зробіть це якомога швидше, бо частина медичних і доказових можливостей залежить від часу.",
                    "Suchen Sie nach körperlichem oder sexualisiertem Angriff ein Krankenhaus oder eine Ärztin beziehungsweise einen Arzt auf, auch bei wenigen sichtbaren Verletzungen. Bitten Sie um Dokumentation und besprechen Sie Behandlung sowie mögliche Spurensicherung. Nach sexualisierter Gewalt ist rasche Hilfe wichtig, weil manche medizinischen und forensischen Möglichkeiten zeitabhängig sind."
                ),
                section(
                    "report", "Заява й підтримка у процедурі", "Anzeige und Begleitung", "doc.text.fill",
                    "Про злочин можна повідомити в будь-якому відділку поліції. Якщо безпечно, збережіть повідомлення, фото й контакти свідків. Служба підтримки потерпілих пояснює права, допомагає знайти місцеву організацію та з’ясувати право на психосоціальний і юридичний супровід у процесі; консультація безкоштовна у робочі дні з 08:00 до 20:00.",
                    "Eine Straftat können Sie in jeder Polizeidienststelle anzeigen. Sichern Sie Nachrichten, Fotos und Zeugenkontakte, wenn dies gefahrlos möglich ist. Der Opfer-Notruf erklärt Rechte, vermittelt lokale Hilfe und klärt die Voraussetzungen für psychosoziale und juristische Prozessbegleitung; die kostenlose Telefonberatung ist werktags von 08:00 bis 20:00 Uhr erreichbar.",
                    [victims]),
            ], [
                DirectorySource(name: "Gewaltinfo · Medizinische Hilfe", url: "https://www.gewaltinfo.at/hilfe-finden/wer-bietet-hilfe-und-unterstuetzung-an/krankenhaeuser--aerzte-und-aerztinnen.html"),
                DirectorySource(name: "Opfer-Notruf · Beratung", url: "https://www.opfer-notruf.at/leistung/"),
                DirectorySource(name: "Opfer-Notruf · Prozessbegleitung", url: "https://www.opfer-notruf.at/opferhilfe/"),
                DirectorySource(name: "oesterreich.gv.at · Beratungsstellen für Opfer", url: "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/unterstuetzungen_fuer_verbrechensopfer/1"),
            ]),
        "discrimination": guide(
            "Розрізніть дискримінацію, домагання й переслідування; збережіть докази та зверніться в належну службу.",
            "Unterscheiden Sie Diskriminierung, Belästigung und Stalking; sichern Sie Belege und finden Sie Beratung.",
            [
                section(
                    "danger", "Погрози або напад", "Drohung oder Angriff", "exclamationmark.shield.fill",
                    "Якщо вам погрожують або переслідують зараз і є небезпека, викликайте поліцію. Не вступайте в контакт заради збору доказів. Збережіть повідомлення й дати подій пізніше, коли це безпечно.",
                    "Rufen Sie bei akuter Bedrohung oder gefährlichem Stalking die Polizei. Suchen Sie nicht allein wegen Beweisen Kontakt zur gefährdenden Person. Sichern Sie Nachrichten und Zeitpunkte später, wenn dies gefahrlos möglich ist.",
                    [police]),
                section(
                    "equal-treatment", "Дискримінація на роботі чи при пошуку житла", "Diskriminierung bei Arbeit oder Wohnung", "person.crop.rectangle.stack.fill",
                    "Служба рівного ставлення безкоштовно й конфіденційно перевіряє випадки расизму, сексизму, сексуальних домагань та інших захищених ознак. Вона консультує щодо роботи, пошуку житла і частини послуг; межі захисту залежать від сфери та підстави дискримінації. При звільненні звертайтеся негайно: оскарження дискримінаційного звільнення може мати строк лише 14 днів.",
                    "Die Gleichbehandlungsanwaltschaft prüft kostenlos und vertraulich Fälle von Rassismus, Sexismus, sexueller Belästigung und weiteren geschützten Merkmalen. Sie berät zu Arbeit, Wohnungssuche und bestimmten Dienstleistungen; der Schutz hängt vom Bereich und Merkmal ab. Bei Kündigung sofort Kontakt aufnehmen: Für die Anfechtung einer diskriminierenden Kündigung können nur 14 Tage bleiben.",
                    [equality]),
                section(
                    "evidence", "Що підготувати до консультації", "Was Sie für die Beratung sichern", "doc.on.doc.fill",
                    "Запишіть, хто, коли й де ухвалив рішення або вчинив дію. Збережіть оголошення, листування, відповіді, імена свідків та послідовність подій. При переслідуванні або злочині попросіть центр захисту чи службу потерпілих пояснити окремі способи захисту.",
                    "Notieren Sie, wer wann und wo eine Entscheidung traf oder handelte. Bewahren Sie Inserate, Nachrichten, Antworten, Zeugenkontakte und den zeitlichen Ablauf auf. Bei Stalking oder einer Straftat können Gewaltschutzzentrum oder Opfer-Notruf die zusätzlichen Schutzwege erläutern.",
                    [protectionCentre, victims]),
            ], [
                DirectorySource(name: "Gleichbehandlungsanwaltschaft · Beratung", url: "https://www.gleichbehandlungsanwaltschaft.gv.at/unser-angebot/beratung-und-unterstuetzung.html"),
                DirectorySource(name: "Gleichbehandlungsanwaltschaft · Was tun?", url: "https://www.gleichbehandlungsanwaltschaft.gv.at/unser-angebot/diskriminierung-was-kann-ich-tun.html"),
                DirectorySource(name: "oesterreich.gv.at · Meldestellen", url: "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/melde-und-beratungsstellen-in-oesterreich/melde__und_beratungsstellen"),
            ]),
        "mental-crisis": guide(
            "Невідкладна допомога при загрозі собі чи іншим і конфіденційна підтримка під час кризи.",
            "Akuthilfe bei Selbst- oder Fremdgefährdung und vertrauliche Unterstützung in Krisen.",
            [
                section(
                    "acute", "Коли потрібна екстрена допомога", "Wann sofort Hilfe nötig ist", "cross.case.fill",
                    "Якщо людина має намір завдати собі шкоди, не реагує або потребує негайної медичної допомоги, викликайте швидку. При безпосередній загрозі безпеці інших людей — поліцію. Залишайтеся поруч лише тоді, коли це безпечно; виконуйте вказівки диспетчера.",
                    "Bei unmittelbarer Selbstgefährdung, fehlender Reaktion oder akutem medizinischem Bedarf die Rettung rufen. Bei unmittelbarer Gefahr für andere die Polizei verständigen. Bleiben Sie nur dann bei der Person, wenn es sicher ist, und folgen Sie der Leitstelle.",
                    [ambulance, police]),
                section(
                    "own-crisis", "Якщо криза стосується вас", "Wenn Sie selbst in der Krise sind", "heart.text.square.fill",
                    "Скажіть довіреній людині прямо, що вам потрібна допомога, і не залишайтеся наодинці при сильних суїцидальних думках. Телефон довіри 142 доступний цілодобово й анонімно; дітям і підліткам допомагає 147. Якщо боїтеся, що можете діяти негайно, звертайтеся до екстреної служби, а не чекайте консультації.",
                    "Sagen Sie einer Vertrauensperson offen, dass Sie Hilfe brauchen, und bleiben Sie bei starken Suizidgedanken nicht allein. Die Telefonseelsorge 142 ist rund um die Uhr anonym erreichbar; Kinder und Jugendliche erhalten Hilfe unter 147. Wenn Sie befürchten, unmittelbar zu handeln, wählen Sie den Notruf statt auf Beratung zu warten.",
                    [crisis, children]),
                section(
                    "someone-else", "Як підтримати іншу людину", "Wie Sie einer anderen Person helfen", "person.2.fill",
                    "Сприймайте слова про самогубство серйозно, спокійно запитайте прямо про небезпеку й слухайте без осуду. Не обіцяйте зберігати гостру небезпеку в таємниці. При безпосередньому ризику не залишайте людину саму, якщо це безпечно, та організуйте професійну допомогу.",
                    "Nehmen Sie Suizidankündigungen ernst, fragen Sie ruhig und direkt nach der Gefahr und hören Sie ohne Vorwürfe zu. Versprechen Sie bei akuter Gefahr keine Geheimhaltung. Lassen Sie die Person bei unmittelbarem Risiko nicht allein, sofern dies sicher ist, und holen Sie professionelle Hilfe."
                ),
            ], [
                DirectorySource(name: "Gesundheitsportal · Krise und Suizidgefahr", url: "https://www.gesundheit.gv.at/leben/suizidpraevention/anlaufstellen/notrufnummern.html"),
                DirectorySource(name: "Gesundheitsportal · Suizidgedanken", url: "https://www.gesundheit.gv.at/leben/suizidpraevention/betroffene/erste-hilfe.html"),
                DirectorySource(name: "Gesundheitsportal · Angehörige", url: "https://www.gesundheit.gv.at/leben/suizidpraevention/angehoerige/was-soll-ich-tun.html"),
            ]),
    ]
}
