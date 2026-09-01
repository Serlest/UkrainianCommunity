import Foundation

struct AuthPasswordPolicy: Equatable, Sendable {
    static let current = AuthPasswordPolicy(minimumLength: 10, maximumLength: 128)

    let minimumLength: Int
    let maximumLength: Int

    func validationError(for password: String) -> String? {
        if password.isEmpty {
            return AppStrings.Validation.authPasswordRequired
        }

        if password.count < minimumLength {
            return AppStrings.Validation.authPasswordTooShort
        }

        if password.count > maximumLength {
            return AppStrings.Validation.authPasswordTooLong
        }

        return nil
    }
}
