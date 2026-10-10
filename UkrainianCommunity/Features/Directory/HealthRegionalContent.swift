import Foundation

/// Local discovery uses official nationwide directories; the chosen state gives search context.
/// Medical rights and fees can depend on the state of the provider, not the user's residence.
enum HealthRegionalContent {
    static func applies(to topicID: String) -> Bool {
        ["doctors", "specialists", "clinics", "dental", "medication", "pregnancy", "patient-rights"]
            .contains(topicID)
    }

    static func sections(for topicID: String, state: AustrianFederalState) -> [DirectoryGuideSection] {
        switch topicID {
        case "doctors", "specialists":
            return [.init("regional-doctors", "stethoscope", "Лікарі у вашій землі", "Ärzte im Bundesland",
                          "В офіційному переліку відкрийте (state.displayName), оберіть спеціальність і перевірте, чи лікар має договір із вашою касою. Перед записом уточніть прийом нових пацієнтів, мову консультації та можливу оплату.",
                          "Öffnen Sie in der amtlichen Arztsuche (state.displayName), wählen Sie das Fach und prüfen Sie den Vertrag mit Ihrer Kasse. Vor dem Termin nach Aufnahme neuer Patienten, Sprache und möglichen Kosten fragen.",
                          source: HealthGuides.doctorSearch)]
        case "clinics":
            return [
                .init("regional-clinics", "cross.case", "Лікарні у вашій землі", "Spitäler im Bundesland",
                      "Знайдіть лікарню та потрібне відділення через офіційний пошук, вибравши (state.displayName). Для планового лікування запитайте про направлення, очікування і чи заклад має договір із вашою касою. При невідкладній загрозі телефонуйте 144.",
                      "Suchen Sie Spital und Fachabteilung in der amtlichen Kliniksuche für (state.displayName). Bei geplanter Behandlung Überweisung, Wartezeit und Kassenvertrag klären. Bei akutem Notfall 144 wählen.",
                      source: HealthGuides.clinicSearch),
                .init("regional-hospital-costs", "eurosign.circle", "Внесок за перебування", "Kostenbeitrag im Spital",
                      "Щоденний внесок у загальному класі може відрізнятися за федеральною землею й видом лікарні. До планової госпіталізації запитайте лікарню та касу про суму, винятки і окрему оплату Sonderklasse; не оцінюйте витрати за тарифом іншої землі.",
                      "Der tägliche Beitrag in der allgemeinen Klasse kann je Bundesland und Krankenanstalt variieren. Vor geplanter Aufnahme Spital und Kasse nach Betrag, Ausnahmen und Sonderklasse-Kosten fragen; Tarife anderer Länder nicht übernehmen.",
                      source: HealthGuides.hospitalCosts)
            ]
        case "dental":
            return [.init("regional-dental", "mouth", "Стоматологічна допомога поруч", "Zahnbehandlung in der Nähe",
                          "Перевірте стоматологів у пошуку лікарів для (state.displayName) або знайдіть центр стоматологічного здоров’я ÖGK. Перед лікуванням запитайте, які саме процедури покриває ваша каса та чи потрібен план витрат.",
                          "Suchen Sie Zahnärzte für (state.displayName) oder ein ÖGK-Zahngesundheitszentrum. Vor der Behandlung nach Kassendeckung der einzelnen Leistungen und einem Kostenplan fragen.",
                          source: HealthGuides.doctorSearch)]
        case "medication":
            return [.init("regional-pharmacy", "cross.vial", "Аптека й нічне чергування", "Apotheke und Nachtdienst",
                          "Знайдіть аптеку у (state.displayName) через офіційний пошук і перевірте, яка саме чергує сьогодні. Час чергування й наявність потрібних ліків уточніть телефоном перед поїздкою.",
                          "Suchen Sie eine Apotheke in (state.displayName) über die amtliche Suche und prüfen Sie den heutigen Notdienst. Dienstzeit und Verfügbarkeit des Arzneimittels vor der Fahrt telefonisch bestätigen.",
                          source: HealthGuides.pharmacySearch)]
        case "pregnancy":
            return [.init("regional-birth", "figure.and.child.holdinghands", "Місце пологів", "Geburtsort wählen",
                          state == .wien
                            ? "У Відні дізнайтеся про централізований запис на пологи через Geburtsinfo Wien та строки реєстрації. Якщо маєте медичні ризики, обговоріть відповідний заклад із лікарем або акушеркою."
                            : "Порівняйте пологові відділення у (state.displayName), строки запису та доступність акушерської допомоги. Якщо є медичні ризики, узгодьте заклад із лікарем або акушеркою.",
                          state == .wien
                            ? "In Wien informieren Sie sich über die zentrale Anmeldung über Geburtsinfo Wien und deren Fristen. Bei medizinischen Risiken die passende Klinik mit Arzt oder Hebamme besprechen."
                            : "Vergleichen Sie Geburtsabteilungen in (state.displayName), Anmeldefristen und Hebammenbetreuung. Bei medizinischen Risiken die Klinik mit Arzt oder Hebamme abstimmen.",
                          source: HealthGuides.birth)]
        case "patient-rights":
            return [.init("regional-advocacy", "person.crop.rectangle", "Незалежна допомога зі скаргою", "Unabhängige Hilfe bei Beschwerden",
                          "У переліку Patientenanwaltschaft оберіть федеральну землю, де розташований заклад, щодо якого подаєте скаргу. Це може бути не (state.displayName), якщо лікувалися в іншій землі. Перевірте, чи служба розглядає скарги на приватні ординації.",
                          "Wählen Sie in der Liste der Patientenanwaltschaften das Bundesland der betroffenen Einrichtung. Das muss nicht (state.displayName) sein, wenn die Behandlung anderswo stattfand. Prüfen Sie die Zuständigkeit für niedergelassene Ärzte.",
                          source: HealthGuides.patientAdvocacy)]
        default: return []
        }
    }
}
