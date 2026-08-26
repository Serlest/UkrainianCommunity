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
        #expect(newsValidator.firstIssue(in: newsInput(title: String(repeating: "a", count: 121))) == .titleTooLong)
        #expect(newsValidator.firstIssue(in: newsInput(summary: String(repeating: "a", count: 201))) == .summaryTooLong)
        #expect(newsValidator.firstIssue(in: newsInput(body: String(repeating: "a", count: 10_001))) == .bodyTooLong)
        #expect(newsValidator.firstIssue(in: newsInput(sourceInput: "ftp://example.org")) == .invalidSource)
        #expect(newsValidator.firstIssue(in: newsInput(tags: (1...9).map { "tag\($0)" })) == .tooManyTags)
        #expect(newsValidator.firstIssue(in: newsInput(tags: [String(repeating: "a", count: 31)])) == .tagTooLong)
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
        #expect(eventValidator.firstIssue(in: eventInput(minimumAgeText: "child")) == .invalidAgeValue)
        #expect(eventValidator.firstIssue(in: eventInput(maximumAgeText: "121")) == .invalidAgeValue)
        #expect(eventValidator.firstIssue(in: eventInput(minimumAgeText: "18", maximumAgeText: "12")) == .invalidAgeRange)
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

    @Test func eventEditorStepsUnlockOnlyWhenTheirRequiredFieldsAreValid() {
        let viewModel = EventEditorViewModel(
            repository: MockEventRepository(),
            mode: .create(context: .init(
                organizationId: "organization-1",
                organizationName: "Community Center",
                organizationImageURL: nil,
                organizationFederalState: .tirol
            ))
        )

        #expect(!viewModel.canAdvanceBasics)
        viewModel.title = "Community event"
        viewModel.summary = "Short summary"
        viewModel.details = "Full event description"
        #expect(viewModel.canAdvanceBasics)

        #expect(!viewModel.canAdvanceSchedule)
        viewModel.city = "Innsbruck"
        viewModel.venue = "Community Center"
        viewModel.startDate = Date().addingTimeInterval(3_600)
        viewModel.endDate = Date().addingTimeInterval(7_200)
        #expect(viewModel.canAdvanceSchedule)

        viewModel.capacityText = "0"
        #expect(!viewModel.canAdvanceAudience)
        viewModel.capacityText = "50"
        viewModel.minimumAgeText = "18"
        viewModel.maximumAgeText = "12"
        #expect(!viewModel.canAdvanceAudience)
        viewModel.maximumAgeText = "99"
        #expect(viewModel.canAdvanceAudience)
        #expect(viewModel.validationMessage == nil)
    }

    @Test(arguments: [
        "https://example.org/path?q=value#section", "example.org/path",
        "HTTPS://example.org/path", "Support-URL: https://example.org/support"
    ])
    func organizationWebLinksUseTheSameNormalizationForSavingAndDisplay(_ input: String) {
        let normalized = OrganizationWebURL.normalizedInput(input)
        let url = OrganizationWebURL.url(from: input)
        #expect(url != nil)
        #expect(normalized == url?.absoluteString)
        #expect(normalizedOrganizationURL(from: input) == url)
        let errors = OrganizationValidationService().validate(
            name: "Organization", shortDescription: "A complete organization description",
            region: .tirol, city: "Innsbruck", email: "", website: normalized, foundedYear: ""
        )
        #expect(errors.isEmpty)
    }

    @Test(arguments: [
        "javascript:alert(1)", "ftp://example.org", "https://", "https://two words.example",
        "https://trusted.example@other.example", "Support-URL: javascript:alert(1)",
        "Some text https://example.org", "Support-URL: https://one.example https://two.example"
    ])
    func organizationRejectsUnusableWebLinksWithoutErasingTheInput(_ input: String) {
        #expect(OrganizationWebURL.url(from: input) == nil)
        #expect(OrganizationWebURL.normalizedInput(input) == input)
        let errors = OrganizationValidationService().validate(
            name: "Organization", shortDescription: "A complete organization description",
            region: .tirol, city: "Innsbruck", email: "", website: input, foundedYear: ""
        )
        #expect(errors == [AppStrings.Validation.organizationWebsiteInvalid])
    }

    @Test func organizationClosedDaysRemainExplicitAndCanBeReopened() {
        let editor = OrganizationEditorViewModel(mode: .create)
        editor.setHours("09:00-18:00", for: "monday")
        editor.setHours("", for: "monday")
        #expect(editor.regularHours["monday"] == "closed")
        #expect(editor.regularHours["tuesday"] == nil)
        editor.setHours("10:00-16:00", for: "monday")
        #expect(editor.regularHours["monday"] == "10:00-16:00")
    }

    @Test func localizedContentUsesTheSelectedLanguageAndFallsBackToUkrainian() {
        let values = [
            "uk": NewsLocalizedContent(title: "Українська", subtitle: "Опис", body: "Текст"),
            "de": NewsLocalizedContent(title: "Deutsch", subtitle: "Beschreibung", body: "Text")
        ]
        #expect(values.resolved(for: .german)?.title == "Deutsch")
        #expect(values.resolved(for: .ukrainian)?.title == "Українська")
        #expect(["uk": values["uk"]!].resolved(for: .german)?.title == "Українська")
    }

    @Test func legacyNewsDraftDecodesWithoutVersionTwoOptionalFields() throws {
        let draft = NewsCreateDraft(
            version: 1,
            updatedAt: referenceDate,
            organizationId: "organization-1",
            organizationName: "Community",
            organizationImageURL: nil,
            organizationFederalState: .tirol,
            title: "Стара чернетка",
            summary: "Короткий опис",
            body: "Повний текст",
            sourceInput: "",
            tagsInput: "",
            selectedFederalState: .tirol,
            germanTitle: nil,
            germanSummary: nil,
            germanBody: nil,
            imageCaption: nil,
            imageAlternativeText: nil,
            imageCredit: nil,
            externalActionTitle: nil,
            externalActionURL: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var legacyObject = try #require(JSONSerialization.jsonObject(with: encoder.encode(draft)) as? [String: Any])
        [
            "germanTitle", "germanSummary", "germanBody", "imageCaption",
            "imageAlternativeText", "imageCredit", "externalActionTitle", "externalActionURL"
        ].forEach { legacyObject.removeValue(forKey: $0) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            NewsCreateDraft.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )

        #expect(decoded.title == draft.title)
        #expect(decoded.germanTitle == nil)
        #expect(decoded.externalActionURL == nil)
    }

    @Test func eventOccurrencesAreSortedAndResolveTheNextActiveSession() {
        let first = EventOccurrence(
            id: "first",
            startDate: referenceDate.addingTimeInterval(3_600),
            endDate: referenceDate.addingTimeInterval(7_200)
        )
        let second = EventOccurrence(
            id: "second",
            startDate: referenceDate.addingTimeInterval(86_400),
            endDate: referenceDate.addingTimeInterval(90_000)
        )
        let event = testEvent(occurrences: [second, first])
        #expect(event.occurrences.map(\.id) == ["first", "second"])
        #expect(event.startDate == first.startDate)
        #expect(event.endDate == second.endDate)
        #expect(event.nextOccurrence(relativeTo: referenceDate)?.id == "first")
        #expect(event.nextOccurrence(relativeTo: first.endDate.addingTimeInterval(1))?.id == "second")
    }

    @Test func eventEditorCapsOccurrencesAndNormalizesAllDaySessions() {
        let viewModel = EventEditorViewModel(repository: MockEventRepository(), mode: .create())
        for _ in 1..<EventEditorViewModel.maximumOccurrenceCount {
            viewModel.addOccurrence()
        }
        #expect(viewModel.allOccurrences.count == EventEditorViewModel.maximumOccurrenceCount)
        viewModel.addOccurrence()
        #expect(viewModel.allOccurrences.count == EventEditorViewModel.maximumOccurrenceCount)

        let occurrence = viewModel.additionalOccurrences[0]
        viewModel.updateOccurrence(id: occurrence.id, isAllDay: true)
        let normalized = viewModel.additionalOccurrences[0]
        #expect(normalized.isAllDay)
        #expect(Calendar.current.component(.hour, from: normalized.startDate) == 0)
        #expect(normalized.endDate > normalized.startDate)
    }

    @Test func editorsRejectOversizedOptionalPublishingFields() {
        let news = NewsEditorViewModel(
            repository: MockNewsRepository(),
            mode: .create(context: .init(
                organizationId: "organization-1",
                organizationName: "Community",
                organizationImageURL: nil,
                organizationFederalState: .tirol
            ))
        )
        news.title = "Новина"
        news.summary = "Короткий опис"
        news.body = "Повний текст"
        news.germanTitle = String(repeating: "a", count: NewsEditorViewModel.titleLimit + 1)
        #expect(news.validationMessage == ContentPublishingStrings.publishingFieldsTooLong)
        news.germanTitle = ""
        news.externalActionTitle = String(repeating: "a", count: NewsEditorViewModel.externalActionTitleLimit + 1)
        #expect(!news.canPublish)
        news.externalActionTitle = "Детальніше"
        #expect(!news.isValidExternalAction)
        news.externalActionURL = "https://example.org/details"
        #expect(news.isValidExternalAction)

        let event = EventEditorViewModel(
            repository: MockEventRepository(),
            mode: .create(context: .init(
                organizationId: "organization-1",
                organizationName: "Community",
                organizationImageURL: nil,
                organizationFederalState: .tirol
            ))
        )
        event.title = "Подія"
        event.summary = "Короткий опис"
        event.details = "Повний опис"
        event.city = "Innsbruck"
        event.venue = "Community Center"
        event.startDate = Date().addingTimeInterval(86_400)
        event.endDate = Date().addingTimeInterval(90_000)
        event.priceNote = String(repeating: "a", count: EventEditorViewModel.priceNoteLimit + 1)
        #expect(event.validationMessage == ContentPublishingStrings.publishingFieldsTooLong)
        #expect(!event.canPublish)
    }

    @Test func legacyEventDerivesCompatibleParticipationAndPricing() {
        let registered = testEvent(requiresRegistration: true, price: 15)
        #expect(registered.participationMode == .inAppRegistration)
        #expect(registered.pricing.kind == .exact)
        #expect(registered.pricing.amount == 15)

        let informational = testEvent(requiresRegistration: false, price: 0)
        #expect(informational.participationMode == .none)
        #expect(informational.pricing.kind == .free)
    }

    private func newsInput(
        title: String = "Community update",
        summary: String = "Short summary",
        body: String = "Body",
        hasOrganizer: Bool = true,
        federalState: AustrianFederalState? = .tirol,
        sourceInput: String = "",
        tags: [String] = []
    ) -> NewsValidationInput {
        NewsValidationInput(
            title: title,
            summary: summary,
            body: body,
            hasOrganizer: hasOrganizer,
            federalState: federalState,
            sourceInput: sourceInput,
            tags: tags
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
        minimumAgeText: String = "",
        maximumAgeText: String = "",
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
            minimumAgeText: minimumAgeText,
            maximumAgeText: maximumAgeText,
            federalState: federalState,
            now: referenceDate
        )
    }

    private func testEvent(
        occurrences: [EventOccurrence] = [],
        requiresRegistration: Bool = false,
        price: Double = 0
    ) -> Event {
        Event(
            id: "event",
            title: "Подія",
            summary: "Опис",
            details: "Деталі",
            city: "Innsbruck",
            venue: "Community Center",
            startDate: referenceDate.addingTimeInterval(3_600),
            endDate: referenceDate.addingTimeInterval(7_200),
            occurrences: occurrences,
            createdAt: referenceDate,
            updatedAt: referenceDate,
            requiresRegistration: requiresRegistration,
            price: price,
            capacity: nil,
            registeredCount: 0,
            comments: [],
            moderationStatus: .approved,
            registrationState: .notRegistered,
            likeCount: 0,
            likeState: .notLiked
        )
    }
}
