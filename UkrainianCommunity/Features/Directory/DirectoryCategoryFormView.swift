import SwiftUI

struct DirectoryCategoryFormView: View {
    @EnvironmentObject private var contentStore: DirectoryContentStore
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var draft: DirectoryManagedCategory
    let isNewCategory: Bool
    let expectedRevision: Int
    let isSaving: Bool
    let onDeleteCategory: () -> Void
    let onDeleteGroup: (String) -> Void
    let onDeleteTopic: (String) -> Void

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        Form {
            Section {
                Text(DirectoryEditorText.value(
                    "Зміни з’являться для всіх після публікації. Приховування прибирає матеріал з довідника, але зберігає його для відновлення.",
                    "Änderungen erscheinen nach Veröffentlichung für alle. Ausblenden entfernt Inhalte aus dem Ratgeber, bewahrt sie aber zur Wiederherstellung."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if isNewCategory {
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
                Toggle(DirectoryEditorText.value("Тимчасово приховати категорію", "Bereich vorübergehend ausblenden"),
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
                            DirectoryMoveMenu(
                                canMoveUp: rank > 0, canMoveDown: rank < ids.count - 1,
                                moveUp: { DirectoryEditorOrdering.moveGroup(&draft.groups, id: id, by: -1) },
                                moveDown: { DirectoryEditorOrdering.moveGroup(&draft.groups, id: id, by: 1) },
                                onDelete: DirectoryEditorDeletion.canDeleteGroup(id, from: draft)
                                    ? { onDeleteGroup(id) } : nil
                            )
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
                                    DirectoryMoveMenu(
                                        canMoveUp: rank > 0, canMoveDown: rank < ids.count - 1,
                                        moveUp: { DirectoryEditorOrdering.moveTopic(&draft.topics, id: id, groupID: groupID, by: -1) },
                                        moveDown: { DirectoryEditorOrdering.moveTopic(&draft.topics, id: id, groupID: groupID, by: 1) },
                                        onDelete: DirectoryEditorDeletion.canDeleteTopic(id, from: draft)
                                            ? { onDeleteTopic(id) } : nil
                                    )
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
            if !isNewCategory && draft.id.hasPrefix("custom-") && expectedRevision > 0 {
                Section {
                    Button(role: .destructive) { onDeleteCategory() } label: {
                        Label(DirectoryEditorText.value("Видалити категорію", "Bereich löschen"),
                              systemImage: "trash")
                    }
                    .disabled(isSaving)
                } footer: {
                    Text(DirectoryEditorText.value(
                        "Категорія зникне з довідника й редактора. Історія публікацій збережеться для перевірки.",
                        "Der Bereich verschwindet aus Ratgeber und Redaktion. Die Veröffentlichungshistorie bleibt zur Prüfung erhalten."
                    ))
                }
            }
        }
        .directoryEditorChrome()
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
                Toggle(DirectoryEditorText.value("Тимчасово приховати підкатегорію", "Unterbereich vorübergehend ausblenden"),
                       isOn: $group.isHidden)
            }
        }
        .directoryEditorChrome()
        .navigationTitle(DirectoryEditorText.value("Підкатегорія", "Unterbereich"))
    }
}
