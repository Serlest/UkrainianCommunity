import Foundation

/// Resolves a lost mutation response by reading the authoritative metadata.
/// The same operation ID is captured by commit; recovery never deletes media.
enum PhotoMutationRecovery {
    static func commit<Value>(
        isCurrent: () -> Bool,
        readCommitted: () async throws -> Value?,
        shouldRetry: (Error) -> Bool,
        mutation: () async throws -> Void
    ) async throws -> Value {
        for attempt in 0..<2 {
            guard isCurrent() else { throw CancellationError() }
            do {
                try await mutation()
                guard isCurrent() else { throw CancellationError() }
                guard let value = try await readCommitted() else { throw AppError.unknown }
                guard isCurrent() else { throw CancellationError() }
                return value
            } catch {
                guard isCurrent() else { throw CancellationError() }
                if let value = try? await readCommitted() {
                    guard isCurrent() else { throw CancellationError() }
                    return value
                }
                guard isCurrent() else { throw CancellationError() }
                if attempt == 0 && shouldRetry(error) { continue }
                throw error
            }
        }
        throw AppError.unknown
    }
}
