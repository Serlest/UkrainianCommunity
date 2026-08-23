import Foundation

enum MediaStoragePath {
    static func newsCover(newsID: String) -> String {
        "news/\(newsID)/cover.jpg"
    }

    static func eventCover(eventID: String) -> String {
        "events/\(eventID)/cover.jpg"
    }

    static func organizationLogo(organizationID: String) -> String {
        "organizations/\(organizationID)/logo.jpg"
    }

    static func organizationPhoto(organizationID: String, photoID: String) -> String {
        "organizations/\(organizationID)/photos/\(photoID).jpg"
    }

    static func profileAvatar(userID: String) -> String {
        "profileImages/\(userID)/avatar.jpg"
    }

    static func featuredBannerImage(bannerID: String, fileID: UUID = UUID()) -> String {
        "featuredBanners/\(bannerID)/hero-\(fileID.uuidString).jpg"
    }
}
