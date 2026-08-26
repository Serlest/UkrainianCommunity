import FirebaseFunctions
import Foundation

nonisolated struct SaveCommentFunctionRequest: Codable, Equatable {
    let parentType: String
    let parentId: String
    let text: String
}

nonisolated struct SaveCommentFunctionResponse: Codable, Equatable {
    let id: String
    let parentType: String
    let parentId: String
    let authorId: String
    let authorName: String
    let authorPhotoURL: String?
    let text: String
    let createdAt: String
    let updatedAt: String?
    let moderationStatus: String
    let isDeleted: Bool
}

final class CloudCommentMutationService {
    static let shared = CloudCommentMutationService()

    private let functions: Functions
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(functions: Functions = Functions.functions(region: "europe-west3")) {
        self.functions = functions
    }

    func save(
        parentType: CommentParentType,
        parentId: String,
        text: String
    ) async throws -> Comment {
        guard let validatedText = CommentTextPolicy.validated(text) else {
            throw AppError.validationFailed
        }

        let request = SaveCommentFunctionRequest(
            parentType: parentType.rawValue,
            parentId: parentId,
            text: validatedText
        )
        let callable: Callable<SaveCommentFunctionRequest, SaveCommentFunctionResponse> =
            functions.httpsCallable("saveComment")

        do {
            let response = try await callable.call(request)
            guard let parsedParentType = CommentParentType(rawValue: response.parentType),
                  let createdAt = dateFormatter.date(from: response.createdAt) else {
                throw AppError.unknown
            }
            return Comment(
                id: response.id,
                parentType: parsedParentType,
                parentId: response.parentId,
                authorId: response.authorId,
                authorName: response.authorName,
                authorPhotoURL: response.authorPhotoURL,
                text: response.text,
                createdAt: createdAt,
                updatedAt: response.updatedAt.flatMap(dateFormatter.date(from:)),
                moderationStatus: ModerationStatus(rawValue: response.moderationStatus) ?? .approved,
                isDeleted: response.isDeleted
            )
        } catch let error as AppError {
            throw error
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> AppError {
        let error = error as NSError
        if error.domain == NSURLErrorDomain { return .network }
        guard error.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: error.code) else { return .unknown }
        switch code {
        case .invalidArgument, .failedPrecondition:
            return .validationFailed
        case .unauthenticated, .permissionDenied:
            return .permissionDenied
        case .notFound:
            return .notFound
        case .deadlineExceeded, .unavailable:
            return .network
        default:
            return .unknown
        }
    }
}
