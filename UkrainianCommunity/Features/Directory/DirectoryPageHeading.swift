import SwiftUI

struct DirectoryPageHeading: View {
    let title: String
    let summary: String
    let symbol: String?
    let isArticle: Bool

    init(title: String, summary: String, symbol: String? = nil, isArticle: Bool = false) {
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.isArticle = isArticle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.textPrimary)
            if isArticle {
                Text(summary)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .appGlassCard(material: .regularMaterial)
            } else {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
