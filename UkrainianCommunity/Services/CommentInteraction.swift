import Combine
import FirebaseFirestore
import Foundation

enum CommentMutationResult: Equatable {
    case success
    case failure(AppError)
    case ignored
}

enum CommentLoadState: Equatable {
    case loading
    case loaded
    case failed(AppError)
}

enum CommentTextPolicy {
    nonisolated static let maximumLength = 1_000

    nonisolated static func length(_ text: String) -> Int {
        // Firestore Rules string.size() uses UTF-16 units (covered by emulator tests).
        text.utf16.count
    }

    nonisolated static func validated(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, length(trimmed) <= maximumLength else { return nil }
        return trimmed
    }
}

enum CommentErrorMapper {
    static func map(_ error: Error) -> AppError {
        if let error = error as? AppError { return error }
        let error = error as NSError
        if error.domain == NSURLErrorDomain { return .network }
        guard error.domain == FirestoreErrorDomain else { return .unknown }
        switch error.code {
        case FirestoreErrorCode.permissionDenied.rawValue, FirestoreErrorCode.unauthenticated.rawValue: return .permissionDenied
        case FirestoreErrorCode.unavailable.rawValue, FirestoreErrorCode.deadlineExceeded.rawValue: return .network
        case FirestoreErrorCode.notFound.rawValue: return .notFound
        case FirestoreErrorCode.invalidArgument.rawValue: return .validationFailed
        default: return .unknown
        }
    }

    static func message(_ error: AppError) -> String {
        switch error {
        case .network: return AppStrings.Comments.networkError
        case .permissionDenied: return AppStrings.Comments.permissionError
        case .validationFailed: return AppStrings.Comments.lengthError
        case .notFound: return AppStrings.Comments.notFoundError
        case .unknown: return AppStrings.Comments.genericError
        }
    }
}

@MainActor
final class CommentComposerState: ObservableObject {
    @Published var text = ""
    @Published private(set) var isSending = false
    @Published private(set) var error: AppError?
    private var generation = 0

    var canSend: Bool { !isSending && CommentTextPolicy.validated(text) != nil }

    @discardableResult
    func submit(_ action: (String) async -> CommentMutationResult) async -> Bool {
        guard !isSending else { return false }
        guard let submission = CommentTextPolicy.validated(text) else {
            error = .validationFailed
            return false
        }
        let draft = text
        let currentGeneration = generation
        isSending = true
        error = nil
        let result = await action(submission)
        guard generation == currentGeneration else { return false }
        isSending = false
        switch result {
        case .success:
            // The user may already be writing the next message while the request is in flight.
            if text == draft { text = "" }
            return text.isEmpty
        case .failure(let reason):
            error = reason
        case .ignored:
            break
        }
        return false
    }

    func reset() {
        generation += 1
        text = ""
        isSending = false
        error = nil
    }
}
