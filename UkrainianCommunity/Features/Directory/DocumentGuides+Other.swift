import Foundation

extension DocumentGuides {
    static let ukrainianTaxNumber = DirectoryGuide(
        cardSummary: .init(ukrainian: "РНОКПП через е-Консул або консульство", german: "Ukrainische Steuernummer über e-Consul oder Konsulat"),
        introduction: .init(ukrainian: "Український РНОКПП (податковий номер) потрібен для багатьох послуг України. Він не є австрійською Steuernummer чи Sozialversicherungsnummer.", german: "Die ukrainische Steuernummer (RNOKPP) wird für viele ukrainische Dienste benötigt. Sie ist weder die österreichische Steuernummer noch die Sozialversicherungsnummer."),
        sections: [
            .init("apply", "number", "Як отримати за кордоном", "Beantragung im Ausland",
                  "МЗС у 2026 році запровадило подання через «е-Консул» та українські дипломатичні установи. Для дорослих і підлітків від 14 років, дітей за заявою батька або матері та представників є різні процедури. Оберіть відповідну сторінку МЗС; перевірте, чи можна завершити дію онлайн або потрібен візит.",
                  "Das ukrainische Außenministerium führte 2026 Anträge über e-Consul und Auslandsvertretungen ein. Für Personen ab 14 Jahren, Kinder auf Antrag eines Elternteils und Vertreter gelten unterschiedliche Verfahren. Wählen Sie die passende MFA-Seite und prüfen Sie, ob der Antrag online abgeschlossen werden kann oder Vorsprache nötig ist.", source: taxNumber),
            .init("papers", "doc.text", "Підготуйте підтвердження", "Nachweise vorbereiten",
                  "Зазвичай потрібні український документ особи, відомості про адресу й, для дитини, свідоцтво про народження та документ законного представника. Зміна прізвища може вимагати документа про зв’язок старих і нових даних. Точний комплект залежить від віку й способу звернення.",
                  "Regelmäßig braucht es ukrainischen Ausweis, Adressangaben und bei Kindern Geburtsurkunde sowie Nachweis der gesetzlichen Vertretung. Bei Namensänderung kann eine Urkunde zur Verbindung alter und neuer Daten nötig sein. Die genaue Liste hängt von Alter und Antragsweg ab.", source: taxNumber),
            .init("electronic", "iphone", "Електронний результат", "Elektronisches Ergebnis",
                  "МЗС описує видачу картки платника податків в електронній формі після перевірки ДПС. Збережіть файл і спосіб перевірки його справжності. Перед поданням в Австрії спитайте, чи саме український номер або документ потрібен цій установі.",
                  "Das Außenministerium beschreibt die elektronische Ausstellung nach Prüfung durch die ukrainische Steuerbehörde. Bewahren Sie Datei und Prüfmöglichkeit auf. Fragen Sie vor Einreichung in Österreich, ob diese Stelle überhaupt die ukrainische Nummer oder Bescheinigung verlangt.", source: taxNumber)
        ], sources: [taxNumber, eConsul]
    )

    static let policeCertificate = DirectoryGuide(
        cardSummary: .init(ukrainian: "Український витяг і австрійська Strafregisterbescheinigung", german: "Ukrainischer Auszug und österreichische Strafregisterbescheinigung"),
        introduction: .init(ukrainian: "Спочатку спитайте установу, з якої країни потрібна довідка й за який період. Українська та австрійська довідки не замінюють одна одну.", german: "Fragen Sie zuerst, aus welchem Staat und für welchen Zeitraum ein Nachweis verlangt wird. Ukrainischer und österreichischer Strafregisterauszug ersetzen einander nicht."),
        sections: [
            .init("ukraine", "doc.text.magnifyingglass", "Витяг з України", "Auszug aus der Ukraine",
                  "Офіційна Дія дає змогу подати онлайн-запит на український витяг про несудимість і отримати електронний результат. Оберіть мету запиту. Для використання в Австрії уточніть у приймаючого органу, чи приймає він електронний оригінал, чи потрібен паперовий документ, апостиль МВС України та засвідчений переклад.",
                  "Über Diia kann ein ukrainischer Strafregisterauszug online beantragt und elektronisch erhalten werden; geben Sie den Zweck an. Für Österreich klären Sie, ob elektronisches Original genügt oder Papier, Apostille des ukrainischen Innenministeriums und beglaubigte Übersetzung verlangt werden.", source: criminalUA),
            .init("austria", "building.2", "Довідка з Австрії", "Auszug aus Österreich",
                  "Австрійську Strafregisterbescheinigung замовляють у компетентної поліції чи громади або через офіційний онлайн-сервіс. У Відні — у Polizeikommissariat. Для роботи з дітьми чи в догляді існують спеціальні форми; роботодавець має надати потрібне підтвердження. Запитайте, яка саме форма потрібна.",
                  "Die österreichische Strafregisterbescheinigung gibt es bei zuständiger Polizei oder Gemeinde sowie online. In Wien ist ein Polizeikommissariat zuständig. Für Kinder- oder Pflegearbeit gibt es besondere Varianten; der Arbeitgeber muss einen passenden Nachweis bereitstellen. Fragen Sie nach der benötigten Form.", source: criminalAT),
            .init("validity", "calendar", "Строк актуальності", "Wie aktuell muss der Auszug sein",
                  "Не замовляйте довідку надто рано: приймаюча установа сама визначає, наскільки новою вона має бути. Якщо потрібен документ з кількох країн проживання, уточніть перелік країн до оплати перекладів та апостилів.",
                  "Bestellen Sie den Auszug nicht zu früh: Die empfangende Stelle bestimmt, wie aktuell er sein muss. Wenn Auszüge aus mehreren früheren Wohnsitzstaaten benötigt werden, klären Sie die Länderliste vor Übersetzungen und Apostillen.", source: criminalAT)
        ], sources: [criminalUA, criminalAT, ukrainianApostille]
    )

    static let powerOfAttorney = DirectoryGuide(
        cardSummary: .init(ukrainian: "Довіреність для дій в Україні, нотаріус і консул", german: "Vollmacht für die Ukraine, Notar und Konsulat"),
        introduction: .init(ukrainian: "Для отримання документів, продажу майна чи представництва в Україні може знадобитися довіреність. Зміст і форму варто узгодити з органом або нотаріусом, де нею користуватимуться.", german: "Für Dokumentenabholung, Vermögen oder Vertretung in der Ukraine kann eine Vollmacht nötig sein. Inhalt und Form sollten mit der empfangenden Stelle oder dem Notar dort abgestimmt werden."),
        sections: [
            .init("consul", "signature", "Оформлення в консульстві України", "Bei einem ukrainischen Konsulat",
                  "Український консул може посвідчувати довіреності та деякі інші правочини; діловодство ведеться українською. Підготуйте точний текст повноважень, особисті дані представника й документи, які консульство вимагає. Консул не посвідчує всі види правочинів з українською нерухомістю — перевірте обмеження до запису.",
                  "Ukrainische Konsuln können Vollmachten und bestimmte weitere Rechtsgeschäfte beurkunden; das Verfahren läuft auf Ukrainisch. Bereiten Sie genaue Befugnisse, Daten des Bevollmächtigten und die verlangten Unterlagen vor. Nicht alle Geschäfte mit ukrainischen Immobilien dürfen konsularisch beurkundet werden; prüfen Sie Beschränkungen vor der Buchung.", source: notary),
            .init("austria", "building.columns", "Оформлення в Австрії", "Bei einem österreichischen Notar",
                  "Австрійський нотаріус може оформити документ для використання в Україні, але перед оплатою узгодьте текст і форму з українською приймаючою установою. Може знадобитися австрійський апостиль і належно засвідчений переклад українською. Консульська довіреність та австрійська нотаріальна довіреність проходять різні шляхи посвідчення.",
                  "Ein österreichischer Notar kann eine Urkunde für die Ukraine erstellen; stimmen Sie Text und Form vor Zahlung mit der ukrainischen Stelle ab. Österreichische Apostille und ordnungsgemäß beglaubigte ukrainische Übersetzung können nötig sein. Konsularische und österreichisch-notarielle Vollmachten haben unterschiedliche Beglaubigungswege.", source: austrianApostille),
            .init("limits", "checklist", "Обсяг і безпека", "Umfang und Sicherheit",
                  "Вказуйте конкретні дії, майно, строк і право передоручення лише якщо вони справді потрібні. Не підписуйте загальну довіреність для незнайомого посередника. Для скасування довіреності уточніть процедуру в установі, яка її оформила, та повідомте представника й органи, де документ використовували.",
                  "Nennen Sie konkrete Handlungen, Vermögen, Dauer und Untervollmacht nur, wenn nötig. Unterschreiben Sie keine weitreichende Vollmacht für unbekannte Vermittler. Für den Widerruf fragen Sie die ausstellende Stelle und informieren Bevollmächtigte und betroffene Behörden.", source: notary)
        ], sources: [notary, austrianApostille, vienna]
    )
}
