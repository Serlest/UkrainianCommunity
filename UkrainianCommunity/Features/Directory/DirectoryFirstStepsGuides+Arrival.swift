import Foundation

extension FirstStepsGuides {
    static let arrival = DirectoryGuide(
        cardSummary: .init(ukrainian: "Ночівля, медична допомога й важливі документи",
                           german: "Unterkunft, medizinische Hilfe und wichtige Unterlagen"),
        introduction: .init(
            ukrainian: "У перший день вирішіть, де безпечно переночувати і чи потрібна негайна допомога. Оформлення адреси та статусу — окремі наступні кроки.",
            german: "Klären Sie am ersten Tag eine sichere Übernachtung und akuten Hilfebedarf. Wohnsitzmeldung und Aufenthaltsstatus folgen als getrennte Schritte."
        ),
        sections: [
            .init("night", "bed.double.fill", "Немає житла на цю ніч", "Keine Unterkunft für heute Nacht",
                  "Зателефонуйте на україномовну лінію BBU. Назвіть землю, де ви перебуваєте, кількість дорослих і дітей та особливі потреби. На сторінці BBU відкрийте актуальний список пунктів первинного прийому й перевірте місце телефоном до поїздки: консультаційний пункт не обов’язково має ліжка, а наявність місць змінюється.",
                  "Rufen Sie die ukrainischsprachige BBU-Hotline an. Nennen Sie Bundesland, Zahl der Erwachsenen und Kinder sowie besondere Bedürfnisse. Öffnen Sie die aktuelle Erstankunftsübersicht der BBU und fragen Sie vor der Fahrt telefonisch nach einem Platz: Eine Beratungsstelle bietet nicht zwingend Betten, und freie Plätze ändern sich.",
                  phoneNumber: "+43 1 2676 870 9460", source: bbu),
            .init("private", "house.fill", "Ви зупинилися у знайомих", "Sie wohnen vorerst privat",
                  "Домовтеся про фактичну адресу, дату заселення й контакт людини, яка надала житло. Запитайте, чи підпише вона Meldezettel для кожного члена родини. Не використовуйте адресу, за якою ви насправді не живете; строк і спосіб реєстрації адреси пояснені в наступному маршруті.",
                  "Notieren Sie die tatsächliche Adresse, das Einzugsdatum und den Kontakt der Unterkunftgeberin oder des Unterkunftgebers. Klären Sie, ob diese Person für jedes Familienmitglied den Meldezettel unterschreibt. Verwenden Sie keine Adresse, an der Sie nicht wohnen; Frist und Ablauf stehen im nächsten Wegweiser.",
                  source: address),
            .init("hospital", "cross.case.fill", "Якщо лікування потрібне зараз", "Wenn Sie jetzt medizinische Hilfe brauchen",
                  "При тяжкому стані викликайте 144. Лікарня надасть невідкладну допомогу й до оформлення, але рахунок не покривається автоматично. Скажіть у лікарні, що ви щойно прибули з України, і попросіть допомогти з’ясувати можливість поліцейської реєстрації в лікарні та заяви на Grundversorgung, якщо ви маєте право на тимчасовий захист.",
                  "Bei einem schweren Notfall wählen Sie 144. Ein Krankenhaus behandelt Sie auch vor der Registrierung, doch die Kosten sind nicht automatisch gedeckt. Sagen Sie, dass Sie gerade aus der Ukraine angekommen sind, und fragen Sie nach einer möglichen polizeilichen Erfassung im Krankenhaus und dem Antrag auf Grundversorgung, falls Sie für vorübergehenden Schutz infrage kommen.",
                  phoneNumber: "144", source: bbuFAQ),
            .init("documents", "folder.fill", "Збережіть те, що знадобиться далі", "Wichtige Unterlagen sichern",
                  "Тримайте доступними паспорти, свідоцтва дітей, документи про шлюб або інший статус, а також наявні медичні довідки й ліки. Запишіть фактичну адресу і надійний номер телефону. Для поліцейської реєстрації беріть документи, які є; відсутність частини документів не означає, що звертатися не треба.",
                  "Halten Sie Reisepässe, Geburtsurkunden der Kinder, Nachweise zu Ehe oder anderem Status sowie vorhandene Befunde und Medikamente bereit. Notieren Sie Ihre tatsächliche Anschrift und eine erreichbare Telefonnummer. Bringen Sie zur polizeilichen Erfassung mit, was vorhanden ist; fehlende Unterlagen sind kein Grund, den Termin auszulassen.",
                  source: police)
        ],
        sources: [housing]
    )
}
