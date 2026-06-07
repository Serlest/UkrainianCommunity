import Foundation

struct SystemLogRedactionPolicy: Codable, Equatable {
    nonisolated static let redactedValue = "[redacted]"
    nonisolated static let maxSummaryLength = 500
    nonisolated static let maxTechnicalMessageLength = 1_500
    nonisolated static let maxMetadataValueLength = 300
    nonisolated static let maxMetadataEntries = 40

    let blockedMetadataKeys: Set<String>
    let blockedContentDescriptions: [String]

    nonisolated init(
        blockedMetadataKeys: Set<String> = SystemLogRedactionPolicy.defaultBlockedMetadataKeys,
        blockedContentDescriptions: [String] = SystemLogRedactionPolicy.defaultBlockedContentDescriptions
    ) {
        self.blockedMetadataKeys = blockedMetadataKeys
        self.blockedContentDescriptions = blockedContentDescriptions
    }

    nonisolated func allowsMetadataKey(_ key: String) -> Bool {
        !isBlockedMetadataKey(key)
    }

    nonisolated func redactedDraft(from draft: SystemLogDraft) -> SystemLogDraft {
        var redactedDraft = draft
        redactedDraft.summary = trimmed(draft.summary, maxLength: Self.maxSummaryLength)
        redactedDraft.technicalMessage = draft.technicalMessage.map {
            trimmed($0, maxLength: Self.maxTechnicalMessageLength)
        }
        redactedDraft.metadata = redactedMetadata(from: draft.metadata)
        return redactedDraft
    }

    private nonisolated func redactedMetadata(from metadata: [String: String]) -> [String: String] {
        let limitedMetadata = metadata
            .sorted { $0.key < $1.key }
            .prefix(Self.maxMetadataEntries)

        return limitedMetadata.reduce(into: [String: String]()) { result, item in
            if isBlockedMetadataKey(item.key) || looksLikeToken(item.value) {
                result[item.key] = Self.redactedValue
            } else {
                result[item.key] = trimmed(item.value, maxLength: Self.maxMetadataValueLength)
            }
        }
    }

    private nonisolated func isBlockedMetadataKey(_ key: String) -> Bool {
        let normalizedKey = key
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        return blockedMetadataKeys.contains { blockedKey in
            normalizedKey.contains(blockedKey.normalizedForRedactionKey)
        }
    }

    private nonisolated func looksLikeToken(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedValue = trimmedValue.lowercased()

        if lowercasedValue.hasPrefix("bearer ") || lowercasedValue.hasPrefix("basic ") {
            return true
        }

        if lowercasedValue.hasPrefix("eyj") || lowercasedValue.hasPrefix("sk_") {
            return true
        }

        let parts = trimmedValue.split(separator: ".")
        if parts.count == 3, parts.allSatisfy({ $0.count >= 10 }) {
            return true
        }

        if trimmedValue.count >= 48, trimmedValue.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
            return true
        }

        return false
    }

    private nonisolated func trimmed(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        return String(value.prefix(maxLength)) + " [truncated]"
    }
}

extension SystemLogRedactionPolicy {
    nonisolated static let `default` = SystemLogRedactionPolicy()

    nonisolated static let defaultBlockedMetadataKeys: Set<String> = [
        "password",
        "passcode",
        "token",
        "access_token",
        "refresh_token",
        "auth_token",
        "authorization",
        "auth_header",
        "authheader",
        "secret",
        "api_key",
        "private_message",
        "privatemessage",
        "message_body",
        "messagebody",
        "raw_content",
        "rawcontent",
        "full_address",
        "street_address"
    ]

    nonisolated static let defaultBlockedContentDescriptions = [
        "Passwords or passcodes",
        "Authentication, refresh, push, or device tokens",
        "Authorization headers",
        "API keys, secrets, or credential material",
        "Private message bodies or unpublished user communications",
        "Raw content bodies that may contain private user text",
        "Full street addresses or precise private locations",
        "Unnecessary personal data not required for audit review"
    ]
}

private extension String {
    nonisolated var normalizedForRedactionKey: String {
        replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}
