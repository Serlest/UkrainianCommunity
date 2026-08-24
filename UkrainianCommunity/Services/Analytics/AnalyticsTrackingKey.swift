import Foundation

enum AnalyticsTrackingKey {
    static func daily(
        contentID: String,
        collectionScopeID: String,
        date: Date = Date()
    ) -> String {
        "\(collectionScopeID):\(AnalyticsFirestoreSchema.dailyDocumentID(for: date)):\(contentID)"
    }
}
