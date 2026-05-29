import Foundation

func readableNewsErrorText(_ error: AppError?) -> String {
    switch error {
    case .network:
        AppStrings.News.loadNetworkError
    case .permissionDenied:
        AppStrings.News.actionPermissionError
    case .validationFailed:
        AppStrings.News.actionValidationError
    case .notFound:
        AppStrings.News.actionNotFoundError
    case .unknown:
        AppStrings.News.actionUnknownError
    case nil:
        AppStrings.News.actionUnknownError
    }
}

func sanitizedAuthorName(_ rawValue: String) -> String {
    let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
        return AppStrings.NewsEditor.authorFallback
    }

    if looksLikeRawAuthorIdentifier(trimmedValue) {
        return AppStrings.NewsEditor.authorFallback
    }

    return trimmedValue
}

private func looksLikeRawAuthorIdentifier(_ value: String) -> Bool {
    guard value.count >= 20 else { return false }
    guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }

    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return value.rangeOfCharacter(from: allowedCharacters.inverted) == nil
}

func newsPublisherText(for post: NewsPost) -> String {
    let authorName = sanitizedAuthorName(post.authorName)
    let trimmedOrganizationName = post.source.displayOrganizationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let sourceName = trimmedOrganizationName.isEmpty ? AppStrings.News.missingOrganization : trimmedOrganizationName

    guard authorName != AppStrings.NewsEditor.authorFallback else {
        return sourceName
    }

    return "\(authorName) · \(sourceName)"
}
