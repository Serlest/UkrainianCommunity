import SwiftUI

struct DirectorySymbolPicker: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var query = ""

    private struct Option: Identifiable {
        let id: String
        let title: DirectoryText
    }

    private static let options: [Option] = [
        .init(id: "books.vertical.fill", title: .init(ukrainian: "Довідник", german: "Ratgeber")),
        .init(id: "shield.lefthalf.filled", title: .init(ukrainian: "Безпека", german: "Sicherheit")),
        .init(id: "figure.walk.arrival", title: .init(ukrainian: "Прибуття", german: "Ankunft")),
        .init(id: "checklist", title: .init(ukrainian: "Список кроків", german: "Checkliste")),
        .init(id: "house.lodge.fill", title: .init(ukrainian: "Житло", german: "Wohnen")),
        .init(id: "person.crop.rectangle", title: .init(ukrainian: "Посвідчення", german: "Ausweis")),
        .init(id: "doc.text.fill", title: .init(ukrainian: "Документи", german: "Dokumente")),
        .init(id: "globe.europe.africa.fill", title: .init(ukrainian: "Країни", german: "Länder")),
        .init(id: "cross.case.fill", title: .init(ukrainian: "Здоров’я", german: "Gesundheit")),
        .init(id: "brain.head.profile", title: .init(ukrainian: "Психічне здоров’я", german: "Psychische Gesundheit")),
        .init(id: "checkmark.shield.fill", title: .init(ukrainian: "Страхування", german: "Versicherung")),
        .init(id: "briefcase.fill", title: .init(ukrainian: "Робота", german: "Arbeit")),
        .init(id: "graduationcap.fill", title: .init(ukrainian: "Навчання", german: "Bildung")),
        .init(id: "person.2.fill", title: .init(ukrainian: "Родина", german: "Familie")),
        .init(id: "tram.fill", title: .init(ukrainian: "Транспорт", german: "Verkehr")),
        .init(id: "eurosign.circle.fill", title: .init(ukrainian: "Фінанси", german: "Finanzen")),
        .init(id: "heart.text.square.fill", title: .init(ukrainian: "Допомога", german: "Hilfe")),
        .init(id: "building.columns.fill", title: .init(ukrainian: "Установа", german: "Behörde")),
        .init(id: "wifi", title: .init(ukrainian: "Зв’язок", german: "Verbindung")),
        .init(id: "desktopcomputer", title: .init(ukrainian: "Онлайн-послуги", german: "Online-Dienste")),
        .init(id: "person.3.fill", title: .init(ukrainian: "Громада", german: "Gemeinschaft")),
        .init(id: "figure.run", title: .init(ukrainian: "Дозвілля", german: "Freizeit")),
        .init(id: "figure.roll", title: .init(ukrainian: "Доступність", german: "Barrierefreiheit")),
        .init(id: "figure.walk", title: .init(ukrainian: "Догляд", german: "Betreuung")),
        .init(id: "figure.walk.motion", title: .init(ukrainian: "Літнім людям", german: "Senioren")),
        .init(id: "info.circle.fill", title: .init(ukrainian: "Інформація", german: "Information")),
        .init(id: "phone.fill", title: .init(ukrainian: "Телефон", german: "Telefon")),
        .init(id: "map.fill", title: .init(ukrainian: "Мапа", german: "Karte")),
        .init(id: "exclamationmark.triangle.fill", title: .init(ukrainian: "Попередження", german: "Warnung")),
        .init(id: "text.book.closed.fill", title: .init(ukrainian: "Пояснення", german: "Erklärung")),
    ]

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var visibleOptions: [Option] {
        let filtered = Self.options.filter {
            query.isEmpty || $0.title.value(for: language).localizedStandardContains(query)
        }
        return filtered
    }

    var body: some View {
        List {
            if !Self.options.contains(where: { $0.id == selection }) {
                row(symbol: selection,
                    title: DirectoryEditorText.value("Поточна іконка", "Aktuelles Symbol"))
            }
            ForEach(visibleOptions) { option in
                row(symbol: option.id, title: option.title.value(for: language))
            }
        }
        .directoryEditorChrome()
        .navigationTitle(DirectoryEditorText.value("Оберіть іконку", "Symbol auswählen"))
        .searchable(text: $query, prompt: DirectoryEditorText.value("Пошук іконки", "Symbol suchen"))
    }

    private func row(symbol: String, title: String) -> some View {
        Button {
            selection = symbol
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 12))
                Text(title).foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if selection == symbol {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
