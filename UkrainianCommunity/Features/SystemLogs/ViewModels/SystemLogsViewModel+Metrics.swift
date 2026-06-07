import Foundation

extension SystemLogsViewModel {
    var overviewMetrics: [SystemLogOverviewMetric] {
        let unreviewed = logs.filter { !$0.isReviewed }.count
        let critical = logs.filter { $0.severity == .critical }.count
        let errors = logs.filter { $0.category == .diagnostics || $0.severity >= .error }.count
        let security = logs.filter { $0.retentionPolicy == .security || $0.category == .authorization }.count
        let moderation = logs.filter { $0.category == .moderation || $0.retentionPolicy == .moderationDispute }.count

        var metrics = [
            SystemLogOverviewMetric(
                id: "unreviewed",
                title: AppStrings.SystemLogs.unreviewed,
                value: "\(unreviewed)",
                subtitle: accessMode == .owner ? AppStrings.SystemLogs.ownerUnreviewedSubtitle : AppStrings.SystemLogs.adminUnreviewedSubtitle,
                systemImage: "circle.badge.questionmark",
                tone: unreviewed > 0 ? .warning : .success
            ),
            SystemLogOverviewMetric(
                id: "critical",
                title: AppStrings.SystemLogs.critical,
                value: "\(critical)",
                subtitle: AppStrings.SystemLogs.highestLevelSubtitle,
                systemImage: "exclamationmark.triangle.fill",
                tone: critical > 0 ? .critical : .neutral
            ),
            SystemLogOverviewMetric(
                id: "errors",
                title: AppStrings.SystemLogs.errors,
                value: "\(errors)",
                subtitle: AppStrings.SystemLogs.technicalDiagnosticsSubtitle,
                systemImage: "stethoscope",
                tone: errors > 0 ? .primary : .neutral
            )
        ]

        if accessMode == .appAdmin {
            metrics.append(
                SystemLogOverviewMetric(
                    id: "moderation",
                    title: AppStrings.SystemLogs.moderation,
                    value: "\(moderation)",
                    subtitle: AppStrings.SystemLogs.adminAvailableSubtitle,
                    systemImage: "checkmark.shield",
                    tone: moderation > 0 ? .primary : .neutral
                )
            )
            return metrics
        }

        metrics.append(
            SystemLogOverviewMetric(
                id: "security",
                title: AppStrings.SystemLogs.security,
                value: "\(security)",
                subtitle: AppStrings.SystemLogs.restrictedJournalSubtitle,
                systemImage: "lock.shield",
                tone: security > 0 ? .critical : .neutral
            )
        )

        return metrics
    }
}
