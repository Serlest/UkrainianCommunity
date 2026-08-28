import Foundation

/// Prevents retention maintenance from turning every user action into a large
/// Firestore read. Maintenance remains best-effort and runs at most once per
/// account/key during the configured interval in the current app process.
actor FirestoreMaintenanceThrottle {
    static let shared = FirestoreMaintenanceThrottle()

    private var lastRuns: [String: Date] = [:]

    func shouldRun(key: String, minimumInterval: TimeInterval = 24 * 60 * 60) -> Bool {
        let now = Date()
        if let lastRun = lastRuns[key], now.timeIntervalSince(lastRun) < minimumInterval {
            return false
        }
        lastRuns[key] = now
        return true
    }
}
