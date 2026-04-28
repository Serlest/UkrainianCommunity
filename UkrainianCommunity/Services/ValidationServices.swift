import Foundation

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

struct MarketplaceValidationService {
    func validate(
        title: String,
        description: String,
        city: String,
        price: Decimal?,
        isFreeGift: Bool,
        expirationDate: Date,
        contactValue: String
    ) -> [String] {
        var errors = [String]()

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AppStrings.Validation.marketplaceTitleRequired)
        }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
            errors.append(AppStrings.Validation.marketplaceDescriptionTooShort)
        }
        if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AppStrings.Validation.marketplaceCityRequired)
        }
        if contactValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(AppStrings.Validation.marketplaceContactRequired)
        }
        if !isFreeGift, let price, price < 0 {
            errors.append(AppStrings.Validation.marketplacePriceInvalid)
        }
        if expirationDate < .now {
            errors.append(AppStrings.Validation.marketplaceExpirationInvalid)
        }

        return errors
    }
}
