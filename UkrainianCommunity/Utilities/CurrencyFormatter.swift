import Foundation

enum CurrencyFormatter {
    static func priceString(for price: Decimal?) -> String {
        guard let price else { return AppStrings.Common.notAvailable }
        return price.formatted(.currency(code: "EUR").locale(LocalizationStore.locale))
    }
}
