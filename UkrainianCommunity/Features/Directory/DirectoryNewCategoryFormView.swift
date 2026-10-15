import SwiftUI

/// The first publishable category is prepared in one place. Later edits use the
/// regular outline, where editors can add more groups, articles and sections.
struct DirectoryNewCategoryFormView: View {
    @Binding var draft: DirectoryManagedCategory
    @Binding var editingLanguage: AppLanguage

    var body: some View {
        Form {
            DirectoryEditingLanguagePicker(language: $editingLanguage)
            DirectoryTranslationSection(inputs: [.init(.categoryTitle, $draft.title), .init(.categorySummary, $draft.summary)] + DirectoryTranslationInput.article($draft.topics[0], firstSection: true), language: editingLanguage)
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

            DirectoryLocalizedEditorField(field: .categoryTitle,
                                          text: $draft.title, language: editingLanguage)
            DirectoryLocalizedEditorField(field: .categorySummary,
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
        DirectoryLocalizedEditorField(field: .articleTitle,
                                      text: $topic.title, language: language)
        DirectoryLocalizedEditorField(field: .articleSummary,
                                      text: $topic.summary, language: language, multiline: true)
        DirectoryLocalizedEditorField(field: .sectionTitle,
                                      text: $topic.sections[0].title, language: language)
        DirectoryLocalizedEditorField(field: .sectionBody,
                                      text: $topic.sections[0].body, language: language, multiline: true)
        Section {
            DirectorySourceFields(source: $topic.sources[0])
        } header: {
            Text(DirectoryEditorText.value("Офіційне джерело", "Amtliche Quelle"))
        } footer: {
            Text(DirectoryEditorText.value(
                "Вкажіть назву установи та адресу сторінки. HTTPS додамо автоматично. Без джерела статтю не можна опублікувати.",
                "Geben Sie die Behörde und die Seitenadresse an. HTTPS wird automatisch ergänzt. Ohne Quelle ist keine Veröffentlichung möglich."
            ))
        }
    }
}
