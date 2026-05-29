import SwiftUI

struct ManagedContentCard<Actions: View>: View {
    let title: String
    let subtitle: String
    let metadata: String
    let status: String
    let systemImage: String
    @ViewBuilder let actions: Actions

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)

                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AppTheme.accentPrimarySoft, in: Capsule())
                        .lineLimit(1)
                }

                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    actions
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(AppTheme.accentPrimary)
            }
        }
    }
}
struct ProfilePreviewGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct ProfileEventPreviewCard: View {
    let event: Event

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.category.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 30, height: 30)
                .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(registrationEventScheduleText(for: event))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                Label(event.city, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.eventsMetadataSpacing)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
        .accessibilityElement(children: .combine)
    }
}
