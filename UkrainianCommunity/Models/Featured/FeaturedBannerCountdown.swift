import Foundation

struct FeaturedBannerCountdown: Equatable {
    enum Completion: String, CaseIterable, Codable, Identifiable {
        case hideCountdown, showStarted, hideBanner
        var id: String { rawValue }
        var title: String { BannerCountdownStrings.text("completion." + rawValue) }
    }
    let targetDate: Date
    let label: String
    let germanLabel: String
    let completion: Completion

    func label(for language: AppLanguage) -> String {
        language == .german && !germanLabel.isEmpty ? germanLabel : label
    }

    func remaining(at now: Date) -> (days: Int, hours: Int, minutes: Int)? {
        let interval = targetDate.timeIntervalSince(now)
        guard interval.isFinite, interval > 0 else { return nil }
        let minutes = Int(ceil(min(interval, 1_000_000_000_000) / 60))
        return (minutes / 1440, minutes % 1440 / 60, minutes % 60)
    }

    var isValid: Bool {
        targetDate.timeIntervalSince1970.isFinite && (2000...2200).contains(Calendar(identifier: .gregorian).component(.year, from: targetDate))
            && label.utf16.count <= 40 && germanLabel.utf16.count <= 40
    }
}

enum BannerCountdownStrings {
    static func text(_ key: String) -> String {
        LocalizationStore.localizedString("banners14." + key, defaultValue: key, table: "BannerAudit")
    }
    static func remaining(_ value: (days: Int, hours: Int, minutes: Int)) -> String {
        let pieces = [(value.days, "days"), (value.hours, "hours"), (value.minutes, "minutes")]
        return pieces.filter { $0.0 > 0 || $0.1 == "minutes" }.map { "\($0.0) \(text($0.1))" }.joined(separator: " · ")
    }
}
