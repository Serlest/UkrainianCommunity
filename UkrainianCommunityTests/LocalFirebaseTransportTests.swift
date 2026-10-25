#if DEBUG && targetEnvironment(simulator)
import Testing
import Foundation
@testable import UkrainianCommunity

@Suite struct LocalFirebaseTransportTests {
    @Test func storageTransportPreservesTheProfileContractAndEncodedObjectPath() throws {
        let local = try #require(URL(string: "http://127.0.0.1:29199/v0/b/ukrainiancommunity-dbd5f.firebasestorage.app/o/profileImages%2Fclosure-member%2Favatar.jpg?alt=media&token=audit-token"))
        let canonical = LocalFirebaseEmulatorConfiguration.canonicalStorageURL(local)
        if ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" {
            #expect(canonical.host == "firebasestorage.googleapis.com")
            #expect(canonical.scheme == "https")
            #expect(canonical.port == nil)
            #expect(canonical.absoluteString.contains("profileImages%2Fclosure-member%2Favatar.jpg"))
            #expect(LocalFirebaseEmulatorConfiguration.localStorageURL(canonical) == local)
        } else {
            #expect(canonical == local)
        }
    }

    @Test func unrelatedHostsBucketsAndPortsAreNeverRewritten() throws {
        for value in [
            "https://example.org/v0/b/ukrainiancommunity-dbd5f.firebasestorage.app/o/image.jpg",
            "https://firebasestorage.googleapis.com/v0/b/some-other-app/o/image.jpg",
            "http://127.0.0.1:1234/v0/b/ukrainiancommunity-dbd5f.firebasestorage.app/o/image.jpg",
            "http://localhost:29199/v0/b/ukrainiancommunity-dbd5f.firebasestorage.app/o/image.jpg"
        ] {
            let url = try #require(URL(string: value))
            #expect(LocalFirebaseEmulatorConfiguration.localStorageURL(url) == url)
            #expect(LocalFirebaseEmulatorConfiguration.canonicalStorageURL(url) == url)
        }
    }
}
#endif
