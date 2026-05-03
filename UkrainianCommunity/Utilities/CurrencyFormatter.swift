import Foundation

enum CurrencyFormatter {
    static func priceString(for price: Decimal?, currencyCode: String = "EUR") -> String {
        guard let price else { return AppStrings.Common.notAvailable }
        return price.formatted(.currency(code: currencyCode).locale(LocalizationStore.locale))
    }
}
