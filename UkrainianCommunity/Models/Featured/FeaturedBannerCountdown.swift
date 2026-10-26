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

    func remaining(at now: Date) -> (days: Int, hours: Int, minutes: Int, seconds: Int)? {
        let interval = targetDate.timeIntervalSince(now)
        guard interval.isFinite, interval > 0 else { return nil }
        let seconds = Int(ceil(min(interval, 1_000_000_000_000)))
        return (seconds / 86_400, seconds % 86_400 / 3_600, seconds % 3_600 / 60, seconds % 60)
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
    static func remaining(_ value: (days: Int, hours: Int, minutes: Int, seconds: Int)) -> String {
        let pieces = [(value.days, "days"), (value.hours, "hours"), (value.minutes, "minutes"), (value.seconds, "seconds")]
        let first = value.days > 0 ? 0 : (value.hours > 0 ? 1 : (value.minutes > 0 ? 2 : 3))
        return pieces.enumerated().dropFirst(first).map { index, piece in
            let number = index > first ? String(format: "%02d", piece.0) : String(piece.0)
            return "\(number) \(text(piece.1))"
        }.joined(separator: " · ")
    }
}
