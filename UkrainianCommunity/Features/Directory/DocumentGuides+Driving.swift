import Foundation

extension DocumentGuides {
    static let licence = DirectoryGuide(
        cardSummary: .init(ukrainian: "Тимчасовий захист: без обміну; інший статус: інші правила", german: "Mit Schutz ohne Umtausch; sonst gelten andere Regeln"),
        introduction: .init(ukrainian: "Спершу перевірте, чи маєте тимчасовий захист і чи дійсне посвідчення водія. Для цих людей діє окремий регламент ЄС.", german: "Prüfen Sie zuerst, ob Sie vorübergehenden Schutz und einen gültigen Führerschein haben. Dafür gilt eine besondere EU-Verordnung."),
        sections: [
            .init("protected", "car", "За тимчасового захисту", "Mit vorübergehendem Schutz",
                  "Дійсне українське посвідчення визнається в ЄС протягом дії тимчасового захисту. Австрійський уряд указує, що спеціальний порядок діє наразі щонайпізніше до 4 березня 2027 року. Обмін не обов’язковий; добровільний обмін після шести місяців проживання зазвичай вимагає практичного іспиту. Правила ЄС не вимагають міжнародного посвідчення або засвідченого перекладу лише через українську мову. Візьміть також документ особи та підтвердження статусу.",
                  "Ein gültiger ukrainischer Führerschein wird in der EU während des vorübergehenden Schutzes anerkannt. Laut österreichischer Regierung gilt die Sonderregel derzeit längstens bis 4. März 2027. Der Umtausch ist nicht Pflicht; ein freiwilliger Umtausch nach sechs Monaten Wohnsitz erfordert in der Regel eine praktische Prüfung. Die EU-Regeln verlangen nicht allein wegen Ukrainisch einen internationalen Führerschein oder eine beglaubigte Übersetzung. Führen Sie Ausweis und Statusnachweis mit.", source: licenceUkraineFAQ),
            .init("other", "arrow.triangle.2.circlepath", "Якщо тимчасового захисту немає", "Ohne vorübergehenden Schutz",
                  "За загальним правилом Австрії посвідчення з країни поза ЄЕЗ після встановлення місця проживання дає право керувати зазвичай шість місяців; далі потрібен обмін. Для українського посвідчення при звичайному обміні, як правило, потрібен практичний іспит. Заяву подають до Führerscheinbehörde; перевірте чинність посвідчення й вимоги до фото, медичного висновку та перекладу.",
                  "Nach der allgemeinen österreichischen Regel erlaubt ein Nicht-EWR-Führerschein nach Wohnsitzbegründung grundsätzlich sechs Monate das Lenken; danach ist ein Umtausch nötig. Beim regulären Umtausch eines ukrainischen Führerscheins ist im Regelfall eine praktische Prüfung erforderlich. Beantragen Sie bei der Führerscheinbehörde und prüfen Sie Gültigkeit, Foto, ärztliches Gutachten und Übersetzung.", source: licenceAT),
            .init("lost", "exclamationmark.triangle", "Якщо посвідчення втрачено", "Bei Verlust des Führerscheins",
                  "Не сідайте за кермо лише з фото або записом у Дії, доки компетентний орган не підтвердить право. За правилами ЄС держава перебування може після перевірки українського права видати тимчасовий документ захищеній особі; уточніть це в австрійській Führerscheinbehörde. Українське посвідчення можна відновлювати через сервіси МВС України, якщо виконані їхні умови.",
                  "Fahren Sie nicht allein mit einem Foto oder Diia-Eintrag, bis die zuständige Behörde das Recht geklärt hat. Nach EU-Regeln kann der Aufenthaltsstaat einer geschützten Person nach Prüfung des ukrainischen Fahrrechts ein befristetes Dokument ausstellen; fragen Sie die österreichische Führerscheinbehörde. Ein ukrainischer Führerschein kann unter Voraussetzungen über ukrainische MVS-Dienste ersetzt werden.", source: licenceEU),
            .init("digital", "iphone", "Цифрове посвідчення й професійне водіння", "Digitaler Nachweis und Berufskraftverkehr",
                  "Цифровий запис у Дії не слід вважати універсальною заміною фізичного посвідчення за кордоном: орган має мати можливість перевірити дані. Для професійного перевезення пасажирів або вантажів діють окремі вимоги до кваліфікації водія, навіть якщо саме право керування визнається.",
                  "Ein Diia-Eintrag ist keine allgemeine Ersatzkarte im Ausland; die Behörde muss die Daten prüfen können. Für gewerblichen Personen- oder Güterverkehr gelten zusätzliche Qualifikationsregeln, selbst wenn die Fahrerlaubnis anerkannt wird.", source: licenceEU)
        ], sources: [licenceEU, licenceUkraineFAQ, licenceAT, licenceUA,
                     DirectorySource(name: "EU-Kommission · Fragen zu ukrainischen Führerscheinen", url: "https://transport.ec.europa.eu/questions-and-answers-new-temporary-eu-rules-ukrainian-driving-documents_en")]
    )
}
