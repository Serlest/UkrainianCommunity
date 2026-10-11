import SwiftUI

/// The first publishable category is prepared in one place. Later edits use the
/// regular outline, where editors can add more groups, articles and sections.
struct DirectoryNewCategoryFormView: View {
    @Binding var draft: DirectoryManagedCategory
    @Binding var editingLanguage: AppLanguage

    var body: some View {
        Form {
            DirectoryEditingLanguagePicker(language: $editingLanguage)
            Section {
                LabeledContent(DirectoryEditorText.value("Розділ довідника", "Ratgeber-Rubrik"),
                               value: placementTitle)
                NavigationLink {
                    DirectorySymbolPicker(selection: $draft.symbol)
                } label: {
                    Label(DirectoryEditorText.value("Зображення категорії", "Bereichssymbol"),
                          systemImage: draft.symbol)
                }
            } footer: {
                Text(DirectoryEditorText.value(
                    "Категорія з’явиться у вибраній рубриці після публікації.",
                    "Nach der Veröffentlichung erscheint der Bereich in dieser Rubrik."
                ))
            }

            DirectoryLocalizedEditorField(title: DirectoryEditorText.value("Назва категорії", "Name des Bereichs"),
                                          text: $draft.title, language: editingLanguage)
            DirectoryLocalizedEditorField(title: DirectoryEditorText.value("Короткий опис категорії", "Kurzbeschreibung des Bereichs"),
                                          text: $draft.summary, language: editingLanguage)

            DirectoryFirstArticleFields(topic: $draft.topics[0], language: editingLanguage)
        }
        .directoryEditorChrome()
    }

    private var placementTitle: String {
        switch draft.placement {
        case .start: DirectoryStrings.startHeading
        case .life: DirectoryStrings.lifeHeading
        case .support: DirectoryStrings.supportHeading
        }
    }
}

struct DirectoryFirstArticleFields: View {
    @Binding var topic: DirectoryManagedTopic
    let language: AppLanguage

    var body: some View {
        DirectoryLocalizedEditorField(title: DirectoryEditorText.value("Назва статті", "Beitragstitel"),
                                      text: $topic.title, language: language)
        DirectoryLocalizedEditorField(title: DirectoryEditorText.value("Короткий вступ", "Kurze Einleitung"),
                                      text: $topic.summary, language: language, multiline: true)
        DirectoryLocalizedEditorField(title: DirectoryEditorText.value("Заголовок інформації", "Überschrift der Information"),
                                      text: $topic.sections[0].title, language: language)
        DirectoryLocalizedEditorField(title: DirectoryEditorText.value("Інформація", "Information"),
                                      text: $topic.sections[0].body, language: language, multiline: true)
        Section {
            DirectorySourceFields(source: $topic.sources[0])
        } header: {
            Text(DirectoryEditorText.value("Офіційне джерело", "Amtliche Quelle"))
        } footer: {
            Text(DirectoryEditorText.value(
                "Вкажіть назву установи та посилання https://. Без джерела статтю не можна опублікувати.",
                "Geben Sie die Behörde und einen https://-Link an. Ohne Quelle ist keine Veröffentlichung möglich."
            ))
        }
    }
}
