import SwiftUI

struct GuideReviewBadge: View {
    let state: GuideReviewState
    let size: AppInfoChip.Size

    init(state: GuideReviewState, size: AppInfoChip.Size = .small) {
        self.state = state
        self.size = size
    }

    var body: some View {
        if let configuration = configuration(for: state) {
            AppInfoChip(
                title: configuration.title,
                systemImage: configuration.systemImage,
                tint: configuration.tint,
                fill: configuration.fill,
                border: configuration.border,
                size: size
            )
            .accessibilityLabel(configuration.title)
        }
    }

    private func configuration(for state: GuideReviewState) -> BadgeConfiguration? {
        switch state {
        case .current:
            nil
        case .dueSoon:
            BadgeConfiguration(
                title: AppStrings.Guide.reviewDueSoon,
                systemImage: "clock",
                tint: AppTheme.textSecondary,
                fill: AppTheme.surfaceGlass,
                border: AppTheme.borderSubtle
            )
        case .overdue:
            BadgeConfiguration(
                title: AppStrings.Guide.reviewOverdue,
                systemImage: "exclamationmark.circle",
                tint: AppTheme.accentSupport,
                fill: AppTheme.accentSupport.opacity(0.14),
                border: AppTheme.accentSupport.opacity(0.22)
            )
        case .archived:
            BadgeConfiguration(
                title: AppStrings.Guide.reviewArchived,
                systemImage: "archivebox",
                tint: AppTheme.textSecondary,
                fill: AppTheme.surfaceGlass,
                border: AppTheme.borderSubtle
            )
        }
    }
}

extension GuideReviewState {
    var accessibilityLabel: String? {
        switch self {
        case .current:
            nil
        case .dueSoon:
            AppStrings.Guide.reviewDueSoon
        case .overdue:
            AppStrings.Guide.reviewOverdue
        case .archived:
            AppStrings.Guide.reviewArchived
        }
    }
}

private struct BadgeConfiguration {
    let title: String
    let systemImage: String
    let tint: Color
    let fill: Color
    let border: Color?
}
