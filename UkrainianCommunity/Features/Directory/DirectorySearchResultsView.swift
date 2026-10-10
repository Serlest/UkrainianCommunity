import SwiftUI

struct DirectorySearchResultsView: View {
    let matches: [DirectorySearchMatch]
    let language: AppLanguage

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(matches) { match in
                NavigationLink(value: match.route) {
                    HStack(spacing: 12) {
                        Image(systemName: match.category.symbol)
                            .font(.body)
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                            .frame(width: 30)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(match.topic?.title.value(for: language) ?? match.category.title.value(for: language))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            if match.topic != nil {
                                Text(match.category.title.value(for: language))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(14)
                    .appGlassCard()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("directory.search.\(match.id)")
            }
        }
    }
}
