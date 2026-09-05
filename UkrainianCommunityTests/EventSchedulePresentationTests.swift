import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct EventSchedulePresentationTests {
    private var vienna: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return calendar
    }

    @Test(arguments: ["hackathon", "marktplatz"])
    func multiDayEndpointsRetainBothDatesAndTimes(scenario: String) throws {
        let event = try #require(MockContentBuilder.multiDayScheduleFixture(scenario: scenario))
        for localeID in ["de_AT", "uk_UA"] {
            let locale = Locale(identifier: localeID)
            let schedule = try #require(EventMultiDaySchedule(
                startDate: event.startDate, endDate: event.endDate, isAllDay: false,
                calendar: vienna, locale: locale
            ))
            let date = DateFormatter()
            date.locale = locale
            date.timeZone = vienna.timeZone
            date.dateStyle = .medium
            date.timeStyle = .none
            #expect(schedule.start.contains(date.string(from: event.startDate)))
            #expect(schedule.end.contains(date.string(from: event.endDate)))
            #expect(schedule.start.contains(scenario == "hackathon" ? "09:00" : "11:00"))
            #expect(schedule.end.contains(scenario == "hackathon" ? "16:00" : "21:00"))
            #expect(schedule.range == "\(schedule.start) – \(schedule.end)")
        }
        // Exercise the real feed/share entry point, which formerly dropped the start time.
        let actual = eventScheduleText(for: event)
        let expectedStart = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .short)
        let expectedEnd = LocalizationStore.dateString(from: event.endDate, dateStyle: .medium, timeStyle: .short)
        #expect(actual == "\(expectedStart) – \(expectedEnd)")
    }

    @Test func singleDayAllDayAndInvalidRangesDoNotOptIn() throws {
        let event = try #require(MockContentBuilder.multiDayScheduleFixture(scenario: "hackathon"))
        #expect(EventMultiDaySchedule(startDate: event.startDate, endDate: event.startDate.addingTimeInterval(3600), isAllDay: false, calendar: vienna) == nil)
        #expect(EventMultiDaySchedule(startDate: event.startDate, endDate: event.endDate, isAllDay: true, calendar: vienna) == nil)
        #expect(EventMultiDaySchedule(startDate: event.startDate, endDate: event.startDate, isAllDay: false, calendar: vienna) == nil)
        #expect(EventMultiDaySchedule(startDate: event.endDate, endDate: event.startDate, isAllDay: false, calendar: vienna) == nil)
    }

    @Test func calendarBoundaryRatherThanDurationControlsTheFormat() throws {
        let start = try #require(vienna.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23)))
        let end = try #require(vienna.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 4)))
        let schedule = try #require(EventMultiDaySchedule(startDate: start, endDate: end, isAllDay: false, calendar: vienna, locale: Locale(identifier: "de_AT")))
        #expect(schedule.start.contains("24.10.2026"))
        #expect(schedule.start.contains("23:00"))
        #expect(schedule.end.contains("25.10.2026"))
        #expect(schedule.end.contains("04:00"))
    }
}
