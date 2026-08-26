import Foundation

extension SystemLogsViewModel {
    var filteredLogs: [SystemLogEntry] {
        logs.filter { log in
            matchesSection(log)
                && matchesQuickFilters(log)
                && matchesAdvancedFilters(log)
                && matchesSearch(log)
        }
    }

    var groupedVisibleLogs: [SystemLogDayGroup] {
        guard sortOption == .newestFirst || sortOption == .oldestFirst else { return [] }
        let grouped = Dictionary(grouping: visibleLogs) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys
            .sorted(by: sortOption == .newestFirst ? (>) : (<))
            .map { date in
                SystemLogDayGroup(
                    date: date,
                    title: dayGroupTitle(for: date),
                    logs: grouped[date] ?? []
                )
            }
    }

    private func matchesSection(_ log: SystemLogEntry) -> Bool {
        switch selectedSection {
        case .all:
            true
        case .actions:
            log.category == .audit || log.category == .content || log.category == .organization || log.category == .userAccount
        case .errors:
            log.category == .diagnostics || log.severity >= .error
        case .security:
            log.retentionPolicy == .security || log.category == .authorization
        case .moderation:
            log.category == .moderation || log.retentionPolicy == .moderationDispute
        case .organizations:
            log.category == .organization || log.targetType == .organization
        case .users:
            log.category == .userAccount || log.targetType == .userProfile
        }
    }

    private func matchesQuickFilters(_ log: SystemLogEntry) -> Bool {
        guard !selectedFilters.isEmpty else { return true }

        return selectedFilters.allSatisfy { filter in
            switch filter {
            case .unreviewed:
                !log.isReviewed
            case .critical:
                log.severity == .critical
            case .today:
                calendar.isDate(log.createdAt, inSameDayAs: nowProvider())
            case .sevenDays:
                log.createdAt >= calendar.date(byAdding: .day, value: -7, to: nowProvider()) ?? nowProvider()
            }
        }
    }

    private func matchesAdvancedFilters(_ log: SystemLogEntry) -> Bool {
        if !selectedCategories.isEmpty, !selectedCategories.contains(log.category) {
            return false
        }
        if !selectedSeverities.isEmpty, !selectedSeverities.contains(log.severity) {
            return false
        }
        if !selectedOutcomes.isEmpty, log.outcome.map(selectedOutcomes.contains) != true {
            return false
        }
        switch reviewFilter {
        case .all:
            break
        case .unreviewed where log.isReviewed:
            return false
        case .reviewed where !log.isReviewed:
            return false
        default:
            break
        }

        let startDate: Date?
        switch datePreset {
        case .all:
            startDate = nil
        case .today:
            startDate = calendar.startOfDay(for: nowProvider())
        case .sevenDays:
            startDate = calendar.date(byAdding: .day, value: -7, to: nowProvider())
        case .thirtyDays:
            startDate = calendar.date(byAdding: .day, value: -30, to: nowProvider())
        }
        return startDate.map { log.createdAt >= $0 } ?? true
    }

    private func matchesSearch(_ log: SystemLogEntry) -> Bool {
        LocalSearchMatcher.matches(query: searchText, values: [searchableText(for: log)])
    }

    private func searchableText(for log: SystemLogEntry) -> String {
        [
            log.id,
            log.summary,
            log.technicalMessage,
            log.errorCode,
            log.moduleName,
            log.screenName,
            log.operationName,
            log.actorDisplayName,
            log.actorUserId,
            log.targetTitle,
            log.targetId,
            log.organizationName,
            log.organizationId,
            log.correlationId,
            log.category.rawValue,
            log.severity.rawValue,
            log.eventType.rawValue,
            log.outcome?.rawValue,
            log.metadata.values.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private func dayGroupTitle(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return AppStrings.SystemLogs.today
        }
        if calendar.isDateInYesterday(date) {
            return AppStrings.SystemLogs.yesterday
        }
        return LocalizationStore.dateString(from: date, dateStyle: .medium, timeStyle: .none)
    }

}
