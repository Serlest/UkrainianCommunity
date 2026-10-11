import SwiftUI

struct DirectoryManagementView: View {
    @EnvironmentObject private var contentStore: DirectoryContentStore
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        List {
            Section {
                Text(DirectoryEditorText.value(
                    "Тут можна змінювати категорії, підкатегорії, статті та джерела. Збереження одразу публікує зміни для читачів.",
                    "Hier bearbeiten Sie Bereiche, Unterbereiche, Beiträge und Quellen. Speichern veröffentlicht die Änderungen sofort."
                ))
                .font(.subheadline)
            }
            ForEach(DirectoryManagedCategory.Placement.allCases, id: \.self) { placement in
                Section(placementTitle(placement)) {
                    ForEach(contentStore.allManagedCategories.filter { $0.placement == placement }) { category in
                        NavigationLink(value: DirectoryRoute.edit(category.id)) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(category.title.value(for: language))
                                    if category.isHidden {
                                        Text(DirectoryEditorText.value("Приховано", "Ausgeblendet"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: category.symbol)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackgroundView())
        .navigationTitle(DirectoryEditorText.value("Керування довідником", "Ratgeber verwalten"))
        .toolbar {
            NavigationLink(value: DirectoryRoute.create) {
                Label(DirectoryEditorText.value("Додати категорію", "Bereich hinzufügen"),
                      systemImage: "plus")
            }
            .accessibilityIdentifier("directory.category.add")
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
