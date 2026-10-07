import SwiftUI

struct DirectoryTopicOutlineView: View {
    let titles: [String]
    let language: AppLanguage
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DirectoryText(ukrainian: "У цій темі", german: "In diesem Thema").value(for: language))
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            ForEach(titles.indices, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    HStack(spacing: 10) {
                        Text(titles[index])
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.down")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .appGlassCard()
    }
}
