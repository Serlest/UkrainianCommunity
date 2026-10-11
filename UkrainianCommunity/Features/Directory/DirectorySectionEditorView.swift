import SwiftUI

struct DirectorySectionEditorView: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var section: DirectoryManagedSection

    var body: some View {
        Form {
            DirectoryBilingualFields(title: DirectoryEditorText.value("Заголовок", "Überschrift"),
                                     text: $section.title)
            DirectoryBilingualFields(title: DirectoryEditorText.value("Інформація", "Information"),
                                     text: $section.body, multiline: true)
            Section(DirectoryEditorText.value("Показ", "Anzeige")) {
                TextField(DirectoryEditorText.value("Системна іконка", "Systemsymbol"),
                          text: $section.symbol)
                Stepper(value: $section.order, in: 0...1000) {
                    Text("\(DirectoryEditorText.value("Порядок", "Reihenfolge")): \(section.order)")
                }
                Toggle(DirectoryEditorText.value("Прибрати блок з довідника", "Abschnitt aus Ratgeber entfernen"),
                       isOn: $section.isHidden)
            }
            Section(DirectoryEditorText.value("Офіційне джерело", "Amtliche Quelle")) {
                if section.source != nil {
                    DirectorySourceFields(source: Binding(
                        get: { section.source ?? .init(name: "", url: "") },
                        set: { section.source = $0 }
                    ))
                    Button(role: .destructive) { section.source = nil } label: {
                        Text(DirectoryEditorText.value("Прибрати джерело блока", "Abschnittsquelle entfernen"))
                    }
                } else {
                    Button {
                        section.source = .init(name: "", url: "")
                    } label: {
                        Label(DirectoryEditorText.value("Додати джерело", "Quelle hinzufügen"),
                              systemImage: "plus")
                    }
                }
            }
            Section(DirectoryEditorText.value("Контактний номер", "Telefonnummer")) {
                TextField(DirectoryEditorText.value("Необов’язково", "Optional"),
                          text: Binding(
                            get: { section.phoneNumber ?? "" },
                            set: { section.phoneNumber = $0.isEmpty ? nil : $0 }
                          ))
                    .keyboardType(.phonePad)
            }
            Section(DirectoryEditorText.value("Екстрені контакти", "Notrufkontakte")) {
                ForEach(section.contacts.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(DirectoryEditorText.value("Номер", "Nummer"),
                                  text: $section.contacts[index].number)
                            .keyboardType(.phonePad)
                        DirectoryBilingualFields(
                            title: DirectoryEditorText.value("Назва", "Name"),
                            text: $section.contacts[index].title
                        )
                        DirectoryBilingualFields(
                            title: DirectoryEditorText.value("Пояснення", "Hinweis"),
                            text: $section.contacts[index].detail
                        )
                    }
                }
                .onDelete { indices in section.contacts.remove(atOffsets: indices) }
                Button {
                    section.contacts.append(.init(
                        number: "", title: .init(ukrainian: "", german: ""),
                        detail: .init(ukrainian: "", german: "")
                    ))
                } label: {
                    Label(DirectoryEditorText.value("Додати контакт", "Kontakt hinzufügen"),
                          systemImage: "plus")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackgroundView())
        .navigationTitle(DirectoryEditorText.value("Блок інформації", "Informationsabschnitt"))
    }
}
