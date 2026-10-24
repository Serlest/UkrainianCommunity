import SwiftUI

struct DirectoryAddTopicView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var discard = false
    private let initial: DirectoryManagedTopic
    @State private var topic: DirectoryManagedTopic
    @State private var editingLanguage: AppLanguage = .ukrainian
    @State private var errorMessage: String?
    @State private var showsValidation = false
    let onAdd: (DirectoryManagedTopic) -> Void

    init(groupID: String, order: Int, onAdd: @escaping (DirectoryManagedTopic) -> Void) {
        initial = DirectoryEditorDrafts.topic(groupID: groupID, order: order)
        _topic = State(initialValue: initial)
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            Form {
                DirectoryEditingLanguagePicker(language: $editingLanguage)
                DirectoryTranslationSection(inputs: DirectoryTranslationInput.article($topic, firstSection: true), language: editingLanguage)
                DirectoryFirstArticleFields(topic: $topic, language: editingLanguage)
                Section {
                    Text(DirectoryEditorText.value(
                        "«Додати» переносить статтю до чернетки категорії. Щоб читачі побачили зміни, натисніть «Опублікувати» в редакторі категорії.",
                        "„Hinzufügen“ übernimmt den Beitrag in den Bereichsentwurf. Damit Leser die Änderungen sehen, wählen Sie dort „Veröffentlichen“."
                    )).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                }
            }
            .environment(\.directoryShowsValidation, showsValidation)
            .directoryEditorChrome()
            .navigationTitle(DirectoryEditorText.value("Нова стаття", "Neuer Beitrag"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DirectoryEditorText.value("Скасувати", "Abbrechen")) { if topic != initial { discard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(DirectoryEditorText.value("Додати", "Hinzufügen"), action: add)
                }
            }
            .modifier(DirectoryDraftDiscard(hasChanges: topic != initial, isPresented: $discard))
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
        topic = DirectorySourceValidation.normalizingSources(in: topic)
        showsValidation = true
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
            if let language = (error as? DirectoryManagedValidation.Failure)?.language {
                editingLanguage = language
            }
            errorMessage = error.localizedDescription
        }
    }
}

struct DirectoryAddGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var discard = false
    @State private var title = DirectoryText(ukrainian: "", german: "")
    @State private var showError = false
    @State private var groupIssue = ""
    let onAdd: (DirectoryText) -> Void

    var body: some View {
        NavigationStack {
            Form {
                DirectoryTranslationControls(inputs: [.init(.groupTitle, $title)])
                DirectoryBilingualFields(field: .groupTitle,
                                         text: $title)
            }
            .directoryEditorChrome()
            .navigationTitle(DirectoryEditorText.value("Нова підкатегорія", "Neuer Unterbereich"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DirectoryEditorText.value("Скасувати", "Abbrechen")) { if !title.ukrainian.isEmpty || !title.german.isEmpty { discard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(DirectoryEditorText.value("Додати", "Hinzufügen")) {
                        for language in [AppLanguage.ukrainian, .german] {
                            if let issue = DirectoryEditorField.groupTitle.issue(for: title.value(for: language), language: language) {
                                groupIssue = issue
                                showError = true
                                return
                            }
                        }
                        onAdd(title)
                        dismiss()
                    }
                }
            }
            .modifier(DirectoryDraftDiscard(hasChanges: !title.ukrainian.isEmpty || !title.german.isEmpty, isPresented: $discard))
            .environment(\.directoryShowsValidation, showError)
            .alert(DirectoryEditorText.value("Перевірте підкатегорію", "Unterbereich prüfen"), isPresented: $showError) {
                Button(DirectoryEditorText.value("Гаразд", "OK"), role: .cancel) { }
            } message: { Text(groupIssue) }
        }
    }
}
