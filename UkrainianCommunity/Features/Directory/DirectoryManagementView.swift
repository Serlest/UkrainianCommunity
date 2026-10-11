import SwiftUI

struct DirectoryManagementView: View {
    @EnvironmentObject private var contentStore: DirectoryContentStore
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }

    var body: some View {
        let categories = contentStore.allManagedCategories
        List {
            Section {
                Text(DirectoryEditorText.value(
                    "Оберіть категорію для редагування або додайте нову в потрібний блок. Публікація робить зміни видимими для читачів.",
                    "Wählen Sie einen Bereich zum Bearbeiten oder fügen Sie ihn im passenden Block hinzu. Nach der Veröffentlichung sind Änderungen für Leser sichtbar."
                ))
                .font(.subheadline)
            }
            ForEach(DirectoryManagedCategory.Placement.allCases, id: \.self) { placement in
                Section(placementTitle(placement)) {
                    ForEach(categories.filter { $0.placement == placement }) { category in
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
                    if contentStore.canEdit {
                        NavigationLink(value: DirectoryRoute.create(placement)) {
                            Label(DirectoryEditorText.value("Додати категорію в цей блок", "Bereich in diesem Block hinzufügen"),
                                  systemImage: "plus.circle.fill")
                        }
                        .accessibilityIdentifier("directory.category.add.\(placement.rawValue)")
                    }
                }
            }
        }
        .directoryEditorChrome()
        .navigationTitle(DirectoryEditorText.value("Керування довідником", "Ratgeber verwalten"))
    }

    private func placementTitle(_ placement: DirectoryManagedCategory.Placement) -> String {
        switch placement {
        case .start: DirectoryStrings.startHeading
        case .life: DirectoryStrings.lifeHeading
        case .support: DirectoryStrings.supportHeading
        }
    }
}
