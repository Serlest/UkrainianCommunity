import Foundation
import Testing
@testable import UkrainianCommunity

struct AppErrorLocalizationTests {
    @Test(arguments: [AppError.network, .permissionDenied, .validationFailed, .notFound, .unknown])
    func erasedAndBridgedErrorsKeepTheAppMessage(_ appError: AppError) {
        let error: any Error = appError
        let key = appError.localizationKey
        let translations = Set(AppLanguage.allCases.compactMap { language -> String? in
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                return nil
            }
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            return value == key ? nil : value
        })

        #expect(translations.count == AppLanguage.allCases.count)
        // Other tests may switch the global app language concurrently. Each form
        // must still resolve to a real translation, whichever language was active.
        for message in [
            error.localizedDescription,
            (error as NSError).localizedDescription,
            appError.asNSError.localizedDescription,
            appError.errorDescription ?? ""
        ] {
            #expect(translations.contains(message))
            #expect(!message.contains("AppError"))
        }
    }
}

private extension AppError {
    var localizationKey: String {
        switch self {
        case .network: "app_error.network"
        case .permissionDenied: "app_error.permission_denied"
        case .validationFailed: "app_error.validation_failed"
        case .notFound: "app_error.not_found"
        case .unknown: "app_error.unknown"
        }
    }
}
