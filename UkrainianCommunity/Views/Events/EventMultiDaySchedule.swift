import SwiftUI

/// Only timed intervals crossing a calendar day opt into the full endpoint format.
/// All-day intervals keep their existing exclusive-end presentation rules.
struct EventMultiDaySchedule {
    let start: String
    let end: String
    var range: String { "\(start) – \(end)" }

    init?(
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendar: Calendar = .current,
        locale: Locale = LocalizationStore.locale
    ) {
        guard !isAllDay, endDate > startDate,
              !calendar.isDate(startDate, inSameDayAs: endDate) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        start = formatter.string(from: startDate)
        end = formatter.string(from: endDate)
    }
}

/// Unlike compact metadata chips, a full interval must never lose an endpoint.
struct EventMultiDayScheduleLabel: View {
    let schedule: EventMultiDaySchedule

    var body: some View {
        Label(schedule.range, systemImage: "calendar")
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EventMultiDayScheduleDetails: View {
    let schedule: EventMultiDaySchedule
    let occurrenceID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            endpoint(title: AppStrings.Events.fieldStartDate, value: schedule.start)
                .accessibilityIdentifier("event.schedule.start.\(occurrenceID)")
            endpoint(title: AppStrings.Events.fieldEndDate, value: schedule.end)
                .accessibilityIdentifier("event.schedule.end.\(occurrenceID)")
        }
    }

    private func endpoint(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTheme.detailMetadataFont)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(AppTheme.detailMetadataFont.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
