import SwiftUI

struct GuideTreeCategoryCard: View {
    let category: GuideCategory

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.feedThumbnailRadius, style: .continuous)
                        .fill(AppTheme.badgeBlueFill)

                    Image(systemName: category.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
                .frame(width: AppTheme.organizationsThumbnailSize, height: AppTheme.organizationsThumbnailSize)

                VStack(alignment: .leading, spacing: 4) {
                    Text(GuideCategoryPresentation.publicTitle(for: category))
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(GuideAuthoringPresentation.localized(uk: "Відкрийте розділи та перегляньте їхній вміст.", de: "Öffnen Sie Abschnitte und prüfen Sie deren Inhalte.", en: "Open sections and inspect their contents."))
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
            }
        }
    }
}

struct GuideManagementSectionCardView: View {
    let node: GuideNode

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .top, spacing: AppTheme.eventsCardHorizontalSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.feedThumbnailRadius, style: .continuous)
                        .fill(AppTheme.badgeBlueFill)

                    Image(systemName: "folder")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
                .frame(width: AppTheme.organizationsThumbnailSize, height: AppTheme.organizationsThumbnailSize)

                VStack(alignment: .leading, spacing: 4) {
                    Text(node.title)
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !node.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(node.summary)
                            .font(AppTheme.secondaryBodyFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(GuideAuthoringPresentation.localized(
                        uk: "Підрозділ",
                        de: "Unterabschnitt",
                        en: "Subsection"
                    ))
                    .font(AppTheme.metadataFont)
                    .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
            }
        }
    }
}

struct GuideManagementMaterialCard: View {
    let material: GuideMaterial

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .top, spacing: AppTheme.eventsCardHorizontalSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.feedThumbnailRadius, style: .continuous)
                        .fill(AppTheme.badgePurpleFill)

                    Image(systemName: "doc.text")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accentSupport)
                }
                .frame(width: AppTheme.organizationsThumbnailSize, height: AppTheme.organizationsThumbnailSize)

                VStack(alignment: .leading, spacing: 4) {
                    Text(material.title)
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !material.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(material.summary)
                            .font(AppTheme.secondaryBodyFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(GuideAuthoringPresentation.localized(
                        uk: "Матеріал",
                        de: "Artikel",
                        en: "Material"
                    ))
                    .font(AppTheme.metadataFont)
                    .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 12)

                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
            }
        }
    }
}
