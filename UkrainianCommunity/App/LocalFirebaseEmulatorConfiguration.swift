#if DEBUG && targetEnvironment(simulator)
import FirebaseAuth
import FirebaseAppCheck
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

/// Opt-in SDK integration tests. The project and endpoints are fixed to local
/// emulators; this configuration is absent from device and Release builds.
enum LocalFirebaseEmulatorConfiguration {
    static let projectID = "demo-uac-release-audit"

    static func configureIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { return false }
        let options = FirebaseOptions(googleAppID: "1:123456789:ios:0123456789abcdef", gcmSenderID: "123456789")
        options.projectID = projectID
        // Firebase Installations validates syntax even for a local demo project.
        options.apiKey = "AIza" + String(repeating: "0", count: 35)
        options.storageBucket = projectID + ".appspot.com"
        AppCheck.setAppCheckProviderFactory(LocalEmulatorAppCheckFactory())
        FirebaseApp.configure(options: options)
        Auth.auth().useEmulator(withHost: "127.0.0.1", port: 19099)
        let firestore = Firestore.firestore()
        firestore.useEmulator(withHost: "127.0.0.1", port: 28080)
        let settings = firestore.settings
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings
        Functions.functions(region: "europe-west3").useEmulator(withHost: "127.0.0.1", port: 15001)
        Storage.storage().useEmulator(withHost: "127.0.0.1", port: 29199)
        return true
    }
}

private final class LocalEmulatorAppCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? { LocalEmulatorAppCheckProvider() }
}

/// The Functions emulator decodes test tokens without verifying signatures.
/// This is only test transport; it is not proof of real device attestation.
private final class LocalEmulatorAppCheckProvider: NSObject, AppCheckProvider {
    func getToken(completion handler: @escaping (AppCheckToken?, Error?) -> Void) {
        let expiration = Date().addingTimeInterval(3600)
        let claims: [String: Any] = ["sub": "1:123456789:ios:0123456789abcdef",
            "aud": ["projects/123456789"], "iss": "https://firebaseappcheck.googleapis.com/123456789",
            "iat": Int(Date().timeIntervalSince1970), "exp": Int(expiration.timeIntervalSince1970)]
        guard let header = try? JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"]),
              let payload = try? JSONSerialization.data(withJSONObject: claims) else {
            handler(nil, NSError(domain: "LocalFirebaseEmulator", code: 1))
            return
        }
        func encode(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        handler(AppCheckToken(token: encode(header) + "." + encode(payload) + ".", expirationDate: expiration), nil)
    }
}
#endif
