import SwiftUI

struct DirectorySourceListView: View {
    let sources: [DirectorySource]
    let language: AppLanguage
    let checkedOn: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DirectoryText(ukrainian: "Офіційні джерела", german: "Offizielle Quellen").value(for: language))
                .font(.headline)
            ForEach(sources) { source in
                Link(destination: source.url) {
                    Label(source.name, systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text(DirectoryText(
                ukrainian: "Посилання перевірено \(checkedOn).",
                german: "Links geprüft am \(checkedOn)."
            ).value(for: language))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}
