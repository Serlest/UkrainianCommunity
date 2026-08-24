import SwiftUI

struct ProfileStatItem: Identifiable {
    let title: String
    let value: String
    let systemImage: String

    var id: String { "\(systemImage)-\(title)" }
}


struct ProfileQuickActionItem: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let status: ProfileModuleStatus

    var id: String { "\(systemImage)-\(title)" }
}


struct ProfileQuickActionCard: View {
    let item: ProfileQuickActionItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .truncationMode(.tail)

            Text(item.subtitle)
                .font(AppTheme.cardSubtitleFont)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.eventsMetadataSpacing)
        .frame(
            maxWidth: .infinity,
            minHeight: 116,
            maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : 116,
            alignment: .topLeading
        )
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
        .opacity(item.status.isDisabled ? 0.72 : 1)
        .accessibilityElement(children: .combine)
    }
}
