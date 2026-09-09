import Foundation
import Testing
@testable import UkrainianCommunity

struct AppErrorLocalizationTests {
    @Test(arguments: [AppError.network, .permissionDenied, .validationFailed, .notFound, .unknown])
    func erasedAndBridgedErrorsKeepTheAppMessage(_ appError: AppError) {
        let error: any Error = appError
        #expect(error.localizedDescription == appError.errorDescription)
        #expect((error as NSError).localizedDescription == appError.errorDescription)
        #expect(appError.asNSError.localizedDescription == appError.errorDescription)
        #expect(!error.localizedDescription.contains("AppError"))
    }
}
