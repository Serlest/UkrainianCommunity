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

struct NewsValidationService {
    func validate(title: String, subtitle: String, body: String) -> [String] {
        var errors = [String]()

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AppStrings.Validation.newsTitleRequired)
        }
        if subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AppStrings.Validation.newsSubtitleRequired)
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
            errors.append(AppStrings.Validation.newsBodyTooShort)
        }

        return errors
    }
}

struct EventValidationService {
    func validate(title: String, details: String, startDate: Date, endDate: Date, city: String, venue: String) -> [String] {
        var errors = [String]()

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AppStrings.Validation.eventTitleRequired)
        }
        if details.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
            errors.append(AppStrings.Validation.eventDetailsTooShort)
        }
        if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AppStrings.Validation.eventCityRequired)
        }
        if venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AppStrings.Validation.eventVenueRequired)
        }
        if endDate < startDate {
            errors.append(AppStrings.Validation.eventDateOrderInvalid)
        }

        return errors
    }
}

struct OrganizationValidationService {
    func validate(
        name: String,
        description: String,
        city: String,
        contactEmail: String,
        website: String
    ) -> [String] {
        var errors = [String]()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWebsite = website.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            errors.append(AppStrings.Validation.organizationNameRequired)
        }
        if trimmedDescription.count < 20 {
            errors.append(AppStrings.Validation.organizationDescriptionTooShort)
        }
        if trimmedCity.isEmpty {
            errors.append(AppStrings.Validation.organizationCityRequired)
        }
        if !trimmedEmail.isEmpty, !trimmedEmail.contains("@") {
            errors.append(AppStrings.Validation.organizationEmailInvalid)
        }
        if !trimmedWebsite.isEmpty,
           URL(string: trimmedWebsite)?.scheme?.isEmpty != false {
            errors.append(AppStrings.Validation.organizationWebsiteInvalid)
        }

        return errors
    }
}
