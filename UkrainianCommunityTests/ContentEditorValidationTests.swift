import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct ContentEditorValidationTests {
    private let newsValidator = NewsValidationService()
    private let eventValidator = EventValidationService()
    private let referenceDate = Date(timeIntervalSince1970: 1_788_188_400)

    @Test func newsValidatorUsesTheProductionFieldOrder() {
        #expect(newsValidator.firstIssue(in: newsInput()) == nil)
        #expect(newsValidator.firstIssue(in: newsInput(title: "   ")) == .titleRequired)
        #expect(newsValidator.firstIssue(in: newsInput(summary: "\n")) == .summaryRequired)
        #expect(newsValidator.firstIssue(in: newsInput(body: "")) == .bodyRequired)
        #expect(newsValidator.firstIssue(in: newsInput(hasOrganizer: false)) == .organizationRequired)
        #expect(newsValidator.firstIssue(in: newsInput(federalState: nil)) == .organizationRegionRequired)
    }

    @Test func eventValidatorCoversEveryProductionRequirement() {
        #expect(eventValidator.firstIssue(in: eventInput()) == nil)
        #expect(eventValidator.firstIssue(in: eventInput(title: "")) == .titleRequired)
        #expect(eventValidator.firstIssue(in: eventInput(summary: " ")) == .summaryRequired)
        #expect(eventValidator.firstIssue(in: eventInput(details: "\n")) == .detailsRequired)
        #expect(eventValidator.firstIssue(in: eventInput(city: "")) == .cityRequired)
        #expect(eventValidator.firstIssue(in: eventInput(venue: "", address: "")) == .venueRequired)
        #expect(eventValidator.firstIssue(in: eventInput(endDate: referenceDate)) == .invalidDateOrder)
        #expect(
            eventValidator.firstIssue(
                in: eventInput(
                    startDate: referenceDate.addingTimeInterval(-120),
                    endDate: referenceDate.addingTimeInterval(3_600)
                )
            ) == .startDateInPast
        )
        #expect(eventValidator.firstIssue(in: eventInput(hasOrganizer: false)) == .organizationRequired)
        #expect(eventValidator.firstIssue(in: eventInput(capacityText: "0")) == .invalidCapacity)
        #expect(eventValidator.firstIssue(in: eventInput(priceText: "free")) == .invalidPrice)
        #expect(eventValidator.firstIssue(in: eventInput(federalState: nil)) == .organizationRegionRequired)
    }

    @Test func eventValidatorPreservesSupportedEditorCases() {
        #expect(eventValidator.firstIssue(in: eventInput(venue: "", address: "Museumstraße 1")) == nil)
        #expect(
            eventValidator.firstIssue(
                in: eventInput(
                    requiresRegistration: false,
                    capacityText: "invalid",
                    priceText: "invalid"
                )
            ) == nil
        )
        #expect(
            eventValidator.firstIssue(
                in: eventInput(
                    startDate: referenceDate.addingTimeInterval(-86_400),
                    endDate: referenceDate.addingTimeInterval(-82_800),
                    isEditing: true
                )
            ) == nil
        )
        #expect(
            eventValidator.firstIssue(
                in: eventInput(
                    startDate: referenceDate.addingTimeInterval(86_400),
                    endDate: referenceDate.addingTimeInterval(86_400),
                    isAllDay: true
                )
            ) == nil
        )
    }

    private func newsInput(
        title: String = "Community update",
        summary: String = "Short summary",
        body: String = "Body",
        hasOrganizer: Bool = true,
        federalState: AustrianFederalState? = .tirol
    ) -> NewsValidationInput {
        NewsValidationInput(
            title: title,
            summary: summary,
            body: body,
            hasOrganizer: hasOrganizer,
            federalState: federalState
        )
    }

    private func eventInput(
        title: String = "Community event",
        summary: String = "Short summary",
        details: String = "Details",
        city: String = "Innsbruck",
        venue: String = "Community Center",
        address: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        isEditing: Bool = false,
        hasOrganizer: Bool = true,
        requiresRegistration: Bool = true,
        capacityText: String = "20",
        priceText: String = "10,50",
        federalState: AustrianFederalState? = .tirol
    ) -> EventValidationInput {
        EventValidationInput(
            title: title,
            summary: summary,
            details: details,
            city: city,
            venue: venue,
            address: address,
            startDate: startDate ?? referenceDate.addingTimeInterval(3_600),
            endDate: endDate ?? referenceDate.addingTimeInterval(7_200),
            isAllDay: isAllDay,
            isEditing: isEditing,
            hasOrganizer: hasOrganizer,
            requiresRegistration: requiresRegistration,
            capacityText: capacityText,
            priceText: priceText,
            federalState: federalState,
            now: referenceDate
        )
    }
}
