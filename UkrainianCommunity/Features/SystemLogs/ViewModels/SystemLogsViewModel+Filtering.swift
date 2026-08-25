import Foundation

extension SystemLogsViewModel {
    var filteredLogs: [SystemLogEntry] {
        logs.filter { log in
            matchesSection(log)
                && matchesQuickFilters(log)
                && matchesSearch(log)
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

    private func matchesSearch(_ log: SystemLogEntry) -> Bool {
        LocalSearchMatcher.matches(query: searchText, values: [searchableText(for: log)])
    }

    private func searchableText(for log: SystemLogEntry) -> String {
        [
            log.summary,
            log.technicalMessage,
            log.errorCode,
            log.moduleName,
            log.screenName,
            log.operationName,
            log.actorDisplayName,
            log.targetTitle,
            log.organizationName,
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

}
