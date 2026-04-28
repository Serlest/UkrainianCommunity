import Foundation

enum AppError: Error, Equatable {
    case network
    case permissionDenied
    case validationFailed
    case notFound
    case unknown
}
