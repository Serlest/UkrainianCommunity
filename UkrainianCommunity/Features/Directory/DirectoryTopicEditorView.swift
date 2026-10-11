import SwiftUI

struct DirectoryTopicEditorView: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var topic: DirectoryManagedTopic
    let groups: [DirectoryManagedGroup]
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        Form {
            DirectoryBilingualFields(title: DirectoryEditorText.value("Назва статті", "Beitragstitel"),
                                     text: $topic.title)
            DirectoryBilingualFields(title: DirectoryEditorText.value("Вступ", "Einleitung"),
                                     text: $topic.summary, multiline: true)
            Section(DirectoryEditorText.value("Розміщення", "Platzierung")) {
                Picker(DirectoryEditorText.value("Підкатегорія", "Unterbereich"),
                       selection: $topic.groupID) {
                    ForEach(groups) { group in
                        Text(group.title.value(for: language)).tag(group.id)
                    }
                }
                Stepper(value: $topic.order, in: 0...1000) {
                    Text("\(DirectoryEditorText.value("Порядок", "Reihenfolge")): \(topic.order)")
                }
                Toggle(DirectoryEditorText.value("Прибрати статтю з довідника", "Beitrag aus Ratgeber entfernen"),
                       isOn: $topic.isHidden)
            }
            Section(DirectoryEditorText.value("Блоки інформації", "Informationsabschnitte")) {
                ForEach($topic.sections) { $section in
                    NavigationLink {
                        DirectorySectionEditorView(section: $section)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(section.title.value(for: language))
                            if section.isHidden {
                                Text(DirectoryEditorText.value("Приховано", "Ausgeblendet"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button {
                    topic.sections.append(.init(
                        id: "section-" + UUID().uuidString.lowercased(),
                        order: topic.sections.count, isHidden: false,
                        title: .init(ukrainian: "", german: ""),
                        body: .init(ukrainian: "", german: ""),
                        symbol: "text.book.closed.fill",
                        phoneNumber: nil, source: nil, contacts: []
                    ))
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
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            DirectorySourcesEditorView(sources: $topic.sources)
        }
        .directoryEditorChrome()
        .navigationTitle(DirectoryEditorText.value("Стаття", "Beitrag"))
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
                DirectorySourceFields(source: $sources[index])
            }
            .onDelete { offsets in
                sources.remove(atOffsets: offsets)
                rowIDs.remove(atOffsets: offsets)
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
                .font(.subheadline).foregroundStyle(.secondary)
            }
            Section(DirectoryEditorText.value("Регіональні блоки", "Regionale Abschnitte")) {
                ForEach(sections) { $section in
                    NavigationLink {
                        DirectorySectionEditorView(section: $section)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(section.title.value(for: language))
                            if section.isHidden {
                                Text(DirectoryEditorText.value("Приховано", "Ausgeblendet"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button {
                    var current = sections.wrappedValue
                    current.append(.init(
                        id: "region-" + UUID().uuidString.lowercased(), order: current.count,
                        isHidden: false, title: .init(ukrainian: "", german: ""),
                        body: .init(ukrainian: "", german: ""), symbol: "building.columns",
                        phoneNumber: nil, source: nil, contacts: []
                    ))
                    sections.wrappedValue = current
                } label: {
                    Label(DirectoryEditorText.value("Додати блок", "Abschnitt hinzufügen"),
                          systemImage: "plus")
                }
            }
        }
        .directoryEditorChrome()
        .navigationTitle(state.displayName)
    }
}

struct DirectorySourceFields: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var source: DirectoryManagedSource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(DirectoryEditorText.value("Назва джерела", "Name der Quelle"),
                      text: $source.name)
            TextField("https://", text: $source.url)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
        }
    }
}
