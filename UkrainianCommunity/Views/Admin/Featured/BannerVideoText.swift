import Foundation
nonisolated enum BannerVideoText {
    static func error(_ error: Error) -> String {
        switch error {
        case BannerVideoPreparationError.gifTooComplex: text("gifTooComplex")
        case BannerVideoPreparationError.tooLarge: text("tooLarge")
        default: text("error")
        }
    }
    static func text(_ key: String) -> String {
        LocalizationStore.localizedString(key, defaultValue: key, table: "BannerVideo")
    }
}
