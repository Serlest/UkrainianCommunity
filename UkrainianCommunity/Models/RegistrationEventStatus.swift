import Foundation

/// One time model for filters, ordering, cards and accessibility descriptions.
enum RegistrationEventStatus: String, CaseIterable, Identifiable {
    case upcoming, ongoing, past, cancelled
    var id: String { rawValue }

    static func resolve(_ event: Event, now: Date, calendar: Calendar = .current) -> Self {
        guard !event.isCancelled else { return .cancelled }
        let scheduled = event.occurrences.filter { $0.status == .scheduled }
        guard !scheduled.isEmpty else { return .cancelled }
        if scheduled.contains(where: { $0.startDate <= now && end(of: $0, calendar: calendar) > now }) { return .ongoing }
        return scheduled.contains(where: { $0.startDate > now }) ? .upcoming : .past
    }

    static func occurrence(for event: Event, now: Date, calendar: Calendar = .current) -> EventOccurrence {
        let sorted = event.occurrences.filter { $0.status == .scheduled }.sorted { $0.startDate < $1.startDate }
        return sorted.first { end(of: $0, calendar: calendar) > now }
            ?? sorted.last ?? event.occurrences.last
            ?? EventOccurrence(startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay)
    }

    static func displayEndDate(for occurrence: EventOccurrence, calendar: Calendar = .current) -> Date {
        guard occurrence.isAllDay else { return occurrence.endDate }
        return end(of: occurrence, calendar: calendar).addingTimeInterval(-0.001)
    }

    private static func end(of occurrence: EventOccurrence, calendar: Calendar) -> Date {
        guard occurrence.isAllDay else { return occurrence.endDate }
        // The editor stores an explicit all-day end as the next midnight (exclusive).
        // Legacy one-day records can instead have identical start and end dates.
        let endDay = calendar.startOfDay(for: occurrence.endDate)
        if occurrence.endDate > occurrence.startDate && abs(occurrence.endDate.timeIntervalSince(endDay)) < 1 {
            return occurrence.endDate
        }
        return calendar.date(byAdding: .day, value: 1, to: endDay) ?? occurrence.endDate
    }
}
