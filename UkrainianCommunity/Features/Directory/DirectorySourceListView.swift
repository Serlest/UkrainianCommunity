import SwiftUI

struct DirectorySourceListView: View {
    let sources: [DirectorySource]
    let language: AppLanguage
    let checkedOn: String?
    var isPublicationDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !sources.isEmpty {
                Text(DirectoryText(ukrainian: "Джерела та сервіси", german: "Quellen und Dienste").value(for: language))
                    .font(.headline)
                ForEach(sources) { source in
                    Link(destination: source.url) {
                        Label(source.name, systemImage: "arrow.up.right.square")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Text(dateCaption.value(for: language))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            if isPublicationDate {
                Text(DirectoryText(
                    ukrainian: "Дата публікації не означає повторну перевірку посилань. Перед дією звірте актуальні умови на сайті джерела.",
                    german: "Das Veröffentlichungsdatum bestätigt keine erneute Prüfung der Links. Prüfen Sie aktuelle Bedingungen vorab auf der Quellseite."
                ).value(for: language))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var dateCaption: DirectoryText {
        if isPublicationDate {
            guard let checkedOn else {
                return DirectoryText(ukrainian: "Дата оновлення категорії недоступна.",
                                     german: "Das Aktualisierungsdatum des Bereichs ist nicht verfügbar.")
            }
            return DirectoryText(ukrainian: "Категорію оновлено: \(checkedOn).",
                                 german: "Bereich aktualisiert: \(checkedOn).")
        }
        return DirectoryText(ukrainian: "Стан інформації: \(checkedOn ?? "—").",
                             german: "Informationsstand: \(checkedOn ?? "—").")
    }
}
