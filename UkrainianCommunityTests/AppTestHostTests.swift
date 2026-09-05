import FirebaseCore
import Foundation
import Testing
@testable import UkrainianCommunity

struct AppTestHostTests {
    @Test func ordinaryLaunchUsesTheApp() {
        #expect(!AppTestHost.isUnitTesting(arguments: [], environment: [:], hasXCTestCase: false))
    }

    @Test func hostedTestsAreRecognizedBeforeTheTestBodyRuns() {
        #expect(AppTestHost.isUnitTesting(
            arguments: [], environment: ["XCTestConfigurationFilePath": "/test/config"], hasXCTestCase: false
        ))
        #expect(AppTestHost.isUnitTesting(
            arguments: [], environment: ["XCTestBundlePath": "/test/bundle"], hasXCTestCase: false
        ))
        #expect(AppTestHost.isUnitTesting(arguments: [], environment: [:], hasXCTestCase: true))
    }

    @Test func explicitUITestLaunchKeepsItsAppEvenWithRunnerMarkers() {
        #expect(!AppTestHost.isUnitTesting(
            arguments: ["-ui-testing"],
            environment: ["XCTestConfigurationFilePath": "/test/config", "XCTestBundlePath": "/test/bundle"],
            hasXCTestCase: true
        ))
    }

    @Test @MainActor func actualUnitHostNeverConfiguresTheLiveFirebaseApp() {
        #expect(AppTestHost.isUnitTesting)
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" {
            #expect(FirebaseApp.app()?.options.projectID == LocalFirebaseEmulatorConfiguration.projectID)
            return
        }
#endif
        // Reading app() does not configure Firebase. This catches accidental host bootstrap.
        #expect(FirebaseApp.app() == nil)
    }
}
