import FirebaseFirestore
import FirebaseFunctions
import Foundation

nonisolated struct UserBlockFunctionRequest: Codable, Equatable {
    let targetUserId: String
    let isBlocked: Bool
}

private nonisolated struct UserBlockFunctionResponse: Codable, Equatable {
    let targetUserId: String
    let isBlocked: Bool
    let displayName: String
    let avatarURL: String?
    let updatedAt: String
}

struct CloudUserBlockingRepository: UserBlockingRepository {
    private let database: Firestore
    private let client: CloudFunctionsClient

    init(
        database: Firestore = .firestore(),
        client: CloudFunctionsClient = .shared
    ) {
        self.database = database
        self.client = client
    }

    func fetchBlockedUsers(userID: String) async throws -> [BlockedUser] {
        do {
            let snapshot = try await database
                .collection("users")
                .document(userID)
                .collection("blockedUsers")
                .getDocuments(source: .server)

            return snapshot.documents
                .map(Self.blockedUser)
                .sorted { lhs, rhs in
                    if lhs.blockedAt == rhs.blockedAt {
                        return lhs.targetUserId < rhs.targetUserId
                    }
                    return lhs.blockedAt > rhs.blockedAt
                }
        } catch let error as UserBlockingError {
            throw error
        } catch {
            throw Self.blockingError(from: error)
        }
    }

    func setBlocked(targetUserID: String, isBlocked: Bool) async throws -> UserBlockMutationReceipt {
        do {
            let response: UserBlockFunctionResponse = try await client.call(
                .setUserBlocked,
                request: UserBlockFunctionRequest(
                    targetUserId: targetUserID,
                    isBlocked: isBlocked
                )
            )
            guard let updatedAt = Self.dateFormatter.date(from: response.updatedAt) else {
                throw UserBlockingError.malformedResponse
            }
            return UserBlockMutationReceipt(
                targetUserId: response.targetUserId,
                isBlocked: response.isBlocked,
                displayName: response.displayName,
                avatarURL: response.avatarURL.flatMap(URL.init(string:)),
                updatedAt: updatedAt
            )
        } catch let error as UserBlockingError {
            throw error
        } catch {
            throw Self.blockingError(from: error)
        }
    }

    private static func blockedUser(from document: QueryDocumentSnapshot) -> BlockedUser {
        let data = document.data()
        // The document path is the authoritative relationship identity. Optional
        // denormalized fields may be missing or corrupt, but must never make an
        // existing block disappear from the visibility policy.
        let targetUserId = document.documentID
        let rawDisplayName = (data["displayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = rawDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? targetUserId
        let blockedAt = (data["blockedAt"] as? Timestamp)?.dateValue()
            ?? (data["updatedAt"] as? Timestamp)?.dateValue()
            ?? .distantPast
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? blockedAt
        let avatarURL = (data["avatarURL"] as? String).flatMap(URL.init(string:))
        return BlockedUser(
            targetUserId: targetUserId,
            displayName: displayName,
            avatarURL: avatarURL,
            blockedAt: blockedAt,
            updatedAt: updatedAt
        )
    }

    private static func blockingError(from error: Error) -> UserBlockingError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network
        }
        if nsError.domain == FirestoreErrorDomain,
           let code = FirestoreErrorCode.Code(rawValue: nsError.code) {
            switch code {
            case .permissionDenied, .unauthenticated:
                return .permissionDenied
            case .cancelled, .deadlineExceeded, .resourceExhausted, .unavailable:
                return .network
            default:
                return .unknown
            }
        }
        guard let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return .unknown
        }
        switch code {
        case .unauthenticated:
            return .authenticationRequired
        case .permissionDenied:
            return .permissionDenied
        case .notFound:
            return .targetUnavailable
        case .failedPrecondition:
            return nsError.localizedDescription.localizedCaseInsensitiveContains("own account")
                ? .ownAccount
                : .targetUnavailable
        case .unavailable, .deadlineExceeded:
            return .network
        default:
            return .unknown
        }
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
