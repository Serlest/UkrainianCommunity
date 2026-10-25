import SwiftUI

struct DirectoryTopicEditorView: View {
    private enum SectionAlert {
        case delete(String)
        case unavailable
    }
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var topic: DirectoryManagedTopic
    let groups: [DirectoryManagedGroup]
    @State private var sectionAlert: SectionAlert?
    @State private var showAddSection = false
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var sectionAlertTitle: String {
        if case .unavailable? = sectionAlert {
            return DirectoryEditorText.value("Видалення недоступне", "Löschen nicht möglich")
        }
        return DirectoryEditorText.value("Видалити інформаційний блок?", "Informationsabschnitt löschen?")
    }

    var body: some View {
        Form {
            DirectoryTranslationControls(inputs: DirectoryTranslationInput.article($topic))
            DirectoryBilingualFields(field: .articleTitle,
                                     text: $topic.title)
            DirectoryBilingualFields(field: .articleSummary,
                                     text: $topic.summary, multiline: true, required: !topic.isHidden)
            Section(DirectoryEditorText.value("У довіднику", "Im Ratgeber")) {
                Picker(DirectoryEditorText.value("Підкатегорія", "Unterbereich"),
                       selection: $topic.groupID) {
                    ForEach(groups) { group in
                        Text(group.title.value(for: language)).tag(group.id)
                    }
                }
                .accessibilityIdentifier("directory.topic.group")
                Toggle(DirectoryEditorText.value("Тимчасово приховати статтю", "Beitrag vorübergehend ausblenden"),
                       isOn: $topic.isHidden)
            }
            Section(DirectoryEditorText.value("Блоки інформації", "Informationsabschnitte")) {
                let ids = DirectoryEditorOrdering.sectionIDs(topic.sections)
                ForEach(ids, id: \.self) { id in
                    if let index = topic.sections.firstIndex(where: { $0.id == id }),
                       let rank = ids.firstIndex(of: id) {
                        HStack {
                            NavigationLink {
                                DirectorySectionEditorView(section: $topic.sections[index])
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(topic.sections[index].title.value(for: language).isEmpty
                                         ? DirectoryEditorText.value("Новий блок", "Neuer Abschnitt")
                                         : topic.sections[index].title.value(for: language))
                                    if topic.sections[index].isHidden {
                                        Text(DirectoryEditorText.value("Приховано", "Ausgeblendet"))
                                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("directory.section.edit.\(id)")
                            DirectoryMoveMenu(
                                canMoveUp: rank > 0, canMoveDown: rank < ids.count - 1,
                                moveUp: { DirectoryEditorOrdering.moveSection(&topic.sections, id: id, by: -1) },
                                moveDown: { DirectoryEditorOrdering.moveSection(&topic.sections, id: id, by: 1) }
                            )
                            Button(role: .destructive) {
                                if DirectoryEditorDeletion.canDeleteSection(id, from: topic) {
                                    sectionAlert = .delete(id)
                                } else {
                                    sectionAlert = .unavailable
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel(DirectoryEditorText.value("Видалити блок", "Abschnitt löschen"))
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("directory.section.delete.\(id)")
                        }
                    }
                }
                Button {
                    showAddSection = true
                } label: {
                    Label(DirectoryEditorText.value("Додати блок", "Abschnitt hinzufügen"),
                          systemImage: "plus")
                }
            }
            Section(DirectoryEditorText.value("Федеральні землі", "Bundesländer")) {
                ForEach(AustrianFederalState.allCases) { state in
                    NavigationLink {
                        DirectoryRegionEditorView(topic: $topic, state: state)
                    } label: {
                        HStack {
                            Text(state.displayName)
                            Spacer()
                            Text("\(topic.regionalSections[state.rawValue]?.filter { !$0.isHidden }.count ?? 0)")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .accessibilityIdentifier("directory.region.edit.\(state.rawValue)")
                }
            }
            DirectorySourcesEditorView(sources: $topic.sources)
        }
        .directoryEditorChrome()
        .navigationTitle(DirectoryEditorText.value("Стаття", "Beitrag"))
        .sheet(isPresented: $showAddSection) {
            DirectoryAddSectionView(order: min(1000, (topic.sections.map(\.order).max() ?? -1) + 1)) {
                topic.sections.append($0)
            }
        }
        .alert(
            sectionAlertTitle,
            isPresented: Binding(get: { sectionAlert != nil },
                                 set: { if !$0 { sectionAlert = nil } }),
            presenting: sectionAlert
        ) { action in
            switch action {
            case let .delete(id):
                Button(DirectoryEditorText.value("Видалити блок", "Abschnitt löschen"), role: .destructive) {
                    DirectoryEditorDeletion.deleteSection(id, from: &topic)
                    sectionAlert = nil
                }
                .accessibilityIdentifier("directory.section.confirmDelete")
                Button(DirectoryEditorText.value("Скасувати", "Abbrechen"), role: .cancel) {
                    sectionAlert = nil
                }
                .accessibilityIdentifier("directory.section.cancelDelete")
            case .unavailable:
                Button(DirectoryEditorText.value("Гаразд", "OK")) { sectionAlert = nil }
            }
        } message: { action in
            switch action {
            case let .delete(id):
                Text(DirectoryEditorText.value(
                    "Блок «\(topic.sections.first { $0.id == id }?.title.value(for: language) ?? "")» буде вилучено з чернетки. Щоб зберегти зміну для читачів, опублікуйте категорію.",
                    "Der Abschnitt „\(topic.sections.first { $0.id == id }?.title.value(for: language) ?? "")“ wird aus dem Entwurf entfernt. Veröffentlichen Sie den Bereich, um die Änderung für Leser zu speichern."
                ))
            case .unavailable:
                Text(DirectoryEditorText.value(
                    "Це останній видимий блок. Додайте новий перед видаленням цього.",
                    "Dies ist der letzte sichtbare Abschnitt. Legen Sie zuerst einen neuen an."
                ))
            }
        }
    }
}

private struct DirectorySourcesEditorView: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var sources: [DirectoryManagedSource]
    @State private var rowIDs: [UUID]

    init(sources: Binding<[DirectoryManagedSource]>) {
        _sources = sources
        _rowIDs = State(initialValue: sources.wrappedValue.map { _ in UUID() })
    }

    var body: some View {
        Section {
            ForEach(Array(rowIDs.enumerated()), id: \.element) { index, _ in
                HStack(alignment: .top) {
                    DirectorySourceFields(source: $sources[index])
                    Button(role: .destructive) {
                        sources.remove(at: index)
                        rowIDs.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(DirectoryEditorText.value("Видалити джерело", "Quelle löschen"))
                    .buttonStyle(.borderless)
                }
            }
            Button {
                sources.append(.init(name: "", url: ""))
                rowIDs.append(UUID())
            } label: {
                Label(DirectoryEditorText.value("Додати джерело статті", "Beitragsquelle hinzufügen"),
                      systemImage: "plus")
            }
        } header: {
            Text(DirectoryEditorText.value("Додаткові джерела", "Weitere Quellen"))
        } footer: {
            Text(DirectoryEditorText.value(
                "Для кожного опублікованого блока потрібне HTTPS-джерело: у самому блоці або тут.",
                "Jeder veröffentlichte Abschnitt benötigt eine HTTPS-Quelle: im Abschnitt oder hier."
            ))
        }
    }
}

private struct DirectoryRegionEditorView: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var topic: DirectoryManagedTopic
    let state: AustrianFederalState
    @State private var pendingSectionID: String?
    @State private var showAddSection = false

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var sections: Binding<[DirectoryManagedSection]> {
        Binding(
            get: { topic.regionalSections[state.rawValue] ?? [] },
            set: { topic.regionalSections[state.rawValue] = $0 }
        )
    }

    var body: some View {
        List {
            Section {
                Text(DirectoryEditorText.value(
                    "Ці блоки бачать читачі, які вибрали цю федеральну землю. Прихований блок можна відновити пізніше.",
                    "Diese Abschnitte sehen Leser, die dieses Bundesland gewählt haben. Ausgeblendete Abschnitte können später wiederhergestellt werden."
                ))
                .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
            }
            Section(DirectoryEditorText.value("Регіональні блоки", "Regionale Abschnitte")) {
                let ids = DirectoryEditorOrdering.sectionIDs(sections.wrappedValue)
                ForEach(ids, id: \.self) { id in
                    if let index = sections.wrappedValue.firstIndex(where: { $0.id == id }),
                       let rank = ids.firstIndex(of: id) {
                        HStack {
                            NavigationLink {
                                DirectorySectionEditorView(section: sections[index])
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(sections.wrappedValue[index].title.value(for: language).isEmpty
                                         ? DirectoryEditorText.value("Новий блок", "Neuer Abschnitt")
                                         : sections.wrappedValue[index].title.value(for: language))
                                    if sections.wrappedValue[index].isHidden {
                                        Text(DirectoryEditorText.value("Приховано", "Ausgeblendet"))
                                            .font(.caption).foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("directory.region.section.edit.\(id)")
                            DirectoryMoveMenu(canMoveUp: rank > 0, canMoveDown: rank < ids.count - 1,
                                              moveUp: { moveRegionSection(id, by: -1) },
                                              moveDown: { moveRegionSection(id, by: 1) })
                            Button(role: .destructive) { pendingSectionID = id } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel(DirectoryEditorText.value("Видалити блок", "Abschnitt löschen"))
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("directory.region.section.delete.\(id)")
                        }
                    }
                }
                Button {
                    showAddSection = true
                } label: {
                    Label(DirectoryEditorText.value("Додати блок", "Abschnitt hinzufügen"),
                          systemImage: "plus")
                }
            }
        }
        .directoryEditorChrome()
        .navigationTitle(state.displayName)
        .sheet(isPresented: $showAddSection) {
            DirectoryAddSectionView(order: min(1000, (sections.wrappedValue.map(\.order).max() ?? -1) + 1)) {
                var current = sections.wrappedValue
                current.append($0)
                sections.wrappedValue = current
            }
        }
        .alert(
            DirectoryEditorText.value("Видалити регіональний блок?", "Regionalen Abschnitt löschen?"),
            isPresented: Binding(get: { pendingSectionID != nil },
                                 set: { if !$0 { pendingSectionID = nil } }),
            presenting: pendingSectionID
        ) { id in
            Button(DirectoryEditorText.value("Видалити блок", "Abschnitt löschen"), role: .destructive) {
                DirectoryEditorDeletion.deleteRegionalSection(id, state: state, from: &topic)
                pendingSectionID = nil
            }
            .accessibilityIdentifier("directory.region.section.confirmDelete")
            Button(DirectoryEditorText.value("Скасувати", "Abbrechen"), role: .cancel) {
                pendingSectionID = nil
            }
            .accessibilityIdentifier("directory.region.section.cancelDelete")
        } message: { _ in
            Text(DirectoryEditorText.value(
                "Блок буде вилучено з чернетки цієї федеральної землі. Щоб зберегти зміну для читачів, опублікуйте категорію.",
                "Der Abschnitt wird aus dem Entwurf dieses Bundeslands entfernt. Veröffentlichen Sie den Bereich, um die Änderung für Leser zu speichern."
            ))
        }
    }

    private func moveRegionSection(_ id: String, by offset: Int) {
        var current = sections.wrappedValue
        DirectoryEditorOrdering.moveSection(&current, id: id, by: offset)
        sections.wrappedValue = current
    }
}
