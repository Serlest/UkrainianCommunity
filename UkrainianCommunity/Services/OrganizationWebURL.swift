import Foundation

/// Shared by the organization editor and detail views. Unknown schemes and
/// malformed input are rejected, rather than silently saving unusable links.
enum OrganizationWebURL {
    nonisolated static func url(from value: String?) -> URL? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }

        // Recover the explicit label found in older records without extracting
        // arbitrary URLs from prose or changing the persisted record on read.
        let labels = ["support-url:", "website:", "webseite:", "сайт:", "вебсайт:", "url:"]
        if let label = labels.first(where: { text.lowercased().hasPrefix($0) }) {
            let candidate = String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidate.lowercased().hasPrefix("https://") || candidate.lowercased().hasPrefix("http://") else {
                return nil
            }
            text = candidate
        }

        guard text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              text.rangeOfCharacter(from: .controlCharacters) == nil,
              !text.contains("\\") else { return nil }
        let lowercased = text.lowercased()
        if !lowercased.hasPrefix("https://"), !lowercased.hasPrefix("http://") {
            guard !text.contains("://"), URL(string: text)?.scheme == nil else { return nil }
            text = "https://\(text)"
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              !host.contains("%"),
              components.user == nil, components.password == nil else { return nil }
        components.scheme = scheme
        return components.url
    }

    /// Keep rejected input intact so validation can explain it to the user.
    nonisolated static func normalizedInput(_ value: String) -> String {
        url(from: value)?.absoluteString ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
