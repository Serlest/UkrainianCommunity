import SwiftUI

struct DirectoryAddTopicView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var topic: DirectoryManagedTopic
    @State private var editingLanguage: AppLanguage = .ukrainian
    @State private var errorMessage: String?
    let onAdd: (DirectoryManagedTopic) -> Void

    init(groupID: String, order: Int, onAdd: @escaping (DirectoryManagedTopic) -> Void) {
        _topic = State(initialValue: DirectoryEditorDrafts.topic(groupID: groupID, order: order))
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            Form {
                DirectoryEditingLanguagePicker(language: $editingLanguage)
                DirectoryFirstArticleFields(topic: $topic, language: editingLanguage)
            }
            .directoryEditorChrome()
            .navigationTitle(DirectoryEditorText.value("Нова стаття", "Neuer Beitrag"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DirectoryEditorText.value("Скасувати", "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(DirectoryEditorText.value("Додати", "Hinzufügen"), action: add)
                }
            }
            .alert(DirectoryEditorText.value("Перевірте статтю", "Beitrag prüfen"),
                   isPresented: Binding(get: { errorMessage != nil },
                                        set: { if !$0 { errorMessage = nil } })) {
                Button(DirectoryEditorText.value("Гаразд", "OK")) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func add() {
        if let missing = DirectoryEditorDrafts.firstMissingLanguage(in: [
            topic.title, topic.summary, topic.sections[0].title, topic.sections[0].body
        ]) {
            editingLanguage = missing
            errorMessage = DirectoryEditorText.value(
                "Заповніть поля вибраною мовою.", "Füllen Sie die Felder in der gewählten Sprache aus."
            )
            return
        }
        let sample = DirectoryManagedCategory(
            id: "draft", placement: .start, order: 0, isHidden: false,
            title: .init(ukrainian: "Стаття", german: "Beitrag"),
            summary: .init(ukrainian: "Опис", german: "Beschreibung"),
            symbol: "books.vertical.fill",
            groups: [.init(id: topic.groupID,
                           title: .init(ukrainian: "Основне", german: "Allgemein"),
                           order: 0, isHidden: false)],
            topics: [topic]
        )
        do {
            _ = try DirectoryManagedValidation.validate(sample)
            onAdd(topic)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DirectoryAddGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = DirectoryText(ukrainian: "", german: "")
    @State private var showError = false
    let onAdd: (DirectoryText) -> Void

    var body: some View {
        NavigationStack {
            Form {
                DirectoryBilingualFields(title: DirectoryEditorText.value("Назва підкатегорії", "Name des Unterbereichs"),
                                         text: $title)
            }
            .directoryEditorChrome()
            .navigationTitle(DirectoryEditorText.value("Нова підкатегорія", "Neuer Unterbereich"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DirectoryEditorText.value("Скасувати", "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(DirectoryEditorText.value("Додати", "Hinzufügen")) {
                        guard !title.ukrainian.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              !title.german.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              title.ukrainian.utf16.count <= 100,
                              title.german.utf16.count <= 100 else {
                            showError = true
                            return
                        }
                        onAdd(title)
                        dismiss()
                    }
                }
            }
            .alert(DirectoryEditorText.value("Вкажіть назву обома мовами (до 100 символів)",
                                             "Namen in beiden Sprachen eingeben (bis 100 Zeichen)"),
                   isPresented: $showError) {
                Button(DirectoryEditorText.value("Гаразд", "OK"), role: .cancel) { }
            }
        }
    }
}
