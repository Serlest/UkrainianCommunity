import SwiftUI

struct DirectoryTranslationInput {
    let field: DirectoryEditorField
    let text: Binding<DirectoryText>

    init(_ field: DirectoryEditorField, _ text: Binding<DirectoryText>) {
        self.field = field
        self.text = text
    }

    func translationField(sourceLanguage: AppLanguage) -> ContentTranslationField {
        let targetLanguage: AppLanguage = sourceLanguage == .ukrainian ? .german : .ukrainian
        return .init(field.rawValue, field.title, source: text.wrappedValue.value(for: sourceLanguage),
                     target: text.localized(targetLanguage), limit: field.limit)
    }

    static func article(_ topic: Binding<DirectoryManagedTopic>, firstSection: Bool = false) -> [Self] {
        var fields: [Self] = [.init(.articleTitle, topic.title), .init(.articleSummary, topic.summary)]
        if firstSection, !topic.wrappedValue.sections.isEmpty {
            fields += [.init(.sectionTitle, topic.sections[0].title), .init(.sectionBody, topic.sections[0].body)]
        }
        return fields
    }
}

struct DirectoryTranslationSection: View {
    let inputs: [DirectoryTranslationInput]
    let language: AppLanguage

    var body: some View {
        Section {
            ContentTranslationButton(kind: "directory", fields: inputs.map {
                $0.translationField(sourceLanguage: language)
            }, sourceLanguage: language)
        }
    }
}

/// Existing bilingual editors retain both visible languages and select the
/// direction explicitly. New forms reuse their existing editing-language picker.
struct DirectoryTranslationControls: View {
    let inputs: [DirectoryTranslationInput]
    @State private var sourceLanguage: AppLanguage = .ukrainian

    var body: some View {
        DirectoryEditingLanguagePicker(language: $sourceLanguage)
        DirectoryTranslationSection(inputs: inputs, language: sourceLanguage)
    }
}

extension Binding where Value == DirectoryText {
    func localized(_ language: AppLanguage) -> Binding<String> {
        Binding<String>(
            get: { wrappedValue.value(for: language) },
            set: { value in
                wrappedValue = .init(ukrainian: language == .ukrainian ? value : wrappedValue.ukrainian,
                                     german: language == .german ? value : wrappedValue.german)
            }
        )
    }
}
