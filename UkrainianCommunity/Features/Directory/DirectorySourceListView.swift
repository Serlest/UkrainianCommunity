import SwiftUI

struct DirectorySourceListView: View {
    let sources: [DirectorySource]
    let language: AppLanguage
    let checkedOn: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DirectoryText(ukrainian: "Джерела та сервіси", german: "Quellen und Dienste").value(for: language))
                .font(.headline)
            ForEach(sources) { source in
                Link(destination: source.url) {
                    Label(source.name, systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text(DirectoryText(
                ukrainian: "Стан інформації: \(checkedOn).",
                german: "Informationsstand: \(checkedOn)."
            ).value(for: language))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}
