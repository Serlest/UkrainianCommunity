import CryptoKit
import Foundation

nonisolated struct FeaturedBannerVideoPresentation: Codable, Equatable, Sendable {
    let assetID: String
    let descriptor: FeaturedBannerVideoDescriptor
    let playbackURL: String

    func isValid(for bannerID: String, bucket: String) -> Bool {
        let expected = SHA256.hash(data: Data((bannerID + ":" + descriptor.sha256).utf8)).map { String(format: "%02x", $0) }.joined()
        guard descriptor.isValid(for: bannerID), assetID == expected,
              let url = URLComponents(string: playbackURL), url.scheme == "https", url.host == "firebasestorage.googleapis.com",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              url.path == "/v0/b/\(bucket)/o/\(descriptor.assetPath)",
              url.queryItems?.first(where: { $0.name == "alt" })?.value == "media",
              url.queryItems?.first(where: { $0.name == "token" })?.value?.isEmpty == false else { return false }
        return true
    }
}
