import Foundation

enum AppError: LocalizedError, Equatable {
    case network
    case permissionDenied
    case validationFailed
    case notFound
    case unknown
}

extension AppError {
    var errorDescription: String? {
        switch self {
        case .network: AppStrings.Errors.network
        case .permissionDenied: AppStrings.Errors.permissionDenied
        case .validationFailed: AppStrings.Errors.validationFailed
        case .notFound: AppStrings.Errors.notFound
        case .unknown: AppStrings.Errors.unknown
        }
    }

    var asNSError: NSError {
        NSError(
            domain: "AppError",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: localizedDescription]
        )
    }

    private var code: Int {
        switch self {
        case .network:
            1
        case .permissionDenied:
            2
        case .validationFailed:
            3
        case .notFound:
            4
        case .unknown:
            5
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        guard size > 0 else { return [self[...]] }

        var chunks: [ArraySlice<Element>] = []
        var currentIndex = startIndex

        while currentIndex < endIndex {
            let nextIndex = index(currentIndex, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(self[currentIndex..<nextIndex])
            currentIndex = nextIndex
        }

        return chunks
    }
}
