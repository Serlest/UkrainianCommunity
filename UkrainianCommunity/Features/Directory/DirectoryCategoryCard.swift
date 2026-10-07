import SwiftUI

struct DirectoryCategoryCard: View {
    let category: DirectoryCategory
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(AppTheme.accentPrimarySoft)
                    .frame(width: 54, height: 54)
                Image(systemName: category.symbol)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            Text(category.title.value(for: language))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(category.summary.value(for: language))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
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
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 19))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(DirectoryStrings.safetyHeading)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(DirectoryStrings.safetySummary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
        .padding(18)
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
