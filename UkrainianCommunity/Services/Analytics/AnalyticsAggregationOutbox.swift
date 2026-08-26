import CryptoKit
import Foundation

#if canImport(FirebaseFunctions)
import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions

nonisolated struct AnalyticsDeliverySession: Sendable, Equatable {
    let principalID: String?
    let consentID: String?
    let generation: UInt64

    var isEnabled: Bool {
        principalID != nil && consentID != nil
    }
}

/// A synchronous authorization fence shared by the main-actor service and the
/// outbox actor. Updating it before scheduling actor work prevents an older
/// enqueue from becoming valid merely because its actor message arrives late.
nonisolated final class AnalyticsDeliveryAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var principalID: String?
    private var consentID: String?
    private var generation: UInt64 = 0

    func transition(principalID: String?, consentID: String?) -> AnalyticsDeliverySession {
        let normalizedPrincipalID = principalID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usablePrincipalID = normalizedPrincipalID?.isEmpty == false ? normalizedPrincipalID : nil
        let normalizedConsentID = consentID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usableConsentID = usablePrincipalID != nil && normalizedConsentID?.isEmpty == false
            ? normalizedConsentID
            : nil

        lock.lock()
        defer { lock.unlock() }

        precondition(generation < .max, "Analytics delivery generation exhausted")
        generation += 1
        self.principalID = usablePrincipalID
        self.consentID = usableConsentID
        return AnalyticsDeliverySession(
            principalID: usablePrincipalID,
            consentID: usableConsentID,
            generation: generation
        )
    }

    func isCurrent(_ session: AnalyticsDeliverySession) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return session.principalID == principalID
            && session.consentID == consentID
            && session.generation == generation
    }

    func allowsDelivery(for session: AnalyticsDeliverySession) -> Bool {
        isCurrent(session) && session.isEnabled && session.principalID != nil
    }
}

/// Diagnostics deliberately exclude NSError descriptions/userInfo: provider
/// errors may embed credentials, URLs or payloads. Retain only domains/codes.
nonisolated struct AnalyticsDeliveryFailureDiagnostic: Sendable, Equatable {
    let domain: String
    let code: Int
    let underlyingCodes: String

    init(error: Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
        var chain: [String] = []
        var underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        for _ in 0..<4 {
            guard let current = underlying else { break }
            chain.append("\(current.domain):\(current.code)")
            underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        underlyingCodes = chain.joined(separator: " -> ")
    }
}

nonisolated protocol AnalyticsAggregationDelivering: Sendable {
    func deliver(
        _ request: AnalyticsAggregationRequest,
        session: AnalyticsDeliverySession
    ) async throws -> AnalyticsAggregationResponse
}

nonisolated final class FirebaseFunctionsAnalyticsAggregationDelivery:
    AnalyticsAggregationDelivering,
    @unchecked Sendable {
    private struct CallableRequestEnvelope: Encodable, Sendable {
        let data: AnalyticsAggregationRequest
    }

    private struct CallableResponseEnvelope: Decodable, Sendable {
        let data: AnalyticsAggregationResponse?
        let result: AnalyticsAggregationResponse?
        let error: CallableErrorEnvelope?
    }

    private struct CallableErrorEnvelope: Decodable, Sendable {
        let status: String?
        let message: String?
    }

    private let region: String
    private let functionName: String
    private let urlSession: URLSession
    private let authorization: AnalyticsDeliveryAuthorization

    init(
        region: String,
        functionName: String = "trackAnalyticsEvent",
        urlSession: URLSession = .shared,
        authorization: AnalyticsDeliveryAuthorization
    ) {
        self.region = region
        self.functionName = functionName
        self.urlSession = urlSession
        self.authorization = authorization
    }

    func deliver(
        _ request: AnalyticsAggregationRequest,
        session: AnalyticsDeliverySession
    ) async throws -> AnalyticsAggregationResponse {
        try Task.checkCancellation()
        guard authorization.allowsDelivery(for: session),
              let expectedPrincipalID = session.principalID,
              let user = Auth.auth().currentUser,
              user.uid == expectedPrincipalID,
              !user.isAnonymous,
              user.isEmailVerified else {
            throw CancellationError()
        }

        // `Functions` resolves Auth context asynchronously from `Auth.currentUser`.
        // Fetching from this captured User instead binds the HTTP request to the
        // principal that owned the queue entry, even if Auth changes meanwhile.
        let authToken = try await user.getIDToken(forcingRefresh: false)
        try Task.checkCancellation()
        guard authorization.allowsDelivery(for: session),
              Self.currentVerifiedPrincipalID() == expectedPrincipalID else {
            throw CancellationError()
        }

        let appCheckToken = try await Self.appCheckToken()
        try Task.checkCancellation()
        guard authorization.allowsDelivery(for: session),
              Self.currentVerifiedPrincipalID() == expectedPrincipalID else {
            throw CancellationError()
        }

        let callableURL = try functionURL()
        var urlRequest = URLRequest(
            url: callableURL,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 70
        )
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        urlRequest.httpBody = try JSONEncoder().encode(CallableRequestEnvelope(data: request))

        let (responseData, urlResponse) = try await urlSession.data(for: urlRequest)
        try Task.checkCancellation()
        guard authorization.allowsDelivery(for: session) else {
            throw CancellationError()
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw Self.functionsError(
                code: .unavailable,
                message: "Analytics callable returned a non-HTTP response."
            )
        }

        let responseEnvelope = try? JSONDecoder().decode(
            CallableResponseEnvelope.self,
            from: responseData
        )
        if let callableError = responseEnvelope?.error {
            throw Self.functionsError(
                code: Self.functionsErrorCode(for: callableError.status),
                message: callableError.message ?? "Analytics callable failed."
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.functionsError(
                code: Self.functionsErrorCode(forHTTPStatus: httpResponse.statusCode),
                message: "Analytics callable failed with HTTP \(httpResponse.statusCode)."
            )
        }
        guard let response = responseEnvelope?.data ?? responseEnvelope?.result else {
            throw Self.functionsError(
                code: .dataLoss,
                message: "Analytics callable response was missing data."
            )
        }

        return response
    }

    private func functionURL() throws -> URL {
        guard let projectID = FirebaseApp.app()?.options.projectID,
              let url = URL(
                string: "https://\(region)-\(projectID).cloudfunctions.net/\(functionName)"
              ) else {
            throw Self.functionsError(
                code: .failedPrecondition,
                message: "Firebase project ID is unavailable."
            )
        }
        return url
    }

    private static func currentVerifiedPrincipalID() -> String? {
        guard let user = Auth.auth().currentUser,
              !user.isAnonymous,
              user.isEmailVerified else {
            return nil
        }
        return user.uid
    }

    private static func appCheckToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            AppCheck.appCheck().token(forcingRefresh: false) { token, error in
                if let token {
                    continuation.resume(returning: token.token)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: functionsError(
                        code: .unavailable,
                        message: "Firebase App Check token is unavailable."
                    ))
                }
            }
        }
    }

    private static func functionsError(
        code: FunctionsErrorCode,
        message: String
    ) -> NSError {
        NSError(
            domain: FunctionsErrorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func functionsErrorCode(for status: String?) -> FunctionsErrorCode {
        switch status?.uppercased() {
        case "CANCELLED": .cancelled
        case "INVALID_ARGUMENT": .invalidArgument
        case "DEADLINE_EXCEEDED": .deadlineExceeded
        case "NOT_FOUND": .notFound
        case "ALREADY_EXISTS": .alreadyExists
        case "PERMISSION_DENIED": .permissionDenied
        case "RESOURCE_EXHAUSTED": .resourceExhausted
        case "FAILED_PRECONDITION": .failedPrecondition
        case "ABORTED": .aborted
        case "OUT_OF_RANGE": .outOfRange
        case "UNIMPLEMENTED": .unimplemented
        case "INTERNAL": .internal
        case "UNAVAILABLE": .unavailable
        case "DATA_LOSS": .dataLoss
        case "UNAUTHENTICATED": .unauthenticated
        default: .unknown
        }
    }

    private static func functionsErrorCode(forHTTPStatus statusCode: Int) -> FunctionsErrorCode {
        switch statusCode {
        case 400: .invalidArgument
        case 401: .unauthenticated
        case 403: .permissionDenied
        case 404: .notFound
        case 409: .alreadyExists
        case 429: .resourceExhausted
        case 499: .cancelled
        case 500: .internal
        case 501: .unimplemented
        case 503: .unavailable
        case 504: .deadlineExceeded
        default: .unknown
        }
    }
}

actor AnalyticsAggregationOutbox {
    private struct Entry: Codable, Equatable, Sendable {
        let id: UUID
        let userID: String
        let consentID: String?
        let request: AnalyticsAggregationRequest
        var retryCount: Int
        var createdAtMilliseconds: Int64?
        var nextAttemptAtMilliseconds: Int64?
    }

    private struct ActiveDrain: Sendable {
        let id: UUID
        let session: AnalyticsDeliverySession
        let task: Task<Void, Never>
    }

    private struct ScheduledRetry: Sendable {
        let id: UUID
        let session: AnalyticsDeliverySession
        let task: Task<Void, Never>
    }

    private let delivery: any AnalyticsAggregationDelivering
    private let authorization: AnalyticsDeliveryAuthorization
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let reportFailure: @Sendable (AnalyticsDeliveryFailureDiagnostic, AnalyticsDeliverySession) -> Void
    private let maximumEntryCount: Int
    private let now: @Sendable () -> Date
    private let retrySleep: @Sendable (UInt64) async -> Void
    private var entries: [Entry]
    private var activeDrain: ActiveDrain?
    private var scheduledRetry: ScheduledRetry?

    private static let entryTimeToLiveMilliseconds: Int64 = 48 * 60 * 60 * 1_000
    private static let maximumBackoffSeconds = 3_600

    init(
        delivery: any AnalyticsAggregationDelivering,
        authorization: AnalyticsDeliveryAuthorization,
        userDefaults: UserDefaults = .standard,
        storageKey: String = "analyticsAggregateOutbox.v1",
        maximumEntryCount: Int = 200,
        reportFailure: @escaping @Sendable (AnalyticsDeliveryFailureDiagnostic, AnalyticsDeliverySession) -> Void = { _, _ in },
        now: @escaping @Sendable () -> Date = { Date() },
        retrySleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        precondition(maximumEntryCount > 0)
        self.delivery = delivery
        self.authorization = authorization
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.maximumEntryCount = maximumEntryCount
        self.reportFailure = reportFailure
        self.now = now
        self.retrySleep = retrySleep
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
        self.scheduledRetry = nil
    }

    func transition(to session: AnalyticsDeliverySession) {
        guard authorization.isCurrent(session) else { return }

        let isResumingActiveSession = activeDrain?.session == session
        if !isResumingActiveSession {
            activeDrain?.task.cancel()
            activeDrain = nil
        }
        if scheduledRetry?.session != session {
            scheduledRetry?.task.cancel()
            scheduledRetry = nil
        }
        pruneExpiredEntries()

        guard session.isEnabled,
              let principalID = session.principalID,
              let consentID = session.consentID else {
            scheduledRetry?.task.cancel()
            scheduledRetry = nil
            entries.removeAll()
            persist()
            return
        }

        removeEntriesOutsideSession(
            storageOwnerID: Self.storageOwnerIdentifier(for: principalID),
            consentID: consentID
        )
        persist()
        if !isResumingActiveSession {
            startDrain(for: session)
        }
    }

    func enqueue(
        _ request: AnalyticsAggregationRequest,
        session: AnalyticsDeliverySession
    ) {
        guard authorization.allowsDelivery(for: session),
              let principalID = session.principalID,
              let consentID = session.consentID else {
            return
        }

        let storageOwnerID = Self.storageOwnerIdentifier(for: principalID)
        removeEntriesOutsideSession(storageOwnerID: storageOwnerID, consentID: consentID)
        let nowMilliseconds = Self.milliseconds(since1970: now())
        entries.append(Entry(
            id: UUID(),
            userID: storageOwnerID,
            consentID: consentID,
            request: request,
            retryCount: 0,
            createdAtMilliseconds: nowMilliseconds,
            nextAttemptAtMilliseconds: nil
        ))
        pruneExpiredEntries(nowMilliseconds: nowMilliseconds)
        if entries.count > maximumEntryCount {
            entries.removeFirst(entries.count - maximumEntryCount)
        }
        persist()

        guard authorization.allowsDelivery(for: session) else {
            entries.removeAll { $0.userID == storageOwnerID }
            persist()
            return
        }
        startDrain(for: session)
    }

    func pendingEntryCount() -> Int {
        entries.count
    }

    func waitForDrain(toCompleteFor session: AnalyticsDeliverySession) async {
        guard let activeDrain, activeDrain.session == session else { return }
        await activeDrain.task.value
    }

    private func startDrain(for session: AnalyticsDeliverySession) {
        guard authorization.allowsDelivery(for: session) else { return }
        if activeDrain?.session == session { return }

        scheduledRetry?.task.cancel()
        scheduledRetry = nil
        activeDrain?.task.cancel()
        let drainID = UUID()
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.drain(for: session, drainID: drainID)
        }
        activeDrain = ActiveDrain(id: drainID, session: session, task: task)
    }

    private func drain(for session: AnalyticsDeliverySession, drainID: UUID) async {
        guard let principalID = session.principalID else {
            finishDrain(drainID)
            return
        }
        let storageOwnerID = Self.storageOwnerIdentifier(for: principalID)
        let consentID = session.consentID

        while !Task.isCancelled,
              authorization.allowsDelivery(for: session),
              activeDrain?.id == drainID {
            let nowMilliseconds = Self.milliseconds(since1970: now())
            pruneExpiredEntries(nowMilliseconds: nowMilliseconds)
            guard let index = entries.firstIndex(where: {
                $0.userID == storageOwnerID
                    && $0.consentID == consentID
                    && ($0.nextAttemptAtMilliseconds ?? .min) <= nowMilliseconds
            }) else {
                let nextAttemptAtMilliseconds = entries
                    .filter { $0.userID == storageOwnerID && $0.consentID == consentID }
                    .compactMap(\.nextAttemptAtMilliseconds)
                    .min()
                if let nextAttemptAtMilliseconds {
                    finishDrain(drainID)
                    scheduleRetry(
                        for: session,
                        at: nextAttemptAtMilliseconds,
                        relativeTo: nowMilliseconds
                    )
                    return
                }
                break
            }
            let entry = entries[index]
            do {
                _ = try await delivery.deliver(entry.request, session: session)
                guard !Task.isCancelled,
                      authorization.allowsDelivery(for: session),
                      activeDrain?.id == drainID else {
                    break
                }
                entries.removeAll { $0.id == entry.id }
                persist()
            } catch is CancellationError {
                break
            } catch {
                guard !Task.isCancelled,
                      authorization.allowsDelivery(for: session),
                      activeDrain?.id == drainID,
                      let currentIndex = entries.firstIndex(where: { $0.id == entry.id }) else {
                    break
                }

                reportFailure(AnalyticsDeliveryFailureDiagnostic(error: error), session)
                if Self.isPermanentDeliveryError(error) {
                    entries.remove(at: currentIndex)
                    persist()
                    continue
                }

                let nextRetryCount = entries[currentIndex].retryCount + 1
                entries[currentIndex].retryCount = nextRetryCount
                let failureMilliseconds = Self.milliseconds(since1970: now())
                entries[currentIndex].nextAttemptAtMilliseconds = failureMilliseconds
                    + Int64(Self.backoffSeconds(for: nextRetryCount) * 1_000)
                persist()
                // Continue with another eligible entry instead of allowing a
                // transiently failing head to block the rest of the queue.
            }
        }

        finishDrain(drainID)
    }

    private func finishDrain(_ drainID: UUID) {
        guard activeDrain?.id == drainID else { return }
        activeDrain = nil
    }

    private func scheduleRetry(
        for session: AnalyticsDeliverySession,
        at nextAttemptAtMilliseconds: Int64,
        relativeTo nowMilliseconds: Int64
    ) {
        guard authorization.allowsDelivery(for: session) else { return }

        scheduledRetry?.task.cancel()
        let retryID = UUID()
        let delayMilliseconds = min(
            Int64(Self.maximumBackoffSeconds * 1_000),
            max(0, nextAttemptAtMilliseconds - nowMilliseconds)
        )
        let nanoseconds = UInt64(delayMilliseconds) * 1_000_000
        let retrySleep = self.retrySleep
        let task = Task(priority: .utility) { [weak self] in
            await retrySleep(nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.resumeScheduledRetry(retryID, session: session)
        }
        scheduledRetry = ScheduledRetry(id: retryID, session: session, task: task)
    }

    private func resumeScheduledRetry(
        _ retryID: UUID,
        session: AnalyticsDeliverySession
    ) {
        guard scheduledRetry?.id == retryID,
              scheduledRetry?.session == session,
              authorization.allowsDelivery(for: session) else {
            return
        }

        scheduledRetry = nil
        startDrain(for: session)
    }

    private func removeEntriesOutsideSession(storageOwnerID: String, consentID: String) {
        entries.removeAll {
            $0.userID != storageOwnerID || $0.consentID != consentID
        }
    }

    private func pruneExpiredEntries() {
        pruneExpiredEntries(nowMilliseconds: Self.milliseconds(since1970: now()))
    }

    private func pruneExpiredEntries(nowMilliseconds: Int64) {
        let previousCount = entries.count
        entries.removeAll { entry in
            let createdAtMilliseconds = entry.createdAtMilliseconds
                ?? entry.request.occurredAtMilliseconds
                ?? nowMilliseconds
            return nowMilliseconds - createdAtMilliseconds
                >= Self.entryTimeToLiveMilliseconds
        }
        if entries.count != previousCount {
            persist()
        }
    }

    private static func milliseconds(since1970 date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000)
    }

    private static func backoffSeconds(for retryCount: Int) -> Int {
        let exponent = min(max(retryCount, 1), 12)
        return min(maximumBackoffSeconds, 1 << exponent)
    }

    private static func storageOwnerIdentifier(for principalID: String) -> String {
        let digest = SHA256.hash(data: Data(principalID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func persist() {
        guard !entries.isEmpty else {
            userDefaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private static func isPermanentDeliveryError(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == FunctionsErrorDomain else { return false }

        let permanentCodes: Set<Int> = [
            FunctionsErrorCode.invalidArgument.rawValue,
            FunctionsErrorCode.notFound.rawValue,
            FunctionsErrorCode.alreadyExists.rawValue,
            FunctionsErrorCode.permissionDenied.rawValue,
            FunctionsErrorCode.failedPrecondition.rawValue,
            FunctionsErrorCode.outOfRange.rawValue,
            FunctionsErrorCode.unimplemented.rawValue
        ]
        return permanentCodes.contains(error.code)
    }
}
#endif
