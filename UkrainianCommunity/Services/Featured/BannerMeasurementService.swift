import Combine
import FirebaseAuth
import FirebaseFunctions
import Foundation
import UIKit

/// Banner measurement has its own server-confirmed consent. The content analytics
/// setting cannot grant this purpose, and an old local choice never enables it.
@MainActor
final class BannerMeasurementService: ObservableObject {
    private static let privacyVersion = "2026.21"
    private static let disclosureVersion = "2026-10-12.1"
    private static let pendingWithdrawalKey = "bannerMeasurementPendingWithdrawal.v1"

    @Published private(set) var isAvailable = false
    @Published private(set) var isEnabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var hasError = false

    private var functions: Functions { Functions.functions(region: "europe-west3") }
    private let defaults: UserDefaults
    private let outbox: BannerMeasurementQueueStore
    private var principalID: String?
    private var consentID: String?
    private var isDelivering = false
    private var stateGeneration: UInt64 = 0
    private var retryAfter: Date?
    private var authHandle: NSObjectProtocol?
    private var foregroundHandle: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, startsObservers: Bool = true) {
        self.defaults = defaults
        principalID = startsObservers ? Self.verifiedUserID() : nil
        outbox = BannerMeasurementQueueStore(
            defaults: defaults, principalID: principalID, loadExisting: startsObservers
        )
        guard startsObservers else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshIdentity() }
        }
        foregroundHandle = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        Task { await refresh() }
    }

    deinit {
        if let authHandle { Auth.auth().removeStateDidChangeListener(authHandle) }
        if let foregroundHandle { NotificationCenter.default.removeObserver(foregroundHandle) }
    }

    func record(_ measurement: FeaturedBannerMeasurement) {
        refreshIdentityIfNeeded()
        guard isEnabled, let consentID, principalID != nil else { return }
        outbox.append(BannerMeasurementQueuedEvent(measurement, consentID: consentID))
        Task { await deliverPending() }
    }

    func refresh() async {
        refreshIdentityIfNeeded()
        guard let principalID, !isBusy else { return }
        stateGeneration &+= 1
        let generation = stateGeneration
        if let withdrawalID = pendingWithdrawal(for: principalID) {
            guard await sendChoice(enabled: false, consentID: withdrawalID, principalID: principalID) else { return }
            setPendingWithdrawal(nil, for: principalID)
        }
        do {
            let result = try await functions.httpsCallable("getBannerMeasurementConsent").call()
            guard self.principalID == principalID, stateGeneration == generation,
                  let data = result.data as? [String: Any] else { return }
            isAvailable = data["available"] as? Bool == true
            let grantedID = data["consentID"] as? String
            isEnabled = isAvailable && data["enabled"] as? Bool == true && grantedID != nil
            consentID = isEnabled ? grantedID : nil
            if !isEnabled { outbox.removeAll() }
            hasError = false
            retryAfter = nil
            if isEnabled { await deliverPending() }
        } catch {
            // No cached grant: a failed server read cannot silently enable collection.
            guard self.principalID == principalID, stateGeneration == generation else { return }
            isEnabled = false
            consentID = nil
            hasError = true
        }
    }

    func setEnabled(_ enabled: Bool) async {
        refreshIdentityIfNeeded()
        guard let principalID, !isBusy else { return }
        stateGeneration &+= 1
        let generation = stateGeneration
        if enabled {
            guard isAvailable, !isEnabled, pendingWithdrawal(for: principalID) == nil else { return }
            let proposedID = UUID().uuidString.lowercased()
            isBusy = true
            defer { isBusy = false }
            if await sendChoice(enabled: true, consentID: proposedID, principalID: principalID) {
                guard self.principalID == principalID, stateGeneration == generation else { return }
                consentID = proposedID
                isEnabled = true
                hasError = false
            }
        } else {
            guard let consentID else { return }
            // Stop locally before awaiting a network response. Persist a withdrawal
            // so it is retried after a connection loss or app restart.
            isEnabled = false
            self.consentID = nil
            outbox.removeAll()
            setPendingWithdrawal(consentID, for: principalID)
            isBusy = true
            defer { isBusy = false }
            if await sendChoice(enabled: false, consentID: consentID, principalID: principalID) {
                setPendingWithdrawal(nil, for: principalID)
                hasError = false
            }
        }
    }

    private func sendChoice(enabled: Bool, consentID: String, principalID: String) async -> Bool {
        do {
            let payload: [String: Any] = [
                "enabled": enabled, "consentID": consentID,
                "locale": LocalizationStore.language.rawValue == "uk" ? "uk" : "de",
                "privacyVersion": Self.privacyVersion,
                "disclosureVersion": Self.disclosureVersion,
            ]
            let result = try await functions.httpsCallable("updateBannerMeasurementConsent").call(payload)
            guard self.principalID == principalID,
                  let data = result.data as? [String: Any],
                  data["enabled"] as? Bool == enabled,
                  data["consentID"] as? String == consentID else { return false }
            return true
        } catch {
            if self.principalID == principalID { hasError = true }
            return false
        }
    }

    private func deliverPending() async {
        guard !isDelivering, let principalID, let consentID, isEnabled,
              retryAfter.map({ Date() >= $0 }) ?? true else { return }
        isDelivering = true
        defer {
            isDelivering = false
            if isEnabled && (self.principalID != principalID || self.consentID != consentID) {
                Task { await deliverPending() }
            }
        }
        outbox.prune()
        while let event = outbox.first, self.principalID == principalID,
              self.consentID == consentID, isEnabled {
            guard event.consentID == consentID else {
                outbox.removeFirst(); continue
            }
            do {
                _ = try await functions.httpsCallable("recordBannerMeasurement").call(event.payload)
                guard self.principalID == principalID, self.consentID == consentID else { return }
                outbox.removeFirst()
            } catch {
                // Keep the same event ID for retry; the server receipt prevents
                // a double count if the acknowledgement was lost.
                let failure = error as NSError
                if failure.domain == FunctionsErrorDomain,
                   [FunctionsErrorCode.invalidArgument.rawValue,
                    FunctionsErrorCode.notFound.rawValue].contains(failure.code) {
                    outbox.removeFirst()
                    continue
                }
                if failure.domain == FunctionsErrorDomain,
                   [FunctionsErrorCode.failedPrecondition.rawValue,
                    FunctionsErrorCode.permissionDenied.rawValue,
                    FunctionsErrorCode.unauthenticated.rawValue].contains(failure.code) {
                    outbox.removeAll()
                    isEnabled = false
                    self.consentID = nil
                    Task { await refresh() }
                } else {
                    retryAfter = Date().addingTimeInterval(
                        failure.domain == FunctionsErrorDomain
                            && failure.code == FunctionsErrorCode.resourceExhausted.rawValue ? 300 : 60
                    )
                }
                return
            }
        }
    }

    private func refreshIdentityIfNeeded() {
        let current = Self.verifiedUserID()
        guard principalID != current else { return }
        refreshIdentity()
    }

    private func refreshIdentity() {
        let current = Self.verifiedUserID()
        guard principalID != current else { return }
        stateGeneration &+= 1
        principalID = current
        isEnabled = false
        isAvailable = false
        consentID = nil
        outbox.switchPrincipal(to: current)
        Task { await refresh() }
    }

    private func pendingWithdrawal(for principalID: String) -> String? {
        defaults.dictionary(forKey: Self.pendingWithdrawalKey)?[principalID] as? String
    }

    private func setPendingWithdrawal(_ consentID: String?, for principalID: String) {
        var pending = defaults.dictionary(forKey: Self.pendingWithdrawalKey) ?? [:]
        pending[principalID] = consentID
        if pending.isEmpty {
            defaults.removeObject(forKey: Self.pendingWithdrawalKey)
        } else {
            defaults.set(pending, forKey: Self.pendingWithdrawalKey)
        }
    }

    private static func verifiedUserID() -> String? {
        guard let user = Auth.auth().currentUser, !user.isAnonymous,
              user.isEmailVerified else { return nil }
        return user.uid
    }
}
