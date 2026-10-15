import SwiftUI

struct DirectorySectionEditorView: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var section: DirectoryManagedSection
    @State private var contactRowIDs: [UUID]

    init(section: Binding<DirectoryManagedSection>) {
        _section = section
        _contactRowIDs = State(initialValue: section.wrappedValue.contacts.map { _ in UUID() })
    }

    var body: some View {
        Form {
            DirectoryTranslationControls(inputs: [.init(.sectionTitle, $section.title), .init(.sectionBody, $section.body)])
            DirectoryBilingualFields(field: .sectionTitle,
                                     text: $section.title)
            DirectoryBilingualFields(field: .sectionBody,
                                     text: $section.body, multiline: true, required: !section.isHidden)
            Section(DirectoryEditorText.value("Показ", "Anzeige")) {
                NavigationLink {
                    DirectorySymbolPicker(selection: $section.symbol)
                } label: {
                    Label(DirectoryEditorText.value("Іконка блока", "Symbol des Abschnitts"),
                          systemImage: section.symbol)
                }
                Toggle(DirectoryEditorText.value("Тимчасово приховати блок", "Abschnitt vorübergehend ausblenden"),
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
                ForEach(Array(contactRowIDs.enumerated()), id: \.element) { index, _ in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(DirectoryEditorText.value("Контакт", "Kontakt"))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button(role: .destructive) {
                                section.contacts.remove(at: index)
                                contactRowIDs.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel(DirectoryEditorText.value("Видалити контакт", "Kontakt löschen"))
                        }
                        TextField(DirectoryEditorText.value("Номер", "Nummer"),
                                  text: $section.contacts[index].number)
                            .keyboardType(.phonePad)
                        DirectoryTranslationControls(inputs: [
                            .init(.contactTitle, $section.contacts[index].title),
                            .init(.contactDetail, $section.contacts[index].detail)
                        ])
                        DirectoryBilingualFields(
                            field: .contactTitle,
                            text: $section.contacts[index].title
                        )
                        DirectoryBilingualFields(
                            field: .contactDetail,
                            text: $section.contacts[index].detail
                        )
                    }
                }
                Button {
                    section.contacts.append(.init(
                        number: "", title: .init(ukrainian: "", german: ""),
                        detail: .init(ukrainian: "", german: "")
                    ))
                    contactRowIDs.append(UUID())
                } label: {
                    Label(DirectoryEditorText.value("Додати контакт", "Kontakt hinzufügen"),
                          systemImage: "plus")
                }
            }
        }
        .directoryEditorChrome()
        .navigationTitle(DirectoryEditorText.value("Блок інформації", "Informationsabschnitt"))
    }
}
