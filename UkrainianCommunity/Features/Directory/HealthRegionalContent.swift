import Foundation

/// Local discovery uses official nationwide directories; the chosen state gives search context.
/// Medical rights and fees can depend on the state of the provider, not the user's residence.
enum HealthRegionalContent {
    static func applies(to topicID: String) -> Bool {
        ["specialists", "clinics", "pregnancy", "patient-rights"]
            .contains(topicID)
    }

    static func sections(for topicID: String, state: AustrianFederalState) -> [DirectoryGuideSection] {
        switch topicID {
        case "specialists":
            return [.init("regional-doctors", "stethoscope", "Лікарі у вашій землі", "Ärzte im Bundesland",
                          "В офіційному переліку виберіть \(state.displayName), потрібну спеціальність і касу. Перевірте доступність спеціаліста та чи виконує саме він призначене обстеження; вимоги до направлення уточніть до запису.",
                          "Wählen Sie in der amtlichen Arztsuche \(state.displayName), das Fach und Ihre Kasse. Prüfen Sie, ob die Praxis genau die benötigte Untersuchung anbietet, und klären Sie die Überweisung vor dem Termin.",
                          source: HealthGuides.doctorSearch)]
        case "clinics":
            return [
                .init("regional-hospital-costs", "eurosign.circle", "Внесок за перебування", "Kostenbeitrag im Spital",
                      "Для планового лікування у \(state.displayName) запитайте саме вибрану лікарню та свою касу про добовий внесок у загальному класі, винятки й окрему оплату Sonderklasse. Сума залежить від землі та закладу; тариф іншої землі не підходить.",
                      "Für eine geplante Aufnahme in \(state.displayName) fragen Sie das konkrete Spital und Ihre Kasse nach dem täglichen Beitrag in der allgemeinen Klasse, Ausnahmen und Sonderklasse-Kosten. Betrag und Regeln unterscheiden sich je Land und Einrichtung.",
                      source: HealthGuides.hospitalCosts)
            ]
        case "pregnancy":
            return [.init("regional-birth", "figure.and.child.holdinghands", "Місце пологів", "Geburtsort wählen",
                          state == .wien
                            ? "У Відні використайте офіційну Geburtsinfo Wien для централізованого запису на пологи та перевірки пологових відділень. Зверніться завчасно; при медичних ризиках обговоріть заклад із лікарем або акушеркою."
                            : "У пошуку лікарень виберіть \(state.displayName) і пологове відділення. Зателефонуйте для перевірки строку запису, умов супроводу та доступності акушерки; при медичних ризиках обговоріть заклад із лікарем.",
                          state == .wien
                            ? "Nutzen Sie in Wien die amtliche Geburtsinfo Wien für die zentrale Anmeldung und den Vergleich von Geburtsabteilungen. Melden Sie sich früh; bei medizinischen Risiken die Klinik mit Arzt oder Hebamme besprechen."
                            : "Wählen Sie in der Kliniksuche \(state.displayName) und eine Geburtsabteilung. Fragen Sie nach Anmeldefrist, Begleitung und Hebammenbetreuung; bei medizinischen Risiken die Klinik ärztlich abstimmen.",
                          source: state == .wien ? HealthGuides.viennaBirth : HealthGuides.clinicSearch)]
        case "patient-rights":
            return [.init("regional-advocacy", "person.crop.rectangle", "Незалежна допомога зі скаргою", "Unabhängige Hilfe bei Beschwerden",
                          "У переліку Patientenanwaltschaft оберіть землю, де розташований заклад. Якщо лікувалися у \(state.displayName), виберіть цю землю; якщо в іншій — змініть вибір за місцем закладу. Перевірте, чи служба розглядає скарги на приватні ординації.",
                          "Wählen Sie die Patientenanwaltschaft am Ort der betroffenen Einrichtung. Bei Behandlung in \(state.displayName) ist dieses Land zuständig; sonst wechseln Sie zum Standort der Einrichtung. Prüfen Sie die Zuständigkeit für niedergelassene Ärzte.",
                          source: HealthGuides.patientAdvocacy)]
        default: return []
        }
    }
}
