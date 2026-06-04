import SwiftUI

struct ProfileOrganizationPreviewCard: View {
    let title: String
    let role: String
    let status: ProfileModuleStatus

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "building.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.tint)
                .frame(width: 30, height: 30)
                .background(status.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AppTheme.buttonLabelFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(role)
                    .font(AppTheme.cardSubtitleFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let statusTitle = status.title {
                Text(statusTitle)
                    .font(AppTheme.metadataFont)
                    .foregroundStyle(status.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(status.tint.opacity(0.10), in: Capsule())
                    .lineLimit(1)
            }
        }
        .padding(AppTheme.eventsMetadataSpacing)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}
