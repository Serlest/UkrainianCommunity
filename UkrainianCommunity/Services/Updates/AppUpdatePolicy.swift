import Foundation

/// Numeric release versions only. Build numbers are not public App Store versions.
nonisolated struct AppReleaseVersion: Comparable, Sendable {
    private let parts: [Int]

    init?(_ value: String) {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(components.count) else { return nil }
        var parsed: [Int] = []
        for component in components {
            guard !component.isEmpty, component.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(component) else { return nil }
            parsed.append(number)
        }
        while parsed.count > 1, parsed.last == 0 { parsed.removeLast() }
        parts = parsed
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

nonisolated struct AppStoreUpdate: Equatable, Sendable {
    let version: String
    static let appID = 6_772_565_024
    static let bundleID = "at.serlest.UkrainianCommunity"
    // Constructed locally, never opened from an untrusted response field.
    static let storeURL = URL(string: "https://apps.apple.com/app/id6772565024")!
}

nonisolated struct AppStoreLookupResponse: Decodable, Sendable {
    let results: [Release]

    struct Release: Decodable, Sendable {
        let trackId: Int
        let bundleId: String
        let version: String
        let minimumOsVersion: String
    }

    func availableUpdate(installedVersion: String, operatingSystem: String) -> AppStoreUpdate? {
        guard let installed = AppReleaseVersion(installedVersion),
              let system = AppReleaseVersion(operatingSystem),
              let release = results.first(where: {
                  $0.trackId == AppStoreUpdate.appID && $0.bundleId == AppStoreUpdate.bundleID
              }),
              let published = AppReleaseVersion(release.version), published > installed,
              let minimumSystem = AppReleaseVersion(release.minimumOsVersion), system >= minimumSystem else { return nil }
        return AppStoreUpdate(version: release.version)
    }
}

nonisolated enum AppStoreCountry {
    /// StoreKit uses alpha-3; the lookup API expects alpha-2. Foundation's ICU
    /// region normalization handles AUT -> AT, DEU -> DE, UKR -> UA, etc.
    static func lookupCode(storefront: String?, deviceRegion: String?) -> String? {
        let input = storefront ?? deviceRegion
        guard let input, (2...3).contains(input.count),
              input.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }),
              let code = Locale(identifier: "und_\(input.uppercased())").region?.identifier,
              code.count == 2, Locale.Region.isoRegions.contains(Locale.Region(code)) else { return nil }
        return code.lowercased()
    }
}
