import SwiftUI

extension GuideHealthStatus {
    var displayTitle: String {
        switch self {
        case .current:
            GuideAuthoringPresentation.reviewCurrentTitle
        case .dueSoon:
            GuideAuthoringPresentation.dueSoonTitle
        case .overdue:
            GuideAuthoringPresentation.overdueTitle
        case .archived:
            GuideAuthoringPresentation.reviewArchivedTitle
        }
    }

    var displaySystemImage: String {
        switch self {
        case .current:
            "checkmark.circle"
        case .dueSoon:
            "clock"
        case .overdue:
            "exclamationmark.triangle"
        case .archived:
            "archivebox"
        }
    }

    var displayTint: Color {
        switch self {
        case .current:
            AppTheme.accentPrimary
        case .dueSoon:
            AppTheme.accentSupport
        case .overdue:
            AppTheme.accentDestructive
        case .archived:
            AppTheme.textSecondary
        }
    }

    var displayFill: Color {
        switch self {
        case .current:
            AppTheme.badgeBlueFill
        case .dueSoon:
            AppTheme.accentSupport.opacity(0.16)
        case .overdue:
            AppTheme.badgeRedFill
        case .archived:
            AppTheme.surfaceGlass
        }
    }
}
