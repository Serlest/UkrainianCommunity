import Foundation

enum ContentDetailLoadOutcome: Equatable {
    case loaded
    case failed(AppError)
    case cancelled
}

enum ContentDetailLoadState: Equatable {
    case loading
    case content
    case failed(AppError)
}
