import SwiftUI

struct DirectorySectionEditorView: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var section: DirectoryManagedSection
    private struct ContactDraft: Identifiable {
        let id = UUID()
        var content: DirectoryManagedContact
    }
    @State private var contactDrafts: [ContactDraft]

    init(section: Binding<DirectoryManagedSection>) {
        _section = section
        _contactDrafts = State(initialValue: section.wrappedValue.contacts.map { ContactDraft(content: $0) })
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
                ForEach(Array(contactDrafts.enumerated()), id: \.element.id) { index, draft in
                    let contact = contactBinding(for: draft)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(DirectoryEditorText.value("Контакт", "Kontakt"))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button(role: .destructive) {
                                contactDrafts.removeAll { $0.id == draft.id }
                                synchronizeContacts()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel(DirectoryEditorText.value("Видалити контакт", "Kontakt löschen"))
                            .accessibilityIdentifier("directory.contact.remove." + String(index))
                            .buttonStyle(.borderless)
                        }
                        TextField(DirectoryEditorText.value("Номер", "Nummer"),
                                  text: contact.number)
                            .accessibilityIdentifier("directory.contact.number." + String(index))
                            .keyboardType(.phonePad)
                        DirectoryTranslationControls(inputs: [
                            .init(.contactTitle, contact.title),
                            .init(.contactDetail, contact.detail)
                        ])
                        DirectoryBilingualFields(
                            field: .contactTitle,
                            text: contact.title
                        )
                        DirectoryBilingualFields(
                            field: .contactDetail,
                            text: contact.detail
                        )
                    }
                }
                Button {
                    contactDrafts.append(ContactDraft(content: .init(
                        number: "", title: .init(ukrainian: "", german: ""),
                        detail: .init(ukrainian: "", german: "")
                    )))
                    synchronizeContacts()
                } label: {
                    Label(DirectoryEditorText.value("Додати контакт", "Kontakt hinzufügen"),
                          systemImage: "plus")
                }
                .accessibilityIdentifier("directory.contact.add")
            }
        }
        .directoryEditorChrome()
        .navigationTitle(DirectoryEditorText.value("Блок інформації", "Informationsabschnitt"))
    }

    // Keep row identity and edited value in the same state. Two separate arrays
    // can be observed between their updates; stale index bindings can also
    // outlive a removed row during SwiftUI's Form diff.
    private func contactBinding(for draft: ContactDraft) -> Binding<DirectoryManagedContact> {
        Binding(
            get: { contactDrafts.first { $0.id == draft.id }?.content ?? draft.content },
            set: { value in
                guard let index = contactDrafts.firstIndex(where: { $0.id == draft.id }) else { return }
                contactDrafts[index].content = value
                synchronizeContacts()
            }
        )
    }

    private func synchronizeContacts() {
        section.contacts = contactDrafts.map(\.content)
    }

}
