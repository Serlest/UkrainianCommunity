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
    private var isNewCategory: Bool { original.title.ukrainian.isEmpty && original.title.german.isEmpty }

    init(category: DirectoryManagedCategory?, expectedRevision: Int = 0, focusTopicID: String? = nil,
         newPlacement: DirectoryManagedCategory.Placement = .support, newOrder: Int = 0) {
        self.focusTopicID = focusTopicID
        _expectedRevision = State(initialValue: expectedRevision)
        let initial = category ?? DirectoryManagedCategory(
            id: "custom-" + UUID().uuidString.lowercased(),
            placement: newPlacement, order: newOrder, isHidden: false,
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
            Section {
                LabeledContent(DirectoryEditorText.value("Блок", "Block"),
                               value: placementTitle(draft.placement))
                if !isNewCategory {
                    Menu {
                        ForEach(DirectoryManagedCategory.Placement.allCases, id: \.self) { placement in
                            Button(placementTitle(placement)) {
                                guard placement != draft.placement else { return }
                                draft.placement = placement
                                draft.order = DirectoryEditorOrdering.nextOrder(
                                    in: placement, categories: contentStore.allManagedCategories)
                            }
                        }
                    } label: {
                        Label(DirectoryEditorText.value("Перемістити в інший блок", "In anderen Block verschieben"),
                              systemImage: "rectangle.2.swap")
                    }
                }
                NavigationLink {
                    DirectorySymbolPicker(selection: $draft.symbol)
                } label: {
                    Label(DirectoryEditorText.value("Іконка категорії", "Symbol des Bereichs"),
                          systemImage: draft.symbol)
                }
                Toggle(DirectoryEditorText.value("Прибрати категорію з довідника", "Bereich aus Ratgeber entfernen"),
                       isOn: $draft.isHidden)
            } header: {
                Text(DirectoryEditorText.value("На головному екрані", "Auf der Startseite"))
            } footer: {
                Text(isNewCategory
                     ? DirectoryEditorText.value("Після публікації категорія з’явиться наприкінці цього блока.",
                                                 "Nach der Veröffentlichung erscheint der Bereich am Ende dieses Blocks.")
                     : DirectoryEditorText.value("Переміщення в інший блок також опублікується разом із вашими змінами.",
                                                 "Der Wechsel in einen anderen Block wird mit Ihren Änderungen veröffentlicht."))
            }
            Section(DirectoryEditorText.value("Підкатегорії", "Unterbereiche")) {
                let ids = DirectoryEditorOrdering.groupIDs(draft.groups)
                ForEach(ids, id: \.self) { id in
                    if let index = draft.groups.firstIndex(where: { $0.id == id }),
                       let rank = ids.firstIndex(of: id) {
                        HStack {
                            NavigationLink {
                                DirectoryGroupEditorView(group: $draft.groups[index])
                            } label: {
                                Text(draft.groups[index].title.value(for: language).isEmpty
                                     ? DirectoryEditorText.value("Нова підкатегорія", "Neuer Unterbereich")
                                     : draft.groups[index].title.value(for: language))
                            }
                            DirectoryMoveMenu(canMoveUp: rank > 0, canMoveDown: rank < ids.count - 1,
                                              moveUp: { DirectoryEditorOrdering.moveGroup(&draft.groups, id: id, by: -1) },
                                              moveDown: { DirectoryEditorOrdering.moveGroup(&draft.groups, id: id, by: 1) })
                        }
                    }
                }
                Button {
                    draft.groups.append(.init(
                        id: "group-" + UUID().uuidString.lowercased(),
                        title: .init(ukrainian: "", german: ""),
                        order: min(1000, (draft.groups.map(\.order).max() ?? -1) + 1), isHidden: false
                    ))
                } label: {
                    Label(DirectoryEditorText.value("Додати підкатегорію", "Unterbereich hinzufügen"),
                          systemImage: "plus")
                }
            }
            ForEach(DirectoryEditorOrdering.groupIDs(draft.groups), id: \.self) { groupID in
                if let group = draft.groups.first(where: { $0.id == groupID }) {
                    Section(group.title.value(for: language).isEmpty
                            ? DirectoryEditorText.value("Нова підкатегорія", "Neuer Unterbereich")
                            : group.title.value(for: language)) {
                        let ids = DirectoryEditorOrdering.topicIDs(draft.topics, groupID: groupID)
                        ForEach(ids, id: \.self) { id in
                            if let index = draft.topics.firstIndex(where: { $0.id == id }),
                               let rank = ids.firstIndex(of: id) {
                                HStack {
                                    NavigationLink {
                                        DirectoryTopicEditorView(topic: $draft.topics[index], groups: draft.groups)
                                    } label: {
                                        VStack(alignment: .leading) {
                                            Text(draft.topics[index].title.value(for: language).isEmpty
                                                 ? DirectoryEditorText.value("Нова стаття", "Neuer Beitrag")
                                                 : draft.topics[index].title.value(for: language))
                                            if draft.topics[index].isHidden {
                                                Text(DirectoryEditorText.value("Приховано", "Ausgeblendet"))
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    DirectoryMoveMenu(canMoveUp: rank > 0, canMoveDown: rank < ids.count - 1,
                                                      moveUp: { DirectoryEditorOrdering.moveTopic(&draft.topics, id: id, groupID: groupID, by: -1) },
                                                      moveDown: { DirectoryEditorOrdering.moveTopic(&draft.topics, id: id, groupID: groupID, by: 1) })
                                }
                            }
                        }
                        Button {
                            let nextOrder = min(1000, (draft.topics.filter { $0.groupID == groupID }
                                .map(\.order).max() ?? -1) + 1)
                            draft.topics.append(.init(
                                id: "topic-" + UUID().uuidString.lowercased(),
                                groupID: groupID, order: nextOrder, isHidden: false,
                                title: .init(ukrainian: "", german: ""),
                                summary: .init(ukrainian: "", german: ""),
                                sections: [], sources: [], regionalSections: [:]
                            ))
                        } label: {
                            Label(DirectoryEditorText.value("Додати статтю сюди", "Beitrag hier hinzufügen"),
                                  systemImage: "plus")
                        }
                    }
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
            Button(DirectoryEditorText.value("Гаразд", "OK")) { errorMessage = nil }
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

    private func placementTitle(_ placement: DirectoryManagedCategory.Placement) -> String {
        switch placement {
        case .start: DirectoryStrings.startHeading
        case .life: DirectoryStrings.lifeHeading
        case .support: DirectoryStrings.supportHeading
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
                Toggle(DirectoryEditorText.value("Прибрати підкатегорію з довідника", "Unterbereich aus Ratgeber entfernen"),
                       isOn: $group.isHidden)
            }
        }
        .directoryEditorChrome()
        .navigationTitle(DirectoryEditorText.value("Підкатегорія", "Unterbereich"))
    }
}
