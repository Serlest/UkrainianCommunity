import Foundation

struct AuthValidationService {
    private let minimumPasswordLength = 8

    func validateLogin(email: String, password: String) -> [String] {
        var errors = [String]()
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEmail.isEmpty {
            errors.append(AppStrings.Validation.authEmailRequired)
        } else if !isValidEmail(trimmedEmail) {
            errors.append(AppStrings.Validation.authEmailInvalid)
        }

        if password.count < minimumPasswordLength {
            errors.append(AppStrings.Validation.authPasswordTooShort)
        }

        return errors
    }

    func validateRegistration(
        email: String,
        password: String,
        repeatedPassword: String,
        displayName: String,
        acceptedTerms: Bool,
        acceptedPrivacy: Bool
    ) -> [String] {
        var errors = validateLogin(email: email, password: password)

        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AppStrings.Validation.authDisplayNameRequired)
        }

        if password != repeatedPassword {
            errors.append(AppStrings.Validation.authPasswordMismatch)
        }

        if !acceptedTerms {
            errors.append(AppStrings.Validation.authTermsRequired)
        }

        if !acceptedPrivacy {
            errors.append(AppStrings.Validation.authPrivacyRequired)
        }

        return errors
    }

    func validatePasswordReset(email: String) -> [String] {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEmail.isEmpty {
            return [AppStrings.Validation.authEmailRequired]
        }

        if !isValidEmail(trimmedEmail) {
            return [AppStrings.Validation.authEmailInvalid]
        }

        return []
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}

struct NewsValidationInput {
    let title: String
    let summary: String
    let body: String
    let hasOrganizer: Bool
    let federalState: AustrianFederalState?
}

enum NewsValidationIssue: Equatable {
    case titleRequired
    case summaryRequired
    case bodyRequired
    case organizationRequired
    case organizationRegionRequired

    var message: String {
        switch self {
        case .titleRequired:
            AppStrings.NewsEditor.titleRequired
        case .summaryRequired:
            AppStrings.NewsEditor.summaryRequired
        case .bodyRequired:
            AppStrings.NewsEditor.bodyRequired
        case .organizationRequired:
            AppStrings.NewsEditor.organizationRequired
        case .organizationRegionRequired:
            AppStrings.NewsEditor.organizationRegionRequired
        }
    }
}

struct NewsValidationService {
    func firstIssue(in input: NewsValidationInput) -> NewsValidationIssue? {
        if input.title.trimmedForValidation.isEmpty {
            return .titleRequired
        }
        if input.summary.trimmedForValidation.isEmpty {
            return .summaryRequired
        }
        if input.body.trimmedForValidation.isEmpty {
            return .bodyRequired
        }
        if !input.hasOrganizer {
            return .organizationRequired
        }
        if input.federalState == nil {
            return .organizationRegionRequired
        }
        return nil
    }
}

struct EventValidationInput {
    let title: String
    let summary: String
    let details: String
    let city: String
    let venue: String
    let address: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let isEditing: Bool
    let hasOrganizer: Bool
    let requiresRegistration: Bool
    let capacityText: String
    let priceText: String
    let federalState: AustrianFederalState?
    let now: Date

    init(
        title: String,
        summary: String,
        details: String,
        city: String,
        venue: String,
        address: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        isEditing: Bool,
        hasOrganizer: Bool,
        requiresRegistration: Bool,
        capacityText: String,
        priceText: String,
        federalState: AustrianFederalState?,
        now: Date = Date()
    ) {
        self.title = title
        self.summary = summary
        self.details = details
        self.city = city
        self.venue = venue
        self.address = address
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.isEditing = isEditing
        self.hasOrganizer = hasOrganizer
        self.requiresRegistration = requiresRegistration
        self.capacityText = capacityText
        self.priceText = priceText
        self.federalState = federalState
        self.now = now
    }
}

enum EventValidationIssue: Equatable {
    case titleRequired
    case summaryRequired
    case detailsRequired
    case cityRequired
    case venueRequired
    case invalidDateOrder
    case startDateInPast
    case organizationRequired
    case invalidCapacity
    case invalidPrice
    case organizationRegionRequired

    var message: String {
        switch self {
        case .titleRequired:
            AppStrings.Validation.eventTitleRequired
        case .summaryRequired:
            AppStrings.Events.summaryRequired
        case .detailsRequired:
            AppStrings.Events.detailsRequired
        case .cityRequired:
            AppStrings.Validation.eventCityRequired
        case .venueRequired:
            AppStrings.Validation.eventVenueRequired
        case .invalidDateOrder:
            AppStrings.Events.invalidDateOrder
        case .startDateInPast:
            AppStrings.Events.startDateInPast
        case .organizationRequired:
            AppStrings.Events.organizationRequired
        case .invalidCapacity:
            AppStrings.Events.invalidCapacity
        case .invalidPrice:
            AppStrings.Events.invalidPrice
        case .organizationRegionRequired:
            AppStrings.Events.organizationRegionRequired
        }
    }
}

struct EventValidationService {
    func firstIssue(
        in input: EventValidationInput,
        calendar: Calendar = .current
    ) -> EventValidationIssue? {
        if input.title.trimmedForValidation.isEmpty {
            return .titleRequired
        }
        if input.summary.trimmedForValidation.isEmpty {
            return .summaryRequired
        }
        if input.details.trimmedForValidation.isEmpty {
            return .detailsRequired
        }
        if input.city.trimmedForValidation.isEmpty {
            return .cityRequired
        }
        if input.venue.trimmedForValidation.isEmpty,
           input.address.trimmedForValidation.isEmpty {
            return .venueRequired
        }

        let normalizedStart: Date
        let normalizedEnd: Date
        let isChronological: Bool
        if input.isAllDay {
            normalizedStart = calendar.startOfDay(for: input.startDate)
            normalizedEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: input.endDate)
            ) ?? input.endDate
            isChronological = calendar.startOfDay(for: input.endDate) >= normalizedStart
        } else {
            normalizedStart = input.startDate
            normalizedEnd = input.endDate
            isChronological = input.endDate > input.startDate
        }

        if normalizedEnd <= normalizedStart || !isChronological {
            return .invalidDateOrder
        }
        if !input.isEditing, normalizedStart < input.now.addingTimeInterval(-60) {
            return .startDateInPast
        }
        if !input.hasOrganizer {
            return .organizationRequired
        }
        if !isValidCapacity(input) {
            return .invalidCapacity
        }
        if !isValidPrice(input) {
            return .invalidPrice
        }
        if input.federalState == nil {
            return .organizationRegionRequired
        }
        return nil
    }

    private func isValidCapacity(_ input: EventValidationInput) -> Bool {
        guard input.requiresRegistration else { return true }
        let capacity = input.capacityText.trimmedForValidation
        guard !capacity.isEmpty else { return true }
        return Int(capacity).map { $0 > 0 } == true
    }

    private func isValidPrice(_ input: EventValidationInput) -> Bool {
        guard input.requiresRegistration else { return true }
        let price = input.priceText.trimmedForValidation
        guard !price.isEmpty else { return true }
        let normalizedPrice = price.replacingOccurrences(of: ",", with: ".")
        return Double(normalizedPrice).map { $0 >= 0 } == true
    }
}

private extension String {
    var trimmedForValidation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OrganizationValidationService {
    func validate(
        name: String,
        shortDescription: String,
        region: AustrianFederalState?,
        city: String,
        email: String,
        website: String,
        foundedYear: String
    ) -> [String] {
        var errors = [String]()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShortDescription = shortDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWebsite = website.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFoundedYear = foundedYear.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            errors.append(AppStrings.Validation.organizationNameRequired)
        }
        if trimmedShortDescription.count < 20 {
            errors.append(AppStrings.Validation.organizationDescriptionTooShort)
        }
        if region == nil {
            errors.append(AppStrings.Validation.organizationRegionRequired)
        }
        if !trimmedEmail.isEmpty, !trimmedEmail.contains("@") {
            errors.append(AppStrings.Validation.organizationEmailInvalid)
        }
        if !trimmedWebsite.isEmpty,
           URL(string: trimmedWebsite)?.scheme?.isEmpty != false {
            errors.append(AppStrings.Validation.organizationWebsiteInvalid)
        }
        if !trimmedFoundedYear.isEmpty {
            let currentYear = Calendar.current.component(.year, from: Date())
            if Int(trimmedFoundedYear).map({ (1800...currentYear).contains($0) }) != true {
                errors.append(AppStrings.Validation.organizationFoundedYearInvalid)
            }
        }
        _ = trimmedCity

        return errors
    }
}
