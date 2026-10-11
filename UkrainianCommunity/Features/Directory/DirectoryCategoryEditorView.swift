import FirebaseFunctions
import SwiftUI

struct DirectoryCategoryEditorView: View {
    private enum Confirmation { case publish, discard }
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @EnvironmentObject private var contentStore: DirectoryContentStore
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    private let focusTopicID: String?
    @State private var original: DirectoryManagedCategory
    @State private var draft: DirectoryManagedCategory
    @State private var expectedRevision: Int = 0
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmation: Confirmation?
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var hasUnsavedChanges: Bool { draft != original }

    init(category: DirectoryManagedCategory?, expectedRevision: Int = 0, focusTopicID: String? = nil) {
        self.focusTopicID = focusTopicID
        _expectedRevision = State(initialValue: expectedRevision)
        let initial = category ?? DirectoryManagedCategory(
            id: "custom-" + UUID().uuidString.lowercased(),
            placement: .support, order: 500, isHidden: false,
            title: .init(ukrainian: "", german: ""),
            summary: .init(ukrainian: "", german: ""), symbol: "books.vertical.fill",
            groups: [.init(id: "general", title: .init(ukrainian: "Основне", german: "Allgemein"),
                           order: 0, isHidden: false)],
            topics: []
        )
        _original = State(initialValue: initial)
        _draft = State(initialValue: initial)
    }

    private var categoryForm: some View {
        Form {
            Section {
                Text(DirectoryEditorText.value(
                    "Зміни з’являться для всіх після публікації. Приховування прибирає матеріал з довідника, але зберігає його для відновлення.",
                    "Änderungen erscheinen nach Veröffentlichung für alle. Ausblenden entfernt Inhalte aus dem Ratgeber, bewahrt sie aber zur Wiederherstellung."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if expectedRevision == 0 && original.title.ukrainian.isEmpty {
                    Text(DirectoryEditorText.value(
                        "Перед публікацією додайте статтю, інформаційний блок і офіційне джерело обома мовами.",
                        "Fügen Sie vor der Veröffentlichung einen Beitrag, einen Informationsabschnitt und eine amtliche Quelle in beiden Sprachen hinzu."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            DirectoryBilingualFields(title: DirectoryEditorText.value("Назва категорії", "Name des Bereichs"),
                                     text: $draft.title)
            DirectoryBilingualFields(title: DirectoryEditorText.value("Короткий опис", "Kurzbeschreibung"),
                                     text: $draft.summary)
            Section(DirectoryEditorText.value("Розміщення", "Platzierung")) {
                Picker(DirectoryEditorText.value("Розділ", "Bereich"), selection: $draft.placement) {
                    Text(DirectoryStrings.startHeading).tag(DirectoryManagedCategory.Placement.start)
                    Text(DirectoryStrings.lifeHeading).tag(DirectoryManagedCategory.Placement.life)
                    Text(DirectoryStrings.supportHeading).tag(DirectoryManagedCategory.Placement.support)
                }
                TextField(DirectoryEditorText.value("Системна іконка", "Systemsymbol"), text: $draft.symbol)
                Stepper(value: $draft.order, in: 0...1000) {
                    Text("\(DirectoryEditorText.value("Порядок", "Reihenfolge")): \(draft.order)")
                }
                Toggle(DirectoryEditorText.value("Прибрати категорію з довідника", "Bereich aus Ratgeber entfernen"),
                       isOn: $draft.isHidden)
            }
            Section(DirectoryEditorText.value("Підкатегорії", "Unterbereiche")) {
                ForEach($draft.groups) { $group in
                    NavigationLink {
                        DirectoryGroupEditorView(group: $group)
                    } label: {
                        Text(group.title.value(for: language))
                    }
                }
                Button {
                    draft.groups.append(.init(
                        id: "group-" + UUID().uuidString.lowercased(),
                        title: .init(ukrainian: "", german: ""),
                        order: draft.groups.count, isHidden: false
                    ))
                } label: {
                    Label(DirectoryEditorText.value("Додати підкатегорію", "Unterbereich hinzufügen"),
                          systemImage: "plus")
                }
            }
            Section(DirectoryEditorText.value("Статті", "Beiträge")) {
                ForEach($draft.topics) { $topic in
                    NavigationLink {
                        DirectoryTopicEditorView(topic: $topic, groups: draft.groups)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(topic.title.value(for: language))
                            if topic.isHidden {
                                Text(DirectoryEditorText.value("Приховано", "Ausgeblendet"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button {
                    guard let groupID = draft.groups.first?.id else { return }
                    draft.topics.append(.init(
                        id: "topic-" + UUID().uuidString.lowercased(),
                        groupID: groupID, order: draft.topics.count, isHidden: false,
                        title: .init(ukrainian: "", german: ""),
                        summary: .init(ukrainian: "", german: ""),
                        sections: [], sources: [], regionalSections: [:]
                    ))
                } label: {
                    Label(DirectoryEditorText.value("Додати статтю", "Beitrag hinzufügen"),
                          systemImage: "plus")
                }
            }
        }
        .directoryEditorChrome()
    }

    var body: some View {
        Group {
            if let focusTopicID, let index = draft.topics.firstIndex(where: { $0.id == focusTopicID }) {
                DirectoryTopicEditorView(topic: $draft.topics[index], groups: draft.groups)
            } else {
                categoryForm
            }
        }
        .navigationBarBackButtonHidden()
        .navigationTitle(focusTopicID.flatMap { id in
            draft.topics.first { $0.id == id }?.title.value(for: language)
        } ?? (draft.title.value(for: language).isEmpty
               ? DirectoryEditorText.value("Нова категорія", "Neuer Bereich")
               : draft.title.value(for: language)))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if hasUnsavedChanges { confirmation = .discard }
                    else { dismiss() }
                } label: {
                    Label(DirectoryEditorText.value("Назад", "Zurück"), systemImage: "chevron.left")
                }
                .disabled(isSaving)
            }
            if contentStore.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        confirmation = .publish
                    } label: {
                        if isSaving { ProgressView() }
                        else { Text(DirectoryEditorText.value("Опублікувати", "Veröffentlichen")) }
                    }
                    .disabled(isSaving || !hasUnsavedChanges)
                    .accessibilityIdentifier("directory.category.publish")
                }
            }
        }
        .confirmationDialog(
            confirmation == .publish
                ? DirectoryEditorText.value("Опублікувати для всіх читачів?", "Für alle Leser veröffentlichen?")
                : DirectoryEditorText.value("Вийти без збереження змін?", "Änderungen verwerfen?"),
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            )
        ) {
            if confirmation == .publish {
                Button(DirectoryEditorText.value("Опублікувати", "Veröffentlichen")) {
                    confirmation = nil
                    Task { await save() }
                }
            } else {
                Button(DirectoryEditorText.value("Відкинути зміни", "Änderungen verwerfen"), role: .destructive) {
                    confirmation = nil
                    dismiss()
                }
            }
        }
        .alert(DirectoryEditorText.value("Не вдалося зберегти", "Speichern fehlgeschlagen"),
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard let actorID = authState.user?.id else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await contentStore.save(draft, expectedRevision: expectedRevision, actorID: actorID)
            dismiss()
        } catch {
            let firebaseError = error as NSError
            if firebaseError.domain == FunctionsErrorDomain,
               firebaseError.code == FunctionsErrorCode.aborted.rawValue {
                errorMessage = DirectoryManagedValidation.Failure.conflict.localizedDescription
            } else if firebaseError.domain == FunctionsErrorDomain,
                      firebaseError.code == FunctionsErrorCode.permissionDenied.rawValue {
                errorMessage = DirectoryManagedValidation.Failure.permissionDenied.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct DirectoryGroupEditorView: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var group: DirectoryManagedGroup

    var body: some View {
        Form {
            DirectoryBilingualFields(title: DirectoryEditorText.value("Назва підкатегорії", "Name des Unterbereichs"),
                                     text: $group.title)
            Section {
                Stepper(value: $group.order, in: 0...1000) {
                    Text("\(DirectoryEditorText.value("Порядок", "Reihenfolge")): \(group.order)")
                }
                Toggle(DirectoryEditorText.value("Прибрати підкатегорію з довідника", "Unterbereich aus Ratgeber entfernen"),
                       isOn: $group.isHidden)
            }
        }
        .directoryEditorChrome()
        .navigationTitle(DirectoryEditorText.value("Підкатегорія", "Unterbereich"))
    }
}
