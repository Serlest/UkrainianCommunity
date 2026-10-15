import SwiftUI

struct DirectoryAddSectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var section: DirectoryManagedSection
    @State private var editingLanguage: AppLanguage = .ukrainian
    @State private var errorMessage: String?
    @State private var showsValidation = false
    let onAdd: (DirectoryManagedSection) -> Void

    init(order: Int, onAdd: @escaping (DirectoryManagedSection) -> Void) {
        var draft = DirectoryEditorDrafts.section(order: order)
        draft.source = .init(name: "", url: "")
        _section = State(initialValue: draft)
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            Form {
                DirectoryEditingLanguagePicker(language: $editingLanguage)
                DirectoryTranslationSection(inputs: [.init(.sectionTitle, $section.title), .init(.sectionBody, $section.body)], language: editingLanguage)
                DirectoryLocalizedEditorField(field: .sectionTitle,
                                              text: $section.title, language: editingLanguage)
                DirectoryLocalizedEditorField(field: .sectionBody,
                                              text: $section.body, language: editingLanguage, multiline: true)
                Section(DirectoryEditorText.value("Офіційне джерело", "Amtliche Quelle")) {
                    DirectorySourceFields(source: Binding(
                        get: { section.source ?? .init(name: "", url: "") },
                        set: { section.source = $0 }
                    ))
                }
            }
            .environment(\.directoryShowsValidation, showsValidation)
            .directoryEditorChrome()
            .navigationTitle(DirectoryEditorText.value("Новий блок", "Neuer Abschnitt"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DirectoryEditorText.value("Скасувати", "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(DirectoryEditorText.value("Додати", "Hinzufügen"), action: add)
                }
            }
            .alert(DirectoryEditorText.value("Перевірте інформацію", "Information prüfen"),
                   isPresented: Binding(get: { errorMessage != nil },
                                        set: { if !$0 { errorMessage = nil } })) {
                Button(DirectoryEditorText.value("Гаразд", "OK")) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func add() {
        section = DirectorySourceValidation.normalizingSources(in: section)
        showsValidation = true
        let sampleTopic = DirectoryManagedTopic(
            id: "draft-topic", groupID: "general", order: 0, isHidden: false,
            title: .init(ukrainian: "Стаття", german: "Beitrag"),
            summary: .init(ukrainian: "Вступ", german: "Einleitung"),
            sections: [section], sources: [], regionalSections: [:]
        )
        let sample = DirectoryManagedCategory(
            id: "draft", placement: .start, order: 0, isHidden: false,
            title: .init(ukrainian: "Категорія", german: "Bereich"),
            summary: .init(ukrainian: "Опис", german: "Beschreibung"),
            symbol: "books.vertical.fill",
            groups: [.init(id: "general",
                           title: .init(ukrainian: "Основне", german: "Allgemein"),
                           order: 0, isHidden: false)], topics: [sampleTopic]
        )
        do {
            _ = try DirectoryManagedValidation.validate(sample)
            onAdd(section)
            dismiss()
        } catch {
            if let language = (error as? DirectoryManagedValidation.Failure)?.language {
                editingLanguage = language
            }
            errorMessage = error.localizedDescription
        }
    }
}
