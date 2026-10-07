import SwiftUI

struct DirectoryCategoryCard: View {
    let category: DirectoryCategory
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.accentPrimarySoft)
                    .frame(width: 48, height: 48)
                Image(systemName: category.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title.value(for: language))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(category.summary.value(for: language))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .appGlassCard()
        .accessibilityElement(children: .combine)
    }
}

struct DirectorySafetyCard: View {
    let category: DirectoryCategory
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: category.symbol)
                .font(.system(size: 26, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(category.title.value(for: language))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(category.summary.value(for: language))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppTheme.accentPrimary, AppTheme.accentPrimary.opacity(0.82)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}
