import SwiftUI

struct GuidePopularCategoriesSection: View {
    let categories: [GuideCategory]
    @Binding var selectedCategory: GuideCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderBlock(title: AppStrings.Guide.popularCategoriesTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.dashboardSpacing) {
                    GuideCategoryCard(
                        title: AppStrings.Guide.allCategories,
                        systemImage: "square.grid.2x2",
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(categories) { category in
                        GuideCategoryCard(
                            title: category.title,
                            systemImage: category.systemImage,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct GuideCategoryCard: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SoftContentCard(padding: AppTheme.organizationsCardPadding) {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.feedThumbnailRadius, style: .continuous)
                            .fill(isSelected ? AppTheme.accentPrimary : AppTheme.badgeBlueFill)

                        Image(systemName: systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isSelected ? .white : AppTheme.accentPrimary)
                    }
                    .frame(width: 44, height: 44)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(
                    width: AppTheme.organizationsCategoryCardWidth,
                    height: AppTheme.organizationsCategoryCardHeight,
                    alignment: .leading
                )
            }
        }
        .buttonStyle(.plain)
    }
}
