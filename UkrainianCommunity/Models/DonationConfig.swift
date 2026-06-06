import Foundation

struct DonationConfig: Equatable {
    static let collectionPath = "appConfig"
    static let documentID = "donation"

    var isEnabled: Bool
    var donationURL: String
    var titleUK: String
    var messageUK: String
    var buttonTitleUK: String
    var titleDE: String
    var messageDE: String
    var buttonTitleDE: String
    var updatedAt: Date?
    var updatedBy: String?

    static var defaults: DonationConfig {
        DonationConfig(
            isEnabled: false,
            donationURL: "",
            titleUK: "Підтримати проєкт",
            messageUK: "Ukrainian Community — некомерційний проєкт, створений для підтримки українців в Австрії. Якщо ви хочете допомогти з розвитком і підтримкою додатку, можете зробити добровільний внесок.",
            buttonTitleUK: "Підтримати",
            titleDE: "Projekt unterstützen",
            messageDE: "Ukrainian Community ist ein nicht-kommerzielles Projekt zur Unterstützung von Ukrainerinnen und Ukrainern in Österreich. Wenn Sie die Weiterentwicklung und den Betrieb der App unterstützen möchten, können Sie freiwillig spenden.",
            buttonTitleDE: "Unterstützen",
            updatedAt: nil,
            updatedBy: nil
        )
    }

    var validDonationURL: URL? {
        Self.normalizedDonationURL(from: donationURL).flatMap(URL.init(string:))
    }

    var normalizedDonationURLString: String? {
        Self.normalizedDonationURL(from: donationURL)
    }

    func normalizedForSaving() -> DonationConfig {
        var config = self
        config.donationURL = normalizedDonationURLString ?? donationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return config
    }

    static func normalizedDonationURL(from value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              trimmedValue.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }

        if let schemeSeparatorRange = trimmedValue.range(of: "://") {
            let scheme = String(trimmedValue[..<schemeSeparatorRange.lowerBound]).lowercased()
            guard scheme == "https" else { return nil }
            return validHTTPSURLString(trimmedValue)
        }

        if trimmedValue.contains(":") {
            return nil
        }

        return validHTTPSURLString("https://\(trimmedValue)")
    }

    private static func validHTTPSURLString(_ value: String) -> String? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host?.lowercased(),
              isValidDomain(host),
              let url = components.url else {
            return nil
        }
        return url.absoluteString
    }

    private static func isValidDomain(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-"
            }
        }
    }

    func title(for language: AppLanguage = LocalizationStore.language) -> String {
        localizedValue(
            ukrainian: titleUK,
            german: titleDE,
            fallback: language == .ukrainian ? Self.defaults.titleUK : Self.defaults.titleDE,
            language: language
        )
    }

    func message(for language: AppLanguage = LocalizationStore.language) -> String {
        localizedValue(
            ukrainian: messageUK,
            german: messageDE,
            fallback: language == .ukrainian ? Self.defaults.messageUK : Self.defaults.messageDE,
            language: language
        )
    }

    func buttonTitle(for language: AppLanguage = LocalizationStore.language) -> String {
        localizedValue(
            ukrainian: buttonTitleUK,
            german: buttonTitleDE,
            fallback: language == .ukrainian ? Self.defaults.buttonTitleUK : Self.defaults.buttonTitleDE,
            language: language
        )
    }

    private func localizedValue(ukrainian: String, german: String, fallback: String, language: AppLanguage) -> String {
        let value = language == .ukrainian ? ukrainian : german
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? fallback : trimmedValue
    }
}
