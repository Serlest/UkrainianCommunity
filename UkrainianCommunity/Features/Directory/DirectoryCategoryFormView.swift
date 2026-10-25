import SwiftUI

struct DirectoryCategoryFormView: View {
    private enum Addition: Identifiable {
        case group
        case topic(String)

        var id: String {
            switch self {
            case .group: "group"
            case let .topic(groupID): "topic-\(groupID)"
            }
        }
    }
    @EnvironmentObject private var contentStore: DirectoryContentStore
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var draft: DirectoryManagedCategory
    let hasUnsavedChanges: Bool
    let isSaving: Bool
    let onDeleteCategory: () -> Void
    let onDeleteGroup: (String) -> Void
    let onDeleteTopic: (String) -> Void
    @State private var deletionLimitMessage: String?
    @State private var addition: Addition?

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        Form {
            DirectoryTranslationControls(inputs: [.init(.categoryTitle, $draft.title), .init(.categorySummary, $draft.summary)])
            Section {
                Label(hasUnsavedChanges
                      ? DirectoryEditorText.value("Зміни ще не опубліковані", "Änderungen noch nicht veröffentlicht")
                      : DirectoryEditorText.value("Зміни з’являться після публікації", "Änderungen erscheinen nach Veröffentlichung"),
                      systemImage: hasUnsavedChanges ? "pencil.circle" : "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                Toggle(DirectoryEditorText.value("Прибрати з довідника", "Aus dem Ratgeber entfernen"),
                       isOn: $draft.isHidden)
                if draft.id.hasPrefix("custom-") {
                    Button(role: .destructive, action: onDeleteCategory) {
                        Label(DirectoryEditorText.value("Видалити категорію назавжди", "Bereich endgültig löschen"),
                              systemImage: "trash")
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("directory.category.delete")
                }
            } footer: {
                Text(draft.id.hasPrefix("custom-")
                     ? DirectoryEditorText.value(
                        "Прибрати можна тимчасово; видалення одразу прибере категорію з усіма статтями.",
                        "Entfernen ist vorübergehend; Löschen entfernt den Bereich mit allen Beiträgen sofort."
                     )
                     : DirectoryEditorText.value(
                        "Вбудовану категорію можна прибрати й згодом відновити. Зміну потрібно опублікувати.",
                        "Ein integrierter Bereich kann entfernt und später wiederhergestellt werden. Veröffentlichen Sie die Änderung."
                     ))
            }
            DirectoryBilingualFields(field: .categoryTitle,
                                     text: $draft.title)
            DirectoryBilingualFields(field: .categorySummary,
                                     text: $draft.summary)
            Section {
                Picker(DirectoryEditorText.value("Розділ довідника", "Ratgeber-Rubrik"),
                       selection: $draft.placement) {
                    ForEach(DirectoryManagedCategory.Placement.allCases, id: \.self) { placement in
                        Text(placementTitle(placement)).tag(placement)
                    }
                }
                .accessibilityIdentifier("directory.category.placement")
                .onChange(of: draft.placement) { _, newValue in
                    draft.order = DirectoryEditorOrdering.nextOrder(
                        in: newValue, categories: contentStore.allManagedCategories)
                }
                NavigationLink {
                    DirectorySymbolPicker(selection: $draft.symbol)
                } label: {
                    Label(DirectoryEditorText.value("Іконка категорії", "Symbol des Bereichs"),
                          systemImage: draft.symbol)
                }
                .accessibilityIdentifier("directory.category.symbol")
            } header: {
                Text(DirectoryEditorText.value("На головному екрані", "Auf der Startseite"))
            }
            ForEach(DirectoryEditorOrdering.groupIDs(draft.groups), id: \.self) { groupID in
                if let groupIndex = draft.groups.firstIndex(where: { $0.id == groupID }) {
                    Section {
                        HStack {
                            NavigationLink {
                                DirectoryGroupEditorView(group: $draft.groups[groupIndex])
                            } label: {
                                Label(DirectoryEditorText.value("Назва та видимість", "Name und Sichtbarkeit"),
                                      systemImage: "square.and.pencil")
                            }
                            .accessibilityIdentifier("directory.group.edit.\(groupID)")
                            if draft.groups.count > 1,
                               let rank = DirectoryEditorOrdering.groupIDs(draft.groups).firstIndex(of: groupID) {
                                DirectoryMoveMenu(
                                    canMoveUp: rank > 0, canMoveDown: rank < draft.groups.count - 1,
                                    moveUp: { DirectoryEditorOrdering.moveGroup(&draft.groups, id: groupID, by: -1) },
                                    moveDown: { DirectoryEditorOrdering.moveGroup(&draft.groups, id: groupID, by: 1) }
                                )
                                .accessibilityIdentifier("directory.group.move." + groupID)
                            }
                            Button(role: .destructive) {
                                if DirectoryEditorDeletion.canDeleteGroup(groupID, from: draft) {
                                    onDeleteGroup(groupID)
                                } else {
                                    deletionLimitMessage = DirectoryEditorText.value(
                                        "Це остання підкатегорія зі статтями. Спершу додайте іншу або приберіть усю категорію з довідника.",
                                        "Dies ist der letzte Unterbereich mit Beiträgen. Legen Sie zuerst einen weiteren an oder entfernen Sie den gesamten Bereich aus dem Ratgeber."
                                    )
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel(DirectoryEditorText.value("Видалити підкатегорію", "Unterbereich löschen"))
                            .buttonStyle(.borderless)
                        }
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
                                                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
                                            }
                                        }
                                    }
                                    .accessibilityIdentifier("directory.topic.edit.\(id)")
                                    if ids.count > 1 {
                                        DirectoryMoveMenu(
                                            canMoveUp: rank > 0, canMoveDown: rank < ids.count - 1,
                                            moveUp: { DirectoryEditorOrdering.moveTopic(&draft.topics, id: id, groupID: groupID, by: -1) },
                                            moveDown: { DirectoryEditorOrdering.moveTopic(&draft.topics, id: id, groupID: groupID, by: 1) }
                                        )
                                    }
                                    Button(role: .destructive) {
                                        if DirectoryEditorDeletion.canDeleteTopic(id, from: draft) {
                                            onDeleteTopic(id)
                                        } else {
                                            deletionLimitMessage = DirectoryEditorText.value(
                                                "Це остання видима стаття. Спершу додайте іншу або приберіть усю категорію з довідника.",
                                                "Dies ist der letzte sichtbare Beitrag. Legen Sie zuerst einen weiteren an oder entfernen Sie den gesamten Bereich aus dem Ratgeber."
                                            )
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel(DirectoryEditorText.value("Видалити статтю", "Beitrag löschen"))
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        Button {
                            addition = .topic(groupID)
                        } label: {
                            Label(DirectoryEditorText.value("Додати статтю сюди", "Beitrag hier hinzufügen"),
                                  systemImage: "plus")
                        }
                    } header: {
                        Text(draft.groups[groupIndex].title.value(for: language).isEmpty
                             ? DirectoryEditorText.value("Нова підкатегорія", "Neuer Unterbereich")
                             : draft.groups[groupIndex].title.value(for: language))
                    }
                }
            }
            Section {
                Button {
                    addition = .group
                } label: {
                    Label(DirectoryEditorText.value("Додати підкатегорію", "Unterbereich hinzufügen"),
                          systemImage: "plus")
                }
            }
        }
        .directoryEditorChrome()
        .sheet(item: $addition) { item in
            switch item {
            case .group:
                DirectoryAddGroupView { title in
                    draft.groups.append(.init(
                        id: "group-" + UUID().uuidString.lowercased(), title: title,
                        order: min(1000, (draft.groups.map(\.order).max() ?? -1) + 1), isHidden: false
                    ))
                }
            case let .topic(groupID):
                DirectoryAddTopicView(
                    groupID: groupID,
                    order: min(1000, (draft.topics.filter { $0.groupID == groupID }
                        .map(\.order).max() ?? -1) + 1)
                ) { topic in
                    draft.topics.append(topic)
                }
            }
        }
        .alert(DirectoryEditorText.value("Видалення недоступне", "Löschen nicht möglich"),
               isPresented: Binding(get: { deletionLimitMessage != nil },
                                    set: { if !$0 { deletionLimitMessage = nil } })) {
            Button(DirectoryEditorText.value("Гаразд", "OK")) { deletionLimitMessage = nil }
        } message: {
            Text(deletionLimitMessage ?? "")
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
            DirectoryTranslationControls(inputs: [.init(.groupTitle, $group.title)])
            DirectoryBilingualFields(field: .groupTitle,
                                     text: $group.title)
            Section {
                Toggle(DirectoryEditorText.value("Тимчасово приховати підкатегорію", "Unterbereich vorübergehend ausblenden"),
                       isOn: $group.isHidden)
                .accessibilityIdentifier("directory.group.hidden")
            }
        }
        .directoryEditorChrome()
        .navigationTitle(DirectoryEditorText.value("Підкатегорія", "Unterbereich"))
    }
}
