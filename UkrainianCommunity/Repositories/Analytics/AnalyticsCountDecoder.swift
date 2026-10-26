import Foundation
import CoreFoundation

/// Analytics is produced by JavaScript: values beyond its exact integer range
/// cannot be reported as reliable counters, even when Swift's Int could hold them.
enum AnalyticsCountDecoder {
    nonisolated static let maximumExactCount = 9_007_199_254_740_991

    nonisolated static func decode(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        switch value {
        case let value as Int:
            return (0...maximumExactCount).contains(value) ? value : nil
        case let value as Int64:
            return value >= 0 && value <= Int64(maximumExactCount) ? Int(exactly: value) : nil
        case let value as NSNumber:
            let number = value.doubleValue
            guard number.isFinite, number >= 0, number <= Double(maximumExactCount),
                  number.rounded(.towardZero) == number else { return nil }
            return Int(exactly: number)
        default: return nil
        }
    }

    /// Check before building a model. Missing optional counters retain legacy zero
    /// semantics; a present malformed counter makes its source unavailable.
    nonisolated static func validates(_ data: [String: Any]) -> Bool {
        let fields: Set<String> = ["totalViews", "newsViews", "eventViews", "organizationViews", "activeRegions",
            "newsLikes", "totalLikes", "totalBookmarks", "eventRegistrations", "cancelledEventRegistrations",
            "organizationFollows", "organizationUnfollows", "viewCount", "rank", "views", "likes", "bookmarks",
            "registrations", "cancelledRegistrations", "follows", "unfollows", "profileViews", "totalUsers",
            "newRegistrations", "deletedAccounts", "blockedUsers", "deactivatedUsers", "activeUsersToday",
            "activeUsersSevenDays", "activeUsersThirtyDays"]
        // One overview reads at most 60 daily documents (current + comparison).
        // A checked budget also protects aggregate arithmetic from overflow.
        var budget = Int.max / 64
        func consume(_ value: Any) -> Bool {
            guard let count = decode(value), count <= budget else { return false }
            budget -= count; return true
        }
        func visit(_ value: Any, counters: Bool = false) -> Bool {
            if let dictionary = value as? [String: Any] {
                return dictionary.allSatisfy { key, value in
                    if counters || fields.contains(key) { return consume(value) }
                    return visit(value, counters: key == "metrics" || key == "usersByFederalState")
                }
            }
            if let array = value as? [Any] { return array.allSatisfy { visit($0) } }
            return !counters
        }
        return visit(data)
    }
}
