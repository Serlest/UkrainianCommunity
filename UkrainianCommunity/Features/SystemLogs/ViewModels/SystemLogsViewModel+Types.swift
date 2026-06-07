import Foundation

enum SystemLogsAccessMode: Hashable {
    case owner
    case appAdmin

    var title: String {
        switch self {
        case .owner:
            AppStrings.SystemLogs.ownerTitle
        case .appAdmin:
            AppStrings.SystemLogs.appAdminTitle
        }
    }

    var subtitle: String {
        switch self {
        case .owner:
            AppStrings.SystemLogs.ownerSubtitle
        case .appAdmin:
            AppStrings.SystemLogs.appAdminSubtitle
        }
    }

    var visibleSections: [SystemLogDashboardSection] {
        switch self {
        case .owner:
            [.all, .actions, .errors, .security, .moderation]
        case .appAdmin:
            [.all, .errors, .moderation, .organizations, .users]
        }
    }
}

enum SystemLogDashboardSection: String, CaseIterable, Identifiable {
    case all
    case actions
    case errors
    case security
    case moderation
    case organizations
    case users

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: AppStrings.SystemLogs.all
        case .actions: AppStrings.SystemLogs.actions
        case .errors: AppStrings.SystemLogs.errors
        case .security: AppStrings.SystemLogs.security
        case .moderation: AppStrings.SystemLogs.moderation
        case .organizations: AppStrings.SystemLogs.organizations
        case .users: AppStrings.SystemLogs.users
        }
    }
}

enum SystemLogQuickFilter: String, CaseIterable, Identifiable {
    case unreviewed
    case critical
    case today
    case sevenDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unreviewed: AppStrings.SystemLogs.unreviewed
        case .critical: AppStrings.SystemLogs.critical
        case .today: AppStrings.SystemLogs.today
        case .sevenDays: AppStrings.SystemLogs.sevenDays
        }
    }

    var systemImage: String? {
        switch self {
        case .unreviewed: "circle.badge.questionmark"
        case .critical: "exclamationmark.triangle.fill"
        case .today: "calendar"
        case .sevenDays: "calendar.badge.clock"
        }
    }
}

struct SystemLogOverviewMetric: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tone: SystemLogMetricTone
}

enum SystemLogMetricTone: Equatable {
    case primary
    case warning
    case critical
    case success
    case neutral
}
