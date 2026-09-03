import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct AppUpdateTests {
    @Test func releaseVersionsAreNumericAndZeroPadded() throws {
        #expect(AppReleaseVersion("1.10")! > AppReleaseVersion("1.9")!)
        #expect(AppReleaseVersion("1.0") == AppReleaseVersion("1.0.0"))
        #expect(AppReleaseVersion("1.0.1")! < AppReleaseVersion("1.0.2")!)
        for value in ["", "1..0", "1.0-beta", "-1", " 1.0", "1.2.3.4.5", String(repeating: "9", count: 100)] {
            #expect(AppReleaseVersion(value) == nil)
        }
    }

    @Test func lookupChecksAppVersionIdentityAndOSCompatibility() throws {
        func response(version: String = "1.1", bundle: String = AppStoreUpdate.bundleID,
                      id: Int = AppStoreUpdate.appID, system: String = "17.0") -> AppStoreLookupResponse {
            AppStoreLookupResponse(results: [.init(trackId: id, bundleId: bundle, version: version, minimumOsVersion: system)])
        }
        #expect(response().availableUpdate(installedVersion: "1.0.1", operatingSystem: "17.0")?.version == "1.1")
        #expect(response(version: "1.0.1").availableUpdate(installedVersion: "1.0.1", operatingSystem: "26.0") == nil)
        #expect(response(version: "1.0").availableUpdate(installedVersion: "1.0.1", operatingSystem: "26.0") == nil)
        #expect(response().availableUpdate(installedVersion: "2.0", operatingSystem: "26.0") == nil)
        #expect(response(bundle: "wrong").availableUpdate(installedVersion: "1.0", operatingSystem: "26.0") == nil)
        #expect(response(id: 123).availableUpdate(installedVersion: "1.0", operatingSystem: "26.0") == nil)
        #expect(response(system: "27.0").availableUpdate(installedVersion: "1.0", operatingSystem: "26.0") == nil)
        #expect(response(version: "invalid").availableUpdate(installedVersion: "1.0", operatingSystem: "26.0") == nil)
        #expect(AppStoreLookupResponse(results: []).availableUpdate(installedVersion: "1.0", operatingSystem: "26.0") == nil)
    }

    @Test func decodesApplePayloadWithoutTrustingItsDestinationURL() throws {
        let data = Data("""
        {"resultCount":1,"results":[{"trackId":6772565024,"bundleId":"at.serlest.UkrainianCommunity",
        "version":"1.1.0","minimumOsVersion":"17.0","trackViewUrl":"https://untrusted.invalid"}]}
        """.utf8)
        let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        #expect(response.availableUpdate(installedVersion: "1.0.1", operatingSystem: "17.0") != nil)
        #expect(AppStoreUpdate.storeURL.absoluteString == "https://apps.apple.com/app/id6772565024")
    }

    @Test func usesAppStoreCountryNotTheSelectedContentRegionOrLanguage() {
        #expect(AppStoreCountry.lookupCode(storefront: "AUT", deviceRegion: "DE") == "at")
        #expect(AppStoreCountry.lookupCode(storefront: "DEU", deviceRegion: "AT") == "de")
        #expect(AppStoreCountry.lookupCode(storefront: "UKR", deviceRegion: "AT") == "ua")
        #expect(AppStoreCountry.lookupCode(storefront: "USA", deviceRegion: nil) == "us")
        #expect(AppStoreCountry.lookupCode(storefront: nil, deviceRegion: "AT") == "at")
        #expect(AppStoreCountry.lookupCode(storefront: "ZZZ", deviceRegion: "AT") == nil)
        #expect(AppStoreCountry.lookupCode(storefront: nil, deviceRegion: nil) == nil)
    }

    @Test func laterSuppressesOnlyThisOpeningAndBackgroundResetsIt() async {
        let client = RecordingUpdateClient()
        let controller = AppUpdatePromptController(client: client)
        await controller.checkIfNeeded()
        #expect(controller.update != nil)
        controller.later()
        await controller.checkIfNeeded()
        #expect(controller.update == nil)
        #expect(await client.calls == 1)
        controller.enteredBackground()
        await controller.checkIfNeeded()
        #expect(controller.update != nil)
        #expect(await client.calls == 2)
    }

    @Test func appStoreReturnDoesNotImmediatelyRepeatThePrompt() async {
        let client = RecordingUpdateClient()
        let controller = AppUpdatePromptController(client: client)
        await controller.checkIfNeeded()
        #expect(controller.openStore() == AppStoreUpdate.storeURL)
        controller.enteredBackground()
        await controller.checkIfNeeded()
        #expect(controller.update == nil)
        #expect(await client.calls == 1)
        controller.enteredBackground()
        await controller.checkIfNeeded()
        #expect(controller.update != nil)
        #expect(await client.calls == 2)
    }

    @Test func failedOpenAndNetworkFailureNeverLoop() async {
        let client = RecordingUpdateClient()
        let controller = AppUpdatePromptController(client: client)
        await controller.checkIfNeeded()
        _ = controller.openStore()
        controller.storeCouldNotOpen()
        await controller.checkIfNeeded()
        #expect(controller.update == nil)
        controller.enteredBackground()
        await controller.checkIfNeeded()
        #expect(controller.update != nil)
        let offline = AppUpdatePromptController(client: OfflineUpdateClient())
        await offline.checkIfNeeded()
        #expect(offline.update == nil && !offline.isPresented)
    }

    @Test func lateResponseAfterBackgroundCannotPresentInANewOpening() async {
        let client = SuspendedUpdateClient()
        let controller = AppUpdatePromptController(client: client)
        let check = Task { await controller.checkIfNeeded() }
        while await client.continuation == nil { await Task.yield() }
        controller.enteredBackground()
        await client.finish()
        await check.value
        #expect(controller.update == nil && !controller.isPresented)
    }

    @Test func simultaneousChecksShareOneRequest() async {
        let client = RecordingUpdateClient()
        let controller = AppUpdatePromptController(client: client)
        async let first: Void = controller.checkIfNeeded()
        async let second: Void = controller.checkIfNeeded()
        _ = await (first, second)
        #expect(await client.calls == 1)
    }
}

private actor RecordingUpdateClient: AppUpdateChecking {
    private(set) var calls = 0
    func availableUpdate() async throws -> AppStoreUpdate? {
        calls += 1
        return AppStoreUpdate(version: "9.0")
    }
}

private actor SuspendedUpdateClient: AppUpdateChecking {
    private(set) var continuation: CheckedContinuation<AppStoreUpdate?, Never>?
    func availableUpdate() async throws -> AppStoreUpdate? {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: AppStoreUpdate(version: "9.0")); continuation = nil }
}

private struct OfflineUpdateClient: AppUpdateChecking {
    func availableUpdate() async throws -> AppStoreUpdate? { throw URLError(.notConnectedToInternet) }
}
