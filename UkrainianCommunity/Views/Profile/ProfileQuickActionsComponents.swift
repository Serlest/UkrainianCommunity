import SwiftUI

struct ProfileStatItem: Identifiable {
    let title: String
    let value: String
    let systemImage: String

    var id: String { "\(systemImage)-\(title)" }
}


struct ProfileQuickStatsGrid: View {
    let stats: [ProfileStatItem]

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.eventsMetadataSpacing) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: stat.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)

                    Text(stat.value)
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()

                    Text(stat.title)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppTheme.eventsMetadataSpacing)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                )
            }
        }
    }
}


struct ProfileQuickActionItem: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let status: ProfileModuleStatus

    var id: String { "\(systemImage)-\(title)" }
}


struct ProfileQuickActionGrid: View {
    let items: [ProfileQuickActionItem]

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.eventsMetadataSpacing) {
            ForEach(items) { item in
                ProfileQuickActionCard(item: item)
            }
        }
    }
}


struct ProfileQuickActionCard: View {
    let item: ProfileQuickActionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.status.tint)
                    .frame(width: 28, height: 28)
                    .background(item.status.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)

                if let statusTitle = item.status.title {
                    Text(statusTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.status.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(item.status.tint.opacity(0.10), in: Capsule())
                        .lineLimit(1)
                        .frame(minWidth: 70)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }

            Text(item.title)
                .font(AppTheme.buttonLabelFont)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .truncationMode(.tail)

            Text(item.subtitle)
                .font(AppTheme.cardSubtitleFont)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.eventsMetadataSpacing)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .topLeading)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
        .opacity(item.status.isDisabled ? 0.72 : 1)
        .accessibilityElement(children: .combine)
    }
}
