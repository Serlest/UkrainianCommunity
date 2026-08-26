import Foundation

/// Bounds a read, including SDK operations that do not respond to Swift task cancellation.
/// The operation must only return data: publish it in the caller after this await succeeds.
/// Never use this for writes, whose outcome cannot be inferred from a timeout.
@MainActor
enum RefreshRequest {
    static func run<Value>(
        timeout: Duration = .seconds(20),
        operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let race = ReadRace<Value>()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                race.continuation = continuation
                race.operation = Task {
                    do { race.finish(.success(try await operation())) }
                    catch { race.finish(.failure(error)) }
                }
                race.deadline = Task {
                    do { try await Task.sleep(for: timeout) }
                    catch { return }
                    race.finish(.failure(AppError.network))
                }
            }
        } onCancel: {
            Task { @MainActor in race.finish(.failure(CancellationError())) }
        }
    }

    private final class ReadRace<Value> {
        var continuation: CheckedContinuation<Value, Error>?
        var operation: Task<Void, Never>?
        var deadline: Task<Void, Never>?

        // An explicit deinit avoids Swift 6.3's optimizer crash for a synthesized
        // isolated generic deinit on iOS 17 (swiftlang/swift#90625).
        // finish owns cancellation and continuation cleanup; ARC needs no extra work.
        deinit {}

        func finish(_ result: Result<Value, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            operation?.cancel()
            deadline?.cancel()
            operation = nil
            deadline = nil
            continuation.resume(with: result)
        }
    }
}
